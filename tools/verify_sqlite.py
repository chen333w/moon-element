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

    moon run cmd/main --target native -- dump <file.db> --format csv
        RFC 4180 CSV: a header row of column names, then one row per row. NULL is an empty
        field, blobs are lowercase hex, fields with a comma / quote / newline are quoted and
        inner quotes doubled.

    moon run cmd/main --target native -- dump <file.db> --format sql
        self-contained SQL: CREATE TABLE statements from sqlite_master, then
        INSERT INTO "t" VALUES (...);  Literals: NULL, integers, reals, 'text' (quotes doubled),
        x'hex' blobs. Executing the output must rebuild equivalent rows.

    moon run cmd/main --target native -- stats <file.db>
        one JSON line: file_bytes, page_size, page_count, encoding, sqlite_version and
        tables[{name, rows, without_rowid}]

    WAL databases (header read/write version = 2) are rejected on purpose: their newest frames
    live in the -wal file, so the CLI must exit non-zero and mention WAL.

Exit code is 0 only when every database matches; otherwise the first difference of each failing
database is printed with its table, rowid and column.

The CLI talks to the filesystem, so it must run on the **native** target:
`moon build cmd/main --target native --release`.

The script rebuilds that binary on every run (pass --no-rebuild to reuse one). A stale
`_build/native/.../main.exe` silently answering with pre-fix results is exactly how a real fix looks
like it did nothing, so the default is a fresh build.

Usage:
    python3 tools/verify_sqlite.py                   # rebuild, then compare everything
    python3 tools/verify_sqlite.py --no-rebuild      # trust the existing native binary
    python3 tools/verify_sqlite.py --keep            # keep the temporary directory
    python3 tools/verify_sqlite.py --generate-only   # only build the databases
    python3 tools/verify_sqlite.py --cli PATH        # use an existing CLI binary (no build)

