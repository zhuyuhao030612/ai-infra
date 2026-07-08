#!/usr/bin/env python3
"""skill-crystallize — GPT-5.5 powered task→SKILL.md crystallizer.

Replaces the old PowerShell+Ollama pipeline.  Sends task description +
execution log to GPT-5.5, parses the structured JSON response, and
atomically writes a reusable SKILL.md into the _auto directory.

Usage:
  python skill-crystallize.py "<task description>" --exec-log <file>
  python skill-crystallize.py "<task description>" --exec-log <file> --dry-run
  python skill-crystallize.py "<task description>" --exec-log <file> --force --json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# ── Config ──────────────────────────────────────────────────────────
GPT55_URL = os.environ.get("GPT55_URL", "http://127.0.0.1:3000/ask")
GPT55_TIMEOUT = int(os.environ.get("GPT55_CRYSTALLIZE_TIMEOUT", "300"))
GPT55_MODEL = os.environ.get("GPT55_MODEL", "gpt-5-5-thinking")
AI_ROOT = Path(os.environ.get("AI_ROOT", "D:/Code"))
SKILLS_AUTO = AI_ROOT / "ai-infra" / "skills" / "_auto"
SKILLS_APPROVED = AI_ROOT / "ai-infra" / "skills" / "approved"
RUNTIME_DIR = AI_ROOT / "ai-infra" / "runtime"

# ── Prompt Template ──────────────────────────────────────────────────
CRYSTALLIZE_PROMPT = """You are a workflow crystallization agent. Analyze the task execution below and produce a reusable SKILL.md.

## Task
{task_description}

## Execution Log
{execution_log}

## Outcome: {outcome}
## Existing skills (avoid duplicates): {existing_skills}

Write a concise, reusable SKILL.md in plain Markdown.  Make it:
- **GENERIC**: use <placeholders> not specific values from this log
- **ACTIONABLE**: every step has Tool → Action → Output
- **SELF-CONTAINED**: all context needed is in the skill itself

Use exactly this structure:

# <skill-name> — <one-line description>

## When to use
- <condition 1>
- <condition 2>

## Steps
### Step 1: <Name>
- Tool: <tool>
- Action: <specific action>
- Output: <expected output>

### Step 2: <Name>
- Tool: <tool>
- Action: <specific action>
- Output: <expected output>

## Pitfalls
- <pitfall 1>

## Verification
1. <check 1>

## Anti-patterns
- <anti-pattern 1>

If the task is NOT worth crystallizing (trivial one-off, no reusable pattern), output exactly: SKIP: <reason>"""


# ── GPT-5.5 API (SSE streaming) ─────────────────────────────────────
def call_gpt55(prompt: str, timeout: int = GPT55_TIMEOUT) -> dict | None:
    """Send prompt to GPT-5.5 streaming endpoint, collect full response."""
    body = json.dumps({"prompt": prompt, "model": GPT55_MODEL}, ensure_ascii=False)
    data = body.encode("utf-8")

    stream_url = GPT55_URL.replace("/ask", "/ask/stream")
    req = urllib.request.Request(
        stream_url,
        data=data,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "text/event-stream",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            full_text = _read_sse(resp)
    except Exception as exc:
        print(f"[crystallize] GPT-5.5 streaming failed: {exc}", file=sys.stderr)
        return None

    if not full_text:
        print("[crystallize] Empty streaming response from GPT-5.5", file=sys.stderr)
        return None

    # Log response size
    print(f"[crystallize] GPT-5.5 response: {len(full_text)} chars", file=sys.stderr)

    # Check for skip signal
    if full_text.strip().startswith("SKIP:"):
        reason = full_text.strip()[5:].strip()
        return {"crystallize": False, "reason": reason}

    return _parse_markdown_skill(full_text)


def _parse_markdown_skill(text: str) -> dict | None:
    """Parse GPT-5.5's markdown output into skill metadata + content.

    Extracts skill_name and description from the H1 heading,
    derives category from content keywords.
    """
    text = text.strip()

    # Extract H1 heading: "# skill-name — description" or "# skill-name - description"
    h1_match = re.match(r"^#\s+(\S[^—\-\n]+?)\s*[—\-]\s*(.+?)(?:\n|$)", text)
    if not h1_match:
        # Try without description fallback
        h1_match = re.match(r"^#\s+(.+)", text)
        if h1_match:
            name_part = h1_match.group(1).strip().lower().replace(" ", "-")
            name_part = re.sub(r"[^a-z0-9-]", "", name_part)[:50]
            desc = h1_match.group(1).strip()
            return {
                "crystallize": True,
                "skill_name": name_part,
                "skill_description": desc,
                "skill_content": text,
                "category": _guess_category(text),
                "tags": _guess_tags(text),
            }
        print("[crystallize] Could not parse skill heading", file=sys.stderr)
        return None

    name_raw = h1_match.group(1).strip()
    description = h1_match.group(2).strip()

    # Derive slug from name
    skill_name = re.sub(r"[^a-z0-9\s-]", "", name_raw.lower())
    skill_name = re.sub(r"\s+", "-", skill_name)[:60]

    return {
        "crystallize": True,
        "skill_name": skill_name,
        "skill_description": description,
        "skill_content": text,
        "category": _guess_category(text),
        "tags": _guess_tags(text),
    }


def _guess_category(text: str) -> str:
    """Guess skill category from content keywords."""
    lower = text.lower()
    if any(kw in lower for kw in ("security", "vulnerab", "exploit", "auth", "token")):
        return "security"
    if any(kw in lower for kw in ("debug", "trace", "error", "crash", "bug")):
        return "debugging"
    if any(kw in lower for kw in ("deploy", "ci/cd", "docker", "infra", "server")):
        return "devops"
    if any(kw in lower for kw in ("test", "assert", "mock", "fixture")):
        return "testing"
    if any(kw in lower for kw in ("refactor", "extract", "simplify", "clean")):
        return "refactoring"
    return "workflow"


def _guess_tags(text: str) -> list[str]:
    """Extract likely tags from content."""
    tags = set()
    lower = text.lower()
    tool_map = {
        "git": "git", "powershell": "powershell", "bash": "bash",
        "python": "python", "node": "nodejs", "grep": "search",
        "edit": "edit", "write": "write", "curl": "api",
        "playwright": "playwright", "mcp": "mcp", "ollama": "ollama",
    }
    for kw, tag in tool_map.items():
        if kw in lower:
            tags.add(tag)
    return sorted(tags)[:5]


def _read_sse(response) -> str:
    """Read Server-Sent Events stream, block until 'done' event received.

    Returns the full collected text from the final 'done' event.
    """
    full_text = ""
    buffer = ""
    current_event = ""
    done_received = False
    start_time = time.time()
    timeout = GPT55_TIMEOUT

    while not done_received:
        # Check timeout
        if time.time() - start_time > timeout:
            print("[crystallize] SSE read timed out", file=sys.stderr)
            break

        try:
            chunk = response.read(4096)
        except Exception:
            time.sleep(0.5)
            continue

        if chunk:
            buffer += chunk.decode("utf-8", errors="replace")
        else:
            # No data available yet — wait briefly, then retry
            time.sleep(0.5)
            continue

        # Process complete lines
        while "\n" in buffer:
            line, buffer = buffer.split("\n", 1)
            line = line.rstrip("\r")

            if line.startswith("event: "):
                current_event = line[7:].strip()
            elif line.startswith("data: "):
                data_str = line[6:]
                if data_str == "[DONE]":
                    continue
                try:
                    data = json.loads(data_str)
                    if current_event == "token":
                        txt = data.get("text", "")
                        if txt:
                            print(".", end="", file=sys.stderr, flush=True)
                    elif current_event == "done":
                        full_text = data.get("text", "") or ""
                        done_received = True
                        break
                    elif current_event == "error":
                        print(f"\n[crystallize] SSE error: {data.get('message', 'unknown')}", file=sys.stderr)
                        done_received = True
                        break
                except json.JSONDecodeError:
                    pass

    print(file=sys.stderr)  # newline after progress dots
    return full_text


def _extract_json(text: str) -> dict | None:
    """Robust JSON extraction from GPT-5.5 response.

    Handles: pure JSON, JSON in markdown fences, leading/trailing noise.
    """
    # Strip 【完成】 markers
    text = re.sub(r"【完[成]?】", "", text)

    # Try pure JSON first
    try:
        return json.loads(text.strip())
    except json.JSONDecodeError:
        pass

    # Try extracting from ```json fences
    m = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if m:
        try:
            return json.loads(m.group(1).strip())
        except json.JSONDecodeError:
            pass

    # Try finding first { ... } block
    m = re.search(r"\{[\s\S]*\}", text)
    if m:
        try:
            return json.loads(m.group(0))
        except json.JSONDecodeError:
            pass

    return None


# ── Validation ───────────────────────────────────────────────────────
def is_powershell_junk(content: str) -> bool:
    """Detect if content is serialized PowerShell objects instead of Markdown."""
    junk_markers = [
        r"@\{When to use=",
        r"@\{.*?=.*?;.*?=",
        r"^\s*@{",  # PowerShell hashtable start at line beginning
    ]
    for marker in junk_markers:
        if re.search(marker, content, re.MULTILINE):
            return True
    return False


def validate_skill(result: dict) -> list[str]:
    """Validate crystallized skill, return list of issues (empty = valid)."""
    issues = []

    if not result.get("crystallize"):
        return issues  # intentionally skipped, not an error

    name = result.get("skill_name", "")
    content = result.get("skill_content", "")

    if not re.match(r"^[a-z0-9][a-z0-9._-]{0,63}$", name):
        issues.append(f"Invalid skill_name: {name!r}")

    if len(content) < 80:
        issues.append(f"skill_content too short ({len(content)} chars, need >=80)")

    if is_powershell_junk(content):
        issues.append("skill_content contains PowerShell serialization junk — rejecting")

    # Must have at least one H1 and one H2 heading
    if not re.search(r"^#\s+", content, re.MULTILINE):
        issues.append("skill_content has no H1 heading")
    if not re.search(r"^##\s+", content, re.MULTILINE):
        issues.append("skill_content has no H2 sections")

    # Must have at least one "Step" or actionable instruction
    if not re.search(r"(Step\s*\d|Tool:|Action:|Output:)", content, re.IGNORECASE):
        issues.append("skill_content has no actionable steps (Tool/Action/Output)")

    return issues


# ── File I/O ─────────────────────────────────────────────────────────
def atomic_write(path: Path, content: str) -> bool:
    """Write file atomically via temp + rename."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    try:
        tmp.write_text(content, encoding="utf-8")
        tmp.replace(path)
        return True
    except Exception as exc:
        print(f"[crystallize] Write failed: {exc}", file=sys.stderr)
        return False


def build_skill_md(result: dict) -> str:
    """Build complete SKILL.md with YAML frontmatter."""
    name = result["skill_name"]
    desc = result.get("skill_description", "")
    category = result.get("category", "workflow")
    tags = result.get("tags", [])
    content = result["skill_content"]

    tags_yaml = ", ".join(tags)
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    return f"""---
name: {name}
description: {desc}
version: 0.1.0
auto_generated: true
generated_date: {date_str}
category: {category}
tags: [{tags_yaml}]
---

{content}
"""


def load_existing_skills() -> list[str]:
    """Scan _auto and approved dirs for existing skill names."""
    names = []
    for d in (SKILLS_AUTO, SKILLS_APPROVED):
        if d.is_dir():
            for child in d.iterdir():
                if child.is_dir() and (child / "SKILL.md").exists():
                    names.append(child.name)
    return names


# ── Main ─────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Crystallize a task into a reusable SKILL.md via GPT-5.5"
    )
    parser.add_argument(
        "task_description",
        nargs="+",
        help="Task description to crystallize",
    )
    parser.add_argument(
        "--exec-log",
        dest="exec_log_file",
        required=True,
        help="Path to execution log file",
    )
    parser.add_argument(
        "--outcome",
        default="success",
        help="Task outcome (default: success)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview only, don't write",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Skip complexity threshold check",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output result as JSON",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=GPT55_TIMEOUT,
        help=f"GPT-5.5 timeout in seconds (default: {GPT55_TIMEOUT})",
    )

    args = parser.parse_args()
    task_desc = " ".join(args.task_description)

    # Load execution log
    log_path = Path(args.exec_log_file)
    if not log_path.exists():
        print(f"ERR: execution log not found: {log_path}", file=sys.stderr)
        sys.exit(1)

    exec_log = log_path.read_text(encoding="utf-8", errors="replace")

    # Phase 1: Complexity check
    tool_patterns = [
        "WebSearch", "WebFetch", "Grep", "Glob", "Read", "Write", "Edit",
        "Bash", "PowerShell", r"Agent\(", r"Workflow\(", r"Skill\(",
    ]
    tool_count = sum(len(re.findall(p, exec_log, re.IGNORECASE)) for p in tool_patterns)
    print(f"[crystallize] Phase 1: Tool calls detected: ~{tool_count}")

    if tool_count < 5 and not args.force:
        print("[crystallize] SKIP: too few tool calls (< 5). Use --force.")
        sys.exit(0)

    if args.outcome != "success" and not args.force:
        print("[crystallize] SKIP: task did not succeed. Use --force.")
        sys.exit(0)

    # Phase 2: Duplicate check
    existing = load_existing_skills()
    print(f"[crystallize] Phase 2: Existing skills: {len(existing)}")

    # Phase 3-4: Call GPT-5.5
    print("[crystallize] Phase 3-4: Sending to GPT-5.5...")
    prompt = CRYSTALLIZE_PROMPT.format(
        task_description=task_desc,
        execution_log=exec_log[:32000],  # Truncate to avoid overflow
        outcome=args.outcome,
        existing_skills=", ".join(existing) if existing else "(none)",
    )

    result = call_gpt55(prompt, timeout=args.timeout)
    if result is None:
        print("ERR: GPT-5.5 did not return valid JSON", file=sys.stderr)
        sys.exit(3)

    if not result.get("crystallize"):
        reason = result.get("reason", "unknown")
        print(f"[crystallize] SKIP: {reason}")
        sys.exit(0)

    # Validate
    issues = validate_skill(result)
    if issues:
        for issue in issues:
            print(f"[crystallize] VALIDATION FAIL: {issue}", file=sys.stderr)
        if not args.force:
            print("[crystallize] Rejecting invalid skill. Use --force to override.", file=sys.stderr)
            sys.exit(4)

    # Dry run
    if args.dry_run:
        content = result["skill_content"]
        preview = content[:500]
        print(f"\n=== DRY RUN ===")
        print(f"Skill: {result['skill_name']} | Category: {result.get('category', '?')}")
        print(f"--- Preview (500 chars) ---")
        print(preview)
        print(f"---")
        sys.exit(0)

    # Phase 5: Write
    print("[crystallize] Phase 5: Writing skill...")
    skill_dir = SKILLS_AUTO / result["skill_name"]
    skill_file = skill_dir / "SKILL.md"
    skill_md = build_skill_md(result)

    if atomic_write(skill_file, skill_md):
        print(f"[crystallize] WROTE: skills/_auto/{result['skill_name']}/SKILL.md")
        print(f"  Review: move to skills/approved/ to activate")

        # Also save execution trace
        trace_file = skill_dir / "_execution-trace.md"
        date_str = datetime.now().strftime("%Y-%m-%d %H:%M")
        trace_content = (
            f"# Execution Trace — {result['skill_name']}\n\n"
            f"**Date:** {date_str} | **Calls:** ~{tool_count} | **Outcome:** {args.outcome}\n\n"
            f"{exec_log[:16000]}"
        )
        atomic_write(trace_file, trace_content)

        if args.json_output:
            print(json.dumps({
                "crystallized": True,
                "skill": result["skill_name"],
                "category": result.get("category", "?"),
            }, ensure_ascii=False))
    else:
        print("ERR: Write failed", file=sys.stderr)
        sys.exit(4)


if __name__ == "__main__":
    main()
