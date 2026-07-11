"""Build code symbol graph from Python files → SQLite."""
import ast
import sqlite3
import sys
from pathlib import Path

DB_PATH = Path("D:/Code/ai-infra/data/symbols.sqlite")
SCAN_ROOTS = [
    Path("D:/Code/local-agent"),
    Path("D:/Code/ai-infra/scripts"),
]
# Only scan .py files
EXCLUDE_DIRS = {"__pycache__", ".venv", "node_modules", ".git", "archive"}


def collect_files(roots: list[Path]) -> list[Path]:
    files = []
    for root in roots:
        if not root.exists():
            continue
        for p in root.rglob("*.py"):
            if any(ex in p.parts for ex in EXCLUDE_DIRS):
                continue
            files.append(p)
    return files


def extract_symbols(filepath: Path) -> dict:
    """Extract functions, classes, imports, calls from a Python file."""
    try:
        tree = ast.parse(filepath.read_text(encoding="utf-8"))
    except (SyntaxError, UnicodeDecodeError):
        return {}

    rel = str(filepath).replace("D:\\Code\\", "").replace("\\", "/")

    functions = []
    classes = []
    imports = []
    calls = []

    for node in ast.walk(tree):
        # Functions/methods
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            functions.append({
                "name": node.name,
                "lineno": node.lineno,
                "args": [a.arg for a in node.args.args],
            })

        # Classes
        if isinstance(node, ast.ClassDef):
            classes.append({
                "name": node.name,
                "lineno": node.lineno,
            })

        # Imports
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append({
                    "module": alias.name,
                    "name": alias.name,
                    "alias": alias.asname or "",
                })
        if isinstance(node, ast.ImportFrom):
            for alias in node.names:
                imports.append({
                    "module": node.module or "",
                    "name": alias.name,
                    "alias": alias.asname or "",
                })

        # Calls
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                calls.append({"name": node.func.id, "lineno": node.lineno})
            elif isinstance(node.func, ast.Attribute):
                calls.append({"name": node.func.attr, "lineno": node.lineno})

    return {
        "file": rel,
        "functions": functions,
        "classes": classes,
        "imports": imports,
        "calls": calls,
    }


def build_db(db_path: Path, roots: list[Path]):
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA journal_mode=WAL")

    # Schema
    conn.executescript("""
        DROP TABLE IF EXISTS files;
        DROP TABLE IF EXISTS functions;
        DROP TABLE IF EXISTS classes;
        DROP TABLE IF EXISTS imports;
        DROP TABLE IF EXISTS calls;

        CREATE TABLE files (id INTEGER PRIMARY KEY, path TEXT UNIQUE);
        CREATE TABLE functions (id INTEGER PRIMARY KEY, file_id INTEGER, name TEXT, lineno INTEGER, args TEXT);
        CREATE TABLE classes (id INTEGER PRIMARY KEY, file_id INTEGER, name TEXT, lineno INTEGER);
        CREATE TABLE imports (id INTEGER PRIMARY KEY, file_id INTEGER, module TEXT, name TEXT, alias TEXT);
        CREATE TABLE calls (id INTEGER PRIMARY KEY, file_id INTEGER, name TEXT, lineno INTEGER);

        CREATE INDEX idx_func_name ON functions(name);
        CREATE INDEX idx_import_module ON imports(module);
        CREATE INDEX idx_call_name ON calls(name);
    """)

    files = collect_files(roots)
    print(f"Scanning {len(files)} Python files...")

    for fp in files:
        data = extract_symbols(fp)
        if not data:
            continue

        rel = data["file"]
        conn.execute("INSERT OR IGNORE INTO files (path) VALUES (?)", (rel,))
        fid = conn.execute("SELECT id FROM files WHERE path=?", (rel,)).fetchone()[0]

        for fn in data["functions"]:
            conn.execute("INSERT INTO functions (file_id, name, lineno, args) VALUES (?,?,?,?)",
                         (fid, fn["name"], fn["lineno"], ",".join(fn["args"])))

        for cls in data["classes"]:
            conn.execute("INSERT INTO classes (file_id, name, lineno) VALUES (?,?,?)",
                         (fid, cls["name"], cls["lineno"]))

        for imp in data["imports"]:
            conn.execute("INSERT INTO imports (file_id, module, name, alias) VALUES (?,?,?,?)",
                         (fid, imp["module"], imp["name"], imp["alias"]))

        for call in data["calls"]:
            conn.execute("INSERT INTO calls (file_id, name, lineno) VALUES (?,?,?)",
                         (fid, call["name"], call["lineno"]))

    conn.commit()

    # Print stats
    counts = {}
    for table in ["files", "functions", "classes", "imports", "calls"]:
        counts[table] = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"Done: {counts['files']} files, {counts['functions']} functions, "
          f"{counts['classes']} classes, {counts['imports']} imports, {counts['calls']} calls")

    # Impact query demo
    print("\n--- Top 10 most-called functions ---")
    for row in conn.execute("""
        SELECT name, COUNT(*) as cnt FROM calls
        WHERE name NOT IN ('print','len','int','str','list','dict','set','range','enumerate','isinstance')
        GROUP BY name ORDER BY cnt DESC LIMIT 10
    """):
        print(f"  {row[0]}: {row[1]} calls")

    conn.close()
    return str(db_path)


if __name__ == "__main__":
    roots = SCAN_ROOTS
    if len(sys.argv) > 1:
        roots = [Path(p) for p in sys.argv[1:]]
    path = build_db(DB_PATH, roots)
    print(f"\nDatabase: {path}")
    print("Query: sqlite3 " + path)
    print("  -- Find all callers: SELECT f.path, c.lineno FROM calls c JOIN files f ON c.file_id=f.id WHERE c.name='verify_token'")
