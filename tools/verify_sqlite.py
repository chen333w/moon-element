#!/usr/bin/env python3
"""Differential conformance test for moon-lite.

Creates databases with Python's standard-library ``sqlite3``, asks SQLite itself for the expected
schema and rows, then runs the moon-lite CLI on the very same files and compares every table,
column, rowid and value.

The CLI contract under test (see cmd/main):

    moon run cmd/main --target native -- schema <file.db>
        one JSON line: page_size, encoding, sqlite_version, tables[...] with columns[...]

    moon run cmd/main --target native -- dump <file.db> [--table NAME] [--limit N]
        one JSON line per row: {"table":..,"rowid":..,"values":[{"type":..,"value":..}]}

    value types: null (no "value"), integer, real, text, blob (hex string)

Exit code is 0 only when every database matches; otherwise the first difference of each failing
database is printed with its table, rowid and column.

Usage:
    python3 tools/verify_sqlite.py            # full run
    python3 tools/verify_sqlite.py --keep     # keep the temporary directory
    python3 tools/verify_sqlite.py --generate-only   # only build the databases
"""

from __future__ import annotations

import json
import pathlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
ENCODINGS = {1: "UTF-8", 2: "UTF-16le", 3: "UTF-16be"}


# --------------------------------------------------------------------------------------
# database fixtures
# --------------------------------------------------------------------------------------


class Db:
    """One fixture: where it lives, plus how to build it."""

    def __init__(self, name: str, build):
        self.name = name
        self.build = build
        self.path = None


def new_conn(path, page_size=None, encoding=None):
    conn = sqlite3.connect(str(path))
    if page_size is not None:
        conn.execute(f"PRAGMA page_size = {page_size}")
    if encoding is not None:
        conn.execute(f"PRAGMA encoding = '{encoding}'")
    return conn


def build_basic_types(path):
    conn = new_conn(path)
    conn.executescript(
        """
        CREATE TABLE t (a INTEGER, b TEXT, c REAL, d BLOB, e);
        INSERT INTO t VALUES (1, 'one', 1.5, x'0001ff', NULL);
        INSERT INTO t VALUES (2, '', -0.0, x'', NULL);
        INSERT INTO t VALUES (-3, 'tab\there', 2.25, x'deadbeef', NULL);
        """
    )
    conn.commit()
    conn.close()


def build_integers(path):
    values = [
        0, 1, -1, 127, 128, 32767, 32768, 8388607, 8388608,
        2147483647, -2147483648, 140737488355327, -140737488355328,
        4611686018427387904, -4611686018427387904,
        9223372036854775807, -9223372036854775808,
    ]
    conn = new_conn(path)
    conn.execute("CREATE TABLE t (v INTEGER)")
    conn.executemany("INSERT INTO t VALUES (?)", [(v,) for v in values])
    conn.commit()
    conn.close()


def build_reals(path):
    values = [0.0, -0.0, 0.5, 1e300, 1e-300, 3.141592653589793, 0.1 + 0.2, -2.5]
    conn = new_conn(path)
    conn.execute("CREATE TABLE t (v REAL)")
    conn.executemany("INSERT INTO t VALUES (?)", [(v,) for v in values])
    conn.commit()
    conn.close()


def build_unicode(path):
    conn = new_conn(path)
    conn.execute("CREATE TABLE t (v TEXT)")
    rows = [
        ("纯 MoonBit 读取器",),
        ("emoji 😀🚀",),
        ("combining a\u0301",),
        ("",),
        ("line\nbreak",),
        ("quote \" and backslash \\",),
    ]
    conn.executemany("INSERT INTO t VALUES (?)", rows)
    conn.commit()
    conn.close()


def build_utf16le(path):
    conn = new_conn(path, encoding="UTF-16le")
    conn.execute("CREATE TABLE t (v TEXT)")
    conn.executemany("INSERT INTO t VALUES (?)", [("UTF-16le 文本",), ("naïve café",), ("",)])
    conn.commit()
    conn.close()


def build_utf16be(path):
    conn = new_conn(path, encoding="UTF-16be")
    conn.execute("CREATE TABLE t (v TEXT)")
    conn.executemany("INSERT INTO t VALUES (?)", [("UTF-16be 文本",), ("Ω≈ç√",)])
    conn.commit()
    conn.close()


def build_empty_table(path):
    conn = new_conn(path)
    conn.executescript("CREATE TABLE empty (a INTEGER, b TEXT);")
    conn.commit()
    conn.close()