Set MOON_CLI to a binary path to skip the build as well.
"""

from __future__ import annotations

import csv
import io
import json
import os
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
    """One fixture: where it lives, how to build it, and whether an error is the expected answer."""

    def __init__(self, name: str, build, expect_error=None):
        self.name = name
        self.build = build
        self.path = None
        # 期望 CLI 明确报错（而不是读出数据）时，写错误信息里必须出现的字样
        self.expect_error = expect_error


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


def build_quoted_names(path):
    """带空格的表名/列名 + 保留字，值里塞逗号、引号、换行、单引号。"""
    conn = new_conn(path)
    conn.execute('CREATE TABLE "my table" ("select" INTEGER, "order by" TEXT, "a b" BLOB)')
    conn.executemany(
        'INSERT INTO "my table" VALUES (?, ?, ?)',
        [
            (1, "plain", b"\x00\xff"),
            (2, 'has, comma and "quote"', b""),
            (3, "line\nbreak and \rcr", b"\x01"),
            (4, "single ' quote", b"\x02"),
        ],
    )
    conn.commit()
    conn.close()


def build_text_pk(path):
    """普通 rowid 表，但主键是 TEXT 列。"""
    conn = new_conn(path)
    conn.execute("CREATE TABLE t (k TEXT PRIMARY KEY, v INTEGER)")
    conn.executemany("INSERT INTO t VALUES (?, ?)", [("a", 1), ("b", 2), ("", 3)])
    conn.commit()
    conn.close()


def build_blob_edges(path):
    """空 blob、全零 blob，以及紧挨着的短 blob。"""
    conn = new_conn(path)
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, empty BLOB, zeros BLOB, mix BLOB)")
    conn.executemany(
        "INSERT INTO t VALUES (?, ?, ?, ?)",
        [
            (1, b"", b"\x00\x00\x00", bytes(range(8))),
            (2, b"", b"", b"\x00"),
        ],
    )
    conn.commit()
    conn.close()


def build_table_shapes(path):
    """单列表 + 20 列宽表。"""
    conn = new_conn(path)
    conn.executescript("CREATE TABLE single (v TEXT);")
    conn.execute("INSERT INTO single VALUES (?)", ("only",))
    columns = ", ".join(f"c{i:02d} INTEGER" for i in range(1, 21))
    conn.executescript(f"CREATE TABLE wide ({columns});")
    placeholders = ", ".join("?" * 20)
    conn.execute(f"INSERT INTO wide VALUES ({placeholders})", tuple(range(1, 21)))
    conn.commit()
    conn.close()


def build_unicode_names(path):
    """表名/列名用中文和 emoji；文本值里也有 emoji。"""
    conn = new_conn(path)
    conn.execute('CREATE TABLE "用户😀" ("名字" TEXT, "值🚀" INTEGER)')
    conn.executemany(
        'INSERT INTO "用户😀" VALUES (?, ?)',
        [("小明", 1), ("emoji 😀🚀", 2), ("", 3)],
    )
    conn.commit()
    conn.close()


def build_wal(path):
    """WAL 模式的库：读取器必须明确拒绝，不能静默读旧快照。"""
    conn = sqlite3.connect(str(path))
    mode = conn.execute("PRAGMA journal_mode=WAL").fetchone()[0]
    if str(mode).lower() != "wal":
        raise AssertionError(f"fixture could not switch to WAL: {mode!r}")
    conn.execute("CREATE TABLE t (a INTEGER, b TEXT)")
    conn.executemany("INSERT INTO t VALUES (?, ?)", [(i, f"wal-{i}") for i in range(5)])
    conn.commit()
    conn.close()
    header = pathlib.Path(path).read_bytes()
    if header[18] != 2 or header[19] != 2:
        raise AssertionError(
            f"expected WAL version bytes 2/2 in the header, got {header[18]}/{header[19]}"
        )

def build_freelist(path):
    """删掉大多数行但不 VACUUM：空闲页留在 freelist 里，读取器只能走活动页。"""
    conn = new_conn(path)
    conn.execute("PRAGMA page_size=512")
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body TEXT)")
    conn.executemany(
        "INSERT INTO t VALUES (?, ?)", [(i, f"row-{i}-" + "x" * 60) for i in range(120)]
    )
    conn.commit()
    conn.execute("DELETE FROM t WHERE id > 20")
    conn.commit()
    free = conn.execute("PRAGMA freelist_count").fetchone()[0]
    conn.close()
    if free <= 0:
        raise AssertionError(f"fixture should leave free pages behind, got {free}")


def build_vacuumed(path):
    """同样删行后 VACUUM：页面被重排，空闲页回收，行仍然可读。"""
    conn = new_conn(path)
    conn.execute("PRAGMA page_size=512")
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body TEXT)")
    conn.executemany(
        "INSERT INTO t VALUES (?, ?)", [(i, f"row-{i}-" + "y" * 60) for i in range(120)]
    )
    conn.commit()
    conn.execute("DELETE FROM t WHERE id > 20")
    conn.commit()
    conn.execute("VACUUM")
    conn.commit()
    free = conn.execute("PRAGMA freelist_count").fetchone()[0]
    conn.close()
    if free != 0:
        raise AssertionError(f"VACUUM should leave no free pages, got {free}")


def build_multi_overflow(path):
    """一个 blob 跨多级溢出链（page_size=512 时需要几十页）。"""
    conn = new_conn(path)
    conn.execute("PRAGMA page_size=512")
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body BLOB, tail TEXT)")
    conn.execute("INSERT INTO t VALUES (1, ?, 'head')", (bytes(range(256)) * 80,))  # 20480
    conn.execute("INSERT INTO t VALUES (2, ?, 'mid')", (bytes(range(256)) * 3,))  # 768
    conn.execute("INSERT INTO t VALUES (3, ?, 'end')", (bytes(range(256)) * 200,))  # 51200
    conn.commit()
    conn.close()


def build_multi_level_tree(path):
    """page_size=512 + 4000 行：表 b-tree 至少三层，interior 页里还有 interior 页。"""
    conn = new_conn(path)
    conn.execute("PRAGMA page_size=512")
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body TEXT)")
    conn.executemany(
        "INSERT INTO t VALUES (?, ?)", [(i, f"row-{i:05d}-" + "z" * 40) for i in range(4000)]
    )
    conn.commit()
    conn.close()


def build_deleted_rows(path):
    """隔行删除：页里留下 freeblock，cell pointer 数组只含活动 cell。"""
    conn = new_conn(path)
    conn.execute("PRAGMA page_size=512")
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, body TEXT)")
    conn.executemany(
        "INSERT INTO t VALUES (?, ?)", [(i, f"row-{i}-" + "q" * 30) for i in range(200)]
    )
    conn.commit()
    conn.execute("DELETE FROM t WHERE id % 2 = 0")
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
    Db("21_quoted_names", build_quoted_names),
    Db("22_text_pk", build_text_pk),
    Db("23_blob_edges", build_blob_edges),
    Db("24_table_shapes", build_table_shapes),
    Db("25_unicode_names", build_unicode_names),
    Db("26_wal", build_wal, expect_error="WAL"),
    Db("27_freelist", build_freelist),
    Db("28_vacuumed", build_vacuumed),
    Db("29_multi_overflow", build_multi_overflow),
    Db("30_multi_level_tree", build_multi_level_tree),
    Db("31_deleted_rows", build_deleted_rows),
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


def resolve_cli(repo, explicit=None, rebuild=True):
    """The CLI needs the native target (the reader uses moonbitlang/x fs)."""
    if explicit:
        return [explicit]
    from_env = os.environ.get("MOON_CLI")
    if from_env:
        return [from_env]
    binary = repo / "_build" / "native" / "release" / "build" / "cmd" / "main" / "main.exe"
    if rebuild or not binary.exists():
        print("[build] moon build cmd/main --target native --release", file=sys.stderr)
        built = subprocess.run(
            ["moon", "build", "cmd/main", "--target", "native", "--release"],
            cwd=repo,
            capture_output=True,
            text=True,
        )
        if built.returncode != 0 or not binary.exists():
            sys.stderr.write(built.stdout + built.stderr)
            raise SystemExit("cannot build cmd/main --target native --release (see the build output)")
    elif binary.exists():
        print(f"[build] reusing {binary}", file=sys.stderr)
    return [str(binary)]


def run_cli(cli, args):
    # 不用 text=True：通用换行转换会把 CSV/SQL 字段里的 \r 变成 \n
    return subprocess.run(cli + args, capture_output=True)


def decode_stdout(proc):
    return proc.stdout.decode("utf-8", errors="replace")


def cli_schema(cli, path):
    proc = run_cli(cli, ["schema", str(path)])
    if proc.returncode != 0:
        raise CliError(
            f"schema exited {proc.returncode}: "
            f"{proc.stderr.decode('utf-8', errors='replace').strip()}"
        )
    text = decode_stdout(proc).strip()
    if not text:
        raise CliError("schema printed nothing")
    if "\n" in text:
        raise CliError(f"schema must print one JSON line, got {text.count(chr(10)) + 1} lines")
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise CliError(f"schema is not JSON: {exc}: {text[:200]}")


def cli_dump(cli, path, table=None, limit=None):
    args = ["dump", str(path)]
    if table is not None:
        args += ["--table", table]
    if limit is not None:
        args += ["--limit", str(limit)]
    proc = run_cli(cli, args)
    if proc.returncode != 0:
        raise CliError(
            f"dump exited {proc.returncode}: "
            f"{proc.stderr.decode('utf-8', errors='replace').strip()}"
        )
    rows = []
    for lineno, line in enumerate(decode_stdout(proc).splitlines(), 1):
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


def check_cli_options(cli, fixtures):
    """`--table` and `--limit` are part of the CLI contract too."""
    checks = 0
    problems = []

    multi = fixtures["13_multi_table"]
    expected_multi = expected_rows(multi)
    rows = cli_dump(cli, multi, table="orders")
    tables = sorted({row.get("table") for row in rows})
    if tables != ["orders"]:
        problems.append(f"--table orders: expected only orders rows, got tables {tables}")
    elif len(rows) != len(expected_multi["orders"][1]):
        problems.append(
            f"--table orders: expected {len(expected_multi['orders'][1])} rows, got {len(rows)}"
        )
    else:
        checks += 1

    many = fixtures["09_many_rows"]
    rows = cli_dump(cli, many, limit=2)
    expected = expected_rows(many)["t"][1][:2]
    got = [(row.get("rowid"), row.get("values")) for row in rows]
    want = [(rowid, values) for rowid, values in expected]
    if len(rows) != 2:
        problems.append(f"--limit 2 on a 5000 row table: expected 2 rows, got {len(rows)}")
    elif got != want:
        problems.append("--limit 2: the two rows differ from the first two rows of the table")
    else:
        checks += 1
    return checks, problems


# --------------------------------------------------------------------------------------
# csv / sql / stats output, and the expected WAL rejection
# --------------------------------------------------------------------------------------


def cli_text(cli, args, what):
    proc = subprocess.run(cli + args, capture_output=True)
    if proc.returncode != 0:
        raise CliError(
            f"{what} exited {proc.returncode}: "
            f"{proc.stderr.decode('utf-8', errors='replace').strip()}"
        )
    return decode_stdout(proc)


def cli_csv(cli, path, table=None):
    args = ["dump", str(path), "--format", "csv"]
    if table is not None:
        args += ["--table", table]
    text = cli_text(cli, args, "dump --format csv")
    # newline="" 让 csv 模块自己处理 \r（RFC 4180 的行结束符）
    return list(csv.reader(io.StringIO(text, newline="")))


def compare_csv_cell(want, cell):
    kind = want["type"]
    if kind == "null":
        return None if cell == "" else f"expected an empty field for NULL, got {cell!r}"
    if kind == "integer":
        return None if cell == str(want["value"]) else f"expected {want['value']} got {cell!r}"
    if kind == "real":
        try:
            number = float(cell)
        except ValueError:
            return f"real field is not a number: {cell!r}"
        return None if number == want["value"] else f"expected {want['value']!r} got {number!r}"
    if kind == "text":
        return None if cell == want["value"] else f"expected {want['value']!r} got {cell!r}"
    if kind == "blob":
        if cell.lower() != want["value"]:
            return f"expected hex {want['value'][:32]} got {cell[:32]!r}"
        return None
    return f"unexpected type {kind}"


def check_csv(cli, db_name, path, schema, rows):
    """Per table: a header row of column names, then the rows as RFC 4180 CSV."""
    checks = 0
    for table in schema["tables"]:
        name = table["name"]
        expected = rows.get(name)
        if expected is None:
            raise Diff(f"{db_name}.{name}: csv: table missing from the dump")
        _, table_rows = expected
        records = cli_csv(cli, path, table=name)
        if not records:
            raise Diff(f"{db_name}.{name}: csv: no output")
        want_header = [column["name"] for column in table["columns"]]
        if records[0] != want_header:
            raise Diff(f"{db_name}.{name}: csv header expected {want_header} got {records[0]}")
        body = records[1:]
        if len(body) != len(table_rows):
            raise Diff(
                f"{db_name}.{name}: csv expected {len(table_rows)} rows, got {len(body)}"
            )
        for index, (rowid, values) in enumerate(table_rows):
            cells = body[index]
            # 只有一列且该列为空时，输出就是一行空行；csv 模块把空行读成 0 个字段
            if len(cells) == 0 and len(values) == 1:
                cells = [""]
            if len(cells) != len(values):
                raise Diff(
                    f"{db_name}.{name} rowid={rowid}: csv expected {len(values)} fields, "
                    f"got {len(cells)}"
                )
            for column, (want, cell) in enumerate(zip(values, cells)):
                problem = compare_csv_cell(want, cell)
                if problem is not None:
                    raise Diff(f"{db_name}.{name} rowid={rowid} column {column}: csv {problem}")
        checks += 1
    return checks


def check_sql(cli, db_name, path, workdir):
    """Execute the exported SQL in a fresh database, then compare rowid and every value."""
    text = cli_text(cli, ["dump", str(path), "--format", "sql"], "dump --format sql")
    if not text.strip():
        raise Diff(f"{db_name}: sql: the export is empty")
    rebuilt = pathlib.Path(workdir) / f"rebuilt-{db_name}.db"
    if rebuilt.exists():
        rebuilt.unlink()
    conn = sqlite3.connect(str(rebuilt))
    try:
        conn.executescript(text)
        conn.commit()
    finally:
        conn.close()
    want = expected_rows(path)
    got = expected_rows(rebuilt)
    for table in sorted(want):
        if table not in got:
            raise Diff(f"{db_name}: sql: table {table!r} did not survive the round trip")
        want_without, want_rows = want[table]
        got_without, got_rows = got[table]
        if want_without != got_without:
            raise Diff(f"{db_name}.{table}: sql: the WITHOUT ROWID flag changed")
        if len(want_rows) != len(got_rows):
            raise Diff(
                f"{db_name}.{table}: sql: expected {len(want_rows)} rows after replay, "
                f"got {len(got_rows)}"
            )
        for index, (want_row, got_row) in enumerate(zip(want_rows, got_rows)):
            want_rowid, want_values = want_row
            _, got_values = got_row
            # 导出的 INSERT 形如 INSERT INTO "t" VALUES (...)，不带 rowid 列：
            # 重建库会重新编号 rowid，所以这里只比对每一行的值。
            if len(want_values) != len(got_values):
                raise Diff(
                    f"{db_name}.{table}: sql: row #{index} expected {len(want_values)} values, "
                    f"got {len(got_values)}"
                )
            for column, (one, other) in enumerate(zip(want_values, got_values)):
                problem = compare_value(one, other)
                if problem is not None:
                    raise Diff(
                        f"{db_name}.{table} rowid={want_rowid} column {column}: sql {problem}"
                    )
    return 1


def check_stats(cli, db_name, path):
    text = cli_text(cli, ["stats", str(path)], "stats").strip()
    if "\n" in text:
        raise Diff(f"{db_name}: stats must print one JSON line")
    data = json.loads(text)
    size = pathlib.Path(path).stat().st_size
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        page_size = conn.execute("PRAGMA page_size").fetchone()[0]
        page_count = conn.execute("PRAGMA page_count").fetchone()[0]
        encoding = conn.execute("PRAGMA encoding").fetchone()[0]
        tables = conn.execute(
            "SELECT name, sql FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'"
        ).fetchall()
        counts = {
            name: conn.execute(f"SELECT count(*) FROM {quote_ident(name)}").fetchone()[0]
            for name, _ in tables
        }
    finally:
        conn.close()

    checks = 0
    for field, want in (
        ("file_bytes", size),
        ("page_size", page_size),
        ("page_count", page_count),
        ("encoding", encoding),
        ("sqlite_version", version_number(sqlite3.sqlite_version)),
    ):
        if data.get(field) != want:
            raise Diff(f"{db_name}: stats {field} expected {want!r} got {data.get(field)!r}")
        checks += 1
    if page_size and size // page_size != data.get("page_count"):
        raise Diff(
            f"{db_name}: stats page_count must be file bytes / page size "
            f"({size // page_size}), got {data.get('page_count')}"
        )

    reported = {entry.get("name"): entry for entry in data.get("tables", [])}
    if set(reported) != set(counts):
        raise Diff(f"{db_name}: stats tables expected {sorted(counts)} got {sorted(reported)}")
    checks += 1
    for name, sql in sorted(tables, key=lambda item: item[0]):
        entry = reported[name]
        if entry.get("rows") != counts[name]:
            raise Diff(
                f"{db_name}.{name}: stats rows expected {counts[name]} got {entry.get('rows')}"
            )
        expected_without = "WITHOUT ROWID" in (sql or "").upper()
        if bool(entry.get("without_rowid")) != expected_without:
            raise Diff(
                f"{db_name}.{name}: stats without_rowid expected {expected_without} "
                f"got {entry.get('without_rowid')}"
            )
        checks += 1
    return checks


def check_expected_error(cli, fixture):
    """A WAL database must be refused loudly, never read from a stale snapshot."""
    proc = subprocess.run(cli + ["schema", str(fixture.path)], capture_output=True, text=True)
    if proc.returncode == 0:
        raise Diff(f"{fixture.name}: expected a non-zero exit, but the CLI read the database")
    message = (proc.stderr + proc.stdout).lower()
    if fixture.expect_error.lower() not in message:
        raise Diff(
            f"{fixture.name}: expected {fixture.expect_error!r} in the error output, "
            f"got {proc.stderr.strip()[:200]!r}"
        )
    return 1


# --------------------------------------------------------------------------------------
# driver
# --------------------------------------------------------------------------------------


def main(argv):
    keep = "--keep" in argv
    generate_only = "--generate-only" in argv
    rebuild = "--no-rebuild" not in argv
    cli_override = None
    if "--cli" in argv:
        index = argv.index("--cli")
        if index + 1 < len(argv):
            cli_override = argv[index + 1]
        else:
            raise SystemExit("--cli needs a path to the CLI binary")
    workdir = pathlib.Path(tempfile.mkdtemp(prefix="moon-lite-verify-"))
    stats = {
        "databases": 0,
        "tables": 0,
        "rows": 0,
        "values": 0,
        "checks": 0,
        "csv_checks": 0,
        "sql_checks": 0,
        "stats_checks": 0,
        "error_checks": 0,
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
                if fixture.expect_error is not None:
                    continue
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

        cli = resolve_cli(REPO, cli_override, rebuild=rebuild and cli_override is None)
        print(f"[cli] {' '.join(cli)}")
        for fixture in FIXTURES:
            if fixture.expect_error is not None:
                continue
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

        fixtures = {fixture.name: fixture.path for fixture in FIXTURES}
        option_checks, option_problems = check_cli_options(cli, fixtures)
        stats["checks"] += option_checks
        for problem in option_problems:
            failures.append(f"cli options: {problem}")
            print(f"[FAIL] cli options: {problem}")
        if not option_problems:
            print("[ok]   cli options: --table and --limit")

        # 第二阶段：输出格式（csv/sql）、导出可重放性（sql）、stats 汇总，以及 WAL 拒绝
        for fixture in FIXTURES:
            if fixture.expect_error is not None:
                continue
            want_schema = expected_schema(fixture.path)
            want_rows = expected_rows(fixture.path)
            phase_failures = 0
            for label, counter_key, runner in (
                (
                    "csv",
                    "csv_checks",
                    lambda: check_csv(cli, fixture.name, fixture.path, want_schema, want_rows),
                ),
                ("sql", "sql_checks", lambda: check_sql(cli, fixture.name, fixture.path, workdir)),
                ("stats", "stats_checks", lambda: check_stats(cli, fixture.name, fixture.path)),
            ):
                try:
                    produced = runner()
                    stats[counter_key] += produced
                    stats["checks"] += produced
                except (Diff, CliError) as exc:
                    phase_failures += 1
                    failures.append(str(exc))
                    print(f"[FAIL] {exc}")
            if phase_failures == 0:
                print(f"[ok]   {fixture.name}: csv, sql replay and stats")

        for fixture in FIXTURES:
            if fixture.expect_error is None:
                continue
            try:
                stats["error_checks"] += check_expected_error(cli, fixture)
                stats["checks"] += 1
                print(f"[ok]   {fixture.name}: rejected explicitly ({fixture.expect_error})")
            except (Diff, CliError) as exc:
                failures.append(str(exc))
                print(f"[FAIL] {exc}")
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
    print(
        "formats: csv {csv_checks} tables, sql {sql_checks} replays, stats {stats_checks} checks, "
        "errors {error_checks}".format(**stats)
    )
    print(f"passed {stats['checks']}, failed {len(failures)}")
    if failures:
        for failure in failures[:10]:
            print(f"  - {failure}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))