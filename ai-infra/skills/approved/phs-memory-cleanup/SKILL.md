---
name: phs-memory-cleanup
description: A workflow for cleaning up and organizing PHS-related memories in a structured manner.
version: 0.1.0
auto_generated: true
generated_date: 2026-07-08
category: 
tags: []
---

# PHS Memory Cleanup Workflow

## When to use
This workflow should be used when you need to clean up, organize, and update PHS-related memories to ensure they are relevant, organized, and free from duplicates.

## Steps
### Step 1: Search & Discovery
- **Tool:** PowerShell Globbing
- **Action:** Search for all files containing 'phs', 'prism', or 'mirage' in the memory directory.
- **Output:** A list of 28 PHS-related memories found.

### Step 2: Analysis
- **Tool:** PowerShell Grep
- **Action:** Cross-reference the discovered memories with core project documents and STATUS.md to assess quality and identify duplicates.
- **Output:** Quality audit results (good, ok, garbage, zombie), identified duplicate pairs, and status alignment.

### Step 3: Cleanup
- **Tool:** PowerShell Script
- **Action:** Delete garbage and duplicate memory files, update relevant status files, and create new governance and key lessons memories.
- **Output:** Updated memory files with cleaned-up content.

### Step 4: Index Update
- **Tool:** PowerShell Script
- **Action:** Restructure MEMORY.md into partitions and remove zombie references from the index.
- **Output:** Updated MEMORY.md with organized partitions.

## Pitfalls
- Misidentification of garbage memories.
- Overlooking duplicate pairs.
- Incorrect status alignment in STATUS.md.

## Verification
1. Check if all 28 memories are accounted for (3 zombies, 18 garbage, 2 duplicates, and 5 ok).
2. Verify that the updated MEMORY.md contains only substantive content under organized partitions.
3. Ensure that all relevant status files are up-to-date.

## Anti-patterns
- Not updating STATUS.md accurately.
- Failing to remove zombie references from the index.
- Overwriting critical memory files without backup.