def build_single_row(path):
    conn = new_conn(path)
    conn.executescript(
        "CREATE TABLE one (id INTEGER PRIMARY KEY, name TEXT NOT NULL, score REAL);"
        "INSERT INTO one VALUES (1, 'only', 99.5);"
    )
    conn.commit()
    conn.close()


def build_many_rows(path):
    conn = new_conn(path)
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, payload TEXT, n INTEGER)")
    conn.executemany(
        "INSERT INTO t VALUES (?, ?, ?)",
        [(i, f"row-{i:05d}-" + "x" * (i % 40), i * 7 - 1000) for i in range(5000)],
    )
    conn.commit()
    conn.close()


def build_big_blob(path):
    conn = new_conn(path)
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body BLOB, note TEXT)")
    conn.execute("INSERT INTO t VALUES (1, ?, 'small')", (bytes(range(256)),))
    conn.execute("INSERT INTO t VALUES (2, ?, 'overflow')", (bytes(range(256)) * 20,))  # 5120
    conn.execute("INSERT INTO t VALUES (3, ?, 'overflow2')", (bytes(range(256)) * 36,))  # 9216
    conn.commit()
    conn.close()


def build_without_rowid(path):
    conn = new_conn(path)
    conn.executescript(
        """
        CREATE TABLE w (k TEXT PRIMARY KEY, v INTEGER, note TEXT) WITHOUT ROWID;
        """
    )
    rows = [(f"key-{i:02d}", i * 11, f"note {i}") for i in range(10)]
    conn.executemany("INSERT INTO w VALUES (?, ?, ?)", rows)
    conn.commit()
    conn.close()


def build_indexed(path):
    conn = new_conn(path)
    conn.executescript(
        """
        CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, kind INTEGER);
        CREATE INDEX idx_name ON t (name);
        CREATE INDEX idx_kind_name ON t (kind, name);
        """
    )
    conn.executemany(
        "INSERT INTO t VALUES (?, ?, ?)",
        [(i, f"name-{i:03d}", i % 5) for i in range(1, 21)],
    )
    conn.commit()
    conn.close()


def build_multi_table(path):
    conn = new_conn(path)
    conn.executescript(
        """
        CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL);
        CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, total REAL);
        CREATE TABLE tags (label TEXT, weight INTEGER);
        """
    )
    conn.executemany("INSERT INTO users VALUES (?, ?)", [(1, "a@example.com"), (2, "b@example.com")])
    conn.executemany("INSERT INTO orders VALUES (?, ?, ?)", [(10, 1, 12.5), (11, 2, 0.99)])
    conn.executemany("INSERT INTO tags VALUES (?, ?)", [("x", 1), ("y", 2), ("z", 3)])
    conn.commit()
    conn.close()


def build_keyword_columns(path):
    conn = new_conn(path)
    conn.executescript(
        """
        CREATE TABLE "t" (
          "select" INTEGER,
          "from" TEXT,
          "order" REAL,
          "group" BLOB,
          "table" TEXT
        );
        INSERT INTO "t" VALUES (1, 'kw', 2.5, x'00ff', 'last');
        """
    )
    conn.commit()
    conn.close()


def build_no_primary_key(path):
    conn = new_conn(path)
    conn.executescript(
        """
        CREATE TABLE plain (a TEXT, b INTEGER, c REAL);
        """
    )
    conn.executemany(
        "INSERT INTO plain VALUES (?, ?, ?)",
        [("only-text", 42, 1.25), ("", -7, -0.5), ("dup", 42, 1.25)],
    )
    conn.commit()
    conn.close()


def build_negative_rowid(path):
    conn = new_conn(path)
    conn.execute("CREATE TABLE t (v TEXT)")
    conn.executemany("INSERT INTO t (rowid, v) VALUES (?, ?)", [(-5, "neg"), (1, "one"), (100, "hundred")])
    conn.commit()
    conn.close()


def build_all_null(path):
    conn = new_conn(path)
    conn.executescript("CREATE TABLE t (a, b TEXT, c INTEGER, d REAL, e BLOB);")
    conn.execute("INSERT INTO t VALUES (NULL, NULL, NULL, NULL, NULL)")
    conn.commit()
    conn.close()


def build_page_512(path):
    conn = new_conn(path, page_size=512)
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body TEXT)")
    conn.executemany(
        "INSERT INTO t VALUES (?, ?)",
        [(i, "y" * (i % 120)) for i in range(200)],
    )
    conn.commit()
    conn.close()


def build_page_65536(path):
    conn = new_conn(path, page_size=65536)
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body TEXT)")
    conn.executemany("INSERT INTO t VALUES (?, ?)", [(i, f"pagebig-{i}") for i in range(20)])
    conn.commit()
    conn.close()


def build_composite_pk(path):
    conn = new_conn(path)
    conn.executescript(
        """
        CREATE TABLE pair (a INTEGER NOT NULL, b TEXT NOT NULL, payload TEXT, PRIMARY KEY (a, b));
        """
    )
    conn.executemany(
        "INSERT INTO pair VALUES (?, ?, ?)",
        [(1, "x", "first"), (1, "y", "second"), (2, "x", "third")],
    )
    conn.commit()
    conn.close()


FIXTURES = [
    Db("01_basic_types", build_basic_types),
    Db("02_integers", build_integers),
    Db("03_reals", build_reals),
    Db("04_unicode", build_unicode),
    Db("05_utf16le", build_utf16le),
    Db("06_utf16be", build_utf16be),
    Db("07_empty_table", build_empty_table),
    Db("08_single_row", build_single_row),
    Db("09_many_rows", build_many_rows),
    Db("10_big_blob", build_big_blob),
    Db("11_without_rowid", build_without_rowid),
    Db("12_indexed", build_indexed),
    Db("13_multi_table", build_multi_table),
    Db("14_keyword_columns", build_keyword_columns),
    Db("15_no_primary_key", build_no_primary_key),
    Db("16_negative_rowid", build_negative_rowid),
    Db("17_all_null", build_all_null),
    Db("18_page_512", build_page_512),
    Db("19_page_65536", build_page_65536),
    Db("20_composite_pk", build_composite_pk),
]


# --------------------------------------------------------------------------------------
# expectations straight from sqlite3
# --------------------------------------------------------------------------------------


def expected_schema(path):
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        page_size = conn.execute("PRAGMA page_size").fetchone()[0]
        encoding = conn.execute("PRAGMA encoding").fetchone()[0]
        version = conn.execute("SELECT sqlite_version()").fetchone()[0]
        tables = conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'"
        ).fetchall()
        out = []
        for (name,) in tables:
            info = conn.execute(f'PRAGMA table_info({quote_ident(name)})').fetchall()
            columns = [
                {
                    "name": row[1],
                    "declared_type": row[2],
                    "not_null": bool(row[3]),
                    "primary_key": row[5] > 0,
                }
                for row in info
            ]
            sql = conn.execute(
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", (name,)
            ).fetchone()[0]
            out.append({"name": name, "sql": sql or "", "columns": columns})
        return {
            "page_size": page_size,
            "encoding": encoding,
            "sqlite_version": version_number(version),
            "tables": out,
        }
    finally:
        conn.close()


def version_number(text):
    parts = [int(p) for p in text.split(".")[:3]]
    while len(parts) < 3:
        parts.append(0)
    return parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2]


def quote_ident(name):
    return '"' + name.replace('"', '""') + '"'


def expected_rows(path):
    """{table: (without_rowid, [(rowid_or_None, [normalized values])])}"""
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        tables = conn.execute(
            "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'"
        ).fetchall()
        out = {}
        for name, sql in tables:
            without_rowid = "WITHOUT ROWID" in (sql or "").upper()
            ident = quote_ident(name)
            if without_rowid:
                rows = conn.execute(f"SELECT * FROM {ident}").fetchall()
                out[name] = (True, [(None, [normalize(v) for v in row]) for row in rows])
            else:
                rows = conn.execute(f"SELECT rowid, * FROM {ident} ORDER BY rowid").fetchall()
                out[name] = (
                    False,
                    [(row[0], [normalize(v) for v in row[1:]]) for row in rows],
                )
        return out
    finally:
        conn.close()


def normalize(value):
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"type": "integer", "value": int(value)}
    if isinstance(value, int):
        return {"type": "integer", "value": value}
    if isinstance(value, float):
        return {"type": "real", "value": value}
    if isinstance(value, str):
        return {"type": "text", "value": value}
    if isinstance(value, (bytes, bytearray, memoryview)):
        return {"type": "blob", "value": bytes(value).hex()}
    raise TypeError(f"unexpected sqlite value type: {type(value)!r}")


# --------------------------------------------------------------------------------------
# the CLI under test
# --------------------------------------------------------------------------------------


def resolve_cli(repo):
    binary = repo / "_build" / "native" / "release" / "build" / "cmd" / "main" / "main.exe"
    if binary.exists():
        return [str(binary)]
    print("[build] moon build --target native --release cmd/main", file=sys.stderr)
    built = subprocess.run(
        ["moon", "build", "--target", "native", "--release", "cmd/main"],
        cwd=repo,
        capture_output=True,
        text=True,
    )
    if built.returncode != 0 or not binary.exists():
        sys.stderr.write(built.stdout + built.stderr)
        raise SystemExit("cannot build cmd/main")
    return [str(binary)]


def run_cli(cli, args):
    return subprocess.run(cli + args, capture_output=True, text=True)


def cli_schema(cli, path):
    proc = run_cli(cli, ["schema", str(path)])
    if proc.returncode != 0:
        raise CliError(f"schema exited {proc.returncode}: {proc.stderr.strip()}")
    text = proc.stdout.strip()
    if not text:
        raise CliError("schema printed nothing")
    if "\n" in text:
        raise CliError(f"schema must print one JSON line, got {text.count(chr(10)) + 1} lines")
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise CliError(f"schema is not JSON: {exc}: {text[:200]}")


def cli_dump(cli, path, table=None):
    args = ["dump", str(path)]
    if table is not None:
        args += ["--table", table]
    proc = run_cli(cli, args)
    if proc.returncode != 0:
        raise CliError(f"dump exited {proc.returncode}: {proc.stderr.strip()}")
    rows = []
    for lineno, line in enumerate(proc.stdout.splitlines(), 1):
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise CliError(f"dump line {lineno} is not JSON: {exc}: {line[:200]}")
    return rows


class CliError(Exception):
    pass


# --------------------------------------------------------------------------------------
# comparison
# --------------------------------------------------------------------------------------


class Diff(Exception):
    pass


def squash_type(text):
    """PRAGMA reports `VARCHAR(20)`; the reader may keep the original spacing."""
    return "".join(str(text).split()).upper()


def compare_schema(db_name, expected, actual):
    checks = 0
    if actual.get("page_size") != expected["page_size"]:
        raise Diff(
            f"{db_name}: page_size expected {expected['page_size']} got {actual.get('page_size')}"
        )
    checks += 1
    if actual.get("encoding") != expected["encoding"]:
        raise Diff(
            f"{db_name}: encoding expected {expected['encoding']!r} got {actual.get('encoding')!r}"
        )
    checks += 1
    if actual.get("sqlite_version") != expected["sqlite_version"]:
        raise Diff(
            f"{db_name}: sqlite_version expected {expected['sqlite_version']} "
            f"got {actual.get('sqlite_version')}"
        )
    checks += 1

    expected_tables = {t["name"]: t for t in expected["tables"]}
    actual_tables = {t["name"]: t for t in actual.get("tables", [])}
    if set(expected_tables) != set(actual_tables):
        raise Diff(
            f"{db_name}: table set expected {sorted(expected_tables)} got {sorted(actual_tables)}"
        )
    checks += 1
    for name in sorted(expected_tables):
        want = expected_tables[name]
        got = actual_tables[name]
        want_cols = [
            (c["name"], squash_type(c["declared_type"]), c["not_null"], c["primary_key"])
            for c in want["columns"]
        ]
        got_cols = [
            (
                c.get("name"),
                squash_type(c.get("declared_type", "")),
                bool(c.get("not_null")),
                bool(c.get("primary_key")),
            )
            for c in got.get("columns", [])
        ]
        if want_cols != got_cols:
            raise Diff(
                f"{db_name}.{name}: columns expected {want_cols} got {got_cols}"
            )
        checks += 1
    return checks


def compare_rows(db_name, expected, actual_rows):
    """Returns (checks, rows_compared, values_compared)."""
    by_table = {}
    for row in actual_rows:
        table = row.get("table")
        by_table.setdefault(table, []).append(row)

    checks = 0
    rows_compared = 0
    values_compared = 0
    for table in sorted(expected):
        without_rowid, want_rows = expected[table]
        got_rows = by_table.get(table)
        if got_rows is None:
            got_rows = []
        if want_rows and not got_rows:
            raise Diff(f"{db_name}.{table}: no rows emitted for a non-empty table")
        if len(got_rows) != len(want_rows):
            raise Diff(
                f"{db_name}.{table}: row count expected {len(want_rows)} got {len(got_rows)}"
            )
        checks += 1
        for index, (want_rowid, want_values) in enumerate(want_rows):
            got = got_rows[index]
            got_values = got.get("values") or []
            rows_compared += 1
            if not without_rowid:
                if got.get("rowid") != want_rowid:
                    raise Diff(
                        f"{db_name}.{table}: row #{index} rowid expected {want_rowid} "
                        f"got {got.get('rowid')}"
                    )
            if len(got_values) != len(want_values):
                raise Diff(
                    f"{db_name}.{table} rowid={want_rowid}: column count expected "
                    f"{len(want_values)} got {len(got_values)}"
                )
            for col, (want, got_value) in enumerate(zip(want_values, got_values)):
                values_compared += 1
                problem = compare_value(want, got_value)
                if problem is not None:
                    raise Diff(
                        f"{db_name}.{table} rowid={want_rowid} column {col}: {problem}"
                    )
        checks += len(want_rows)
    return checks, rows_compared, values_compared


def compare_value(want, got):
    got_type = got.get("type")
    if want["type"] != got_type:
        return f"type expected {want['type']} got {got_type} ({describe(want)} vs {describe(got)})"
    if want["type"] == "null":
        return None if "value" not in got else f"null must not carry a value: {got}"
    if want["type"] == "integer":
        if got.get("value") != want["value"]:
            return f"expected {want['value']} got {got.get('value')}"
        return None
    if want["type"] == "real":
        got_value = got.get("value")
        if not isinstance(got_value, (int, float)) or isinstance(got_value, bool):
            return f"real value must be a JSON number, got {got_value!r}"
        if got_value != want["value"]:
            return f"expected {want['value']!r} got {got_value!r}"
        return None
    if want["type"] == "text":
        if got.get("value") != want["value"]:
            return f"expected {want['value']!r} got {got.get('value')!r}"
        return None
    if want["type"] == "blob":
        if str(got.get("value", "")).lower() != want["value"]:
            return f"expected hex {want['value'][:32]}... got {str(got.get('value'))[:32]}..."
        return None
    return f"unknown expected type {want['type']}"


def describe(value):
    text = json.dumps(value)
    return text if len(text) <= 120 else text[:117] + "..."


# --------------------------------------------------------------------------------------
# driver
# --------------------------------------------------------------------------------------


def main(argv):
    keep = "--keep" in argv
    generate_only = "--generate-only" in argv
    workdir = pathlib.Path(tempfile.mkdtemp(prefix="moon-lite-verify-"))
    stats = {
        "databases": 0,
        "tables": 0,
        "rows": 0,
        "values": 0,
        "checks": 0,
    }
    failures = []
    cli = None
    try:
        for fixture in FIXTURES:
            fixture.path = workdir / f"{fixture.name}.db"
            fixture.build(fixture.path)
            stats["databases"] += 1
        print(f"[fixtures] {stats['databases']} databases in {workdir}")
        if generate_only:
            for fixture in FIXTURES:
                schema = expected_schema(fixture.path)
                rows = expected_rows(fixture.path)
                stats["tables"] += len(schema["tables"])
                for _, table_rows in rows.values():
                    stats["rows"] += len(table_rows)
                    stats["values"] += sum(len(values) for _, values in table_rows)
            print(
                "[generate-only] tables: {tables}, rows: {rows}, values: {values}".format(**stats)
            )
            return 0

        cli = resolve_cli(REPO)
        print(f"[cli] {' '.join(cli)}")
        for fixture in FIXTURES:
            try:
                want_schema = expected_schema(fixture.path)
                want_rows = expected_rows(fixture.path)
                got_schema = cli_schema(cli, fixture.path)
                got_rows = cli_dump(cli, fixture.path)
                checks = compare_schema(fixture.name, want_schema, got_schema)
                row_checks, rows_compared, values_compared = compare_rows(
                    fixture.name, want_rows, got_rows
                )
                stats["tables"] += len(want_schema["tables"])
                stats["rows"] += rows_compared
                stats["values"] += values_compared
                stats["checks"] += checks + row_checks
                print(
                    f"[ok]   {fixture.name}: {len(want_schema['tables'])} tables, "
                    f"{rows_compared} rows, {values_compared} values"
                )
            except Diff as diff:
                failures.append(f"{fixture.name}: {diff}")
                print(f"[FAIL] {fixture.name}: {diff}")
            except CliError as exc:
                failures.append(f"{fixture.name}: {exc}")
                print(f"[FAIL] {fixture.name}: {exc}")
    finally:
        if keep:
            print(f"[keep] {workdir}")
        else:
            shutil.rmtree(workdir, ignore_errors=True)

    total = stats["checks"] + len(failures)
    print()
    print(
        "databases: {databases}, tables: {tables}, rows: {rows}, values: {values}".format(**stats)
    )
    print(f"passed {stats['checks']}, failed {len(failures)}")
    if failures:
        for failure in failures[:10]:
            print(f"  - {failure}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))