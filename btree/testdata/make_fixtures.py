#!/usr/bin/env python3
"""生成 btree 层测试用的 SQLite fixture（只用 Python 标准库 sqlite3）。

用法：python3 btree/testdata/make_fixtures.py
重新生成后请同步更新 btree/real_db_wbtest.mbt 里的 ROOT_PAGE / 行数常量。

三个库都固定 page_size=512，文件都很小（每个 < 50KB）：
- large_table.db   : 120 行，每 20 行带 1200 字节 blob（强制溢出链 + 三层 b-tree）
- single_page.db   : 3 行，整棵树只有一个叶页
- without_rowid.db : WITHOUT ROWID 表，走索引 b-tree（表遍历应返回空）
"""

import os
import sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
PAGE_SIZE = 512
BLOB_UNIT = b"\xab\xcd"  # real_db_wbtest.mbt 里按这个双字节模式找 blob


def fresh(name):
    path = os.path.join(HERE, name)
    if os.path.exists(path):
        os.remove(path)
    # 关掉 journal，保证目录里只留一个 .db
    return path


def connect(path):
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA page_size=%d" % PAGE_SIZE)
    conn.execute("PRAGMA journal_mode=DELETE")
    conn.execute("PRAGMA secure_delete=OFF")
    return conn


def size_of(path):
    return os.path.getsize(path)


def build_large():
    path = fresh("large_table.db")
    conn = connect(path)
    conn.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT, b BLOB)")
    rows = []
    for i in range(1, 121):
        v = "row-%03d-" % i + "x" * 32
        b = BLOB_UNIT * 600 if i % 20 == 0 else b""
        rows.append((i, v, b))
    conn.executemany("INSERT INTO t VALUES(?,?,?)", rows)
    conn.commit()
    root = conn.execute(
        "SELECT rootpage FROM sqlite_master WHERE name='t'"
    ).fetchone()[0]
    count = conn.execute("SELECT count(*) FROM t").fetchone()[0]
    conn.close()
    return path, root, count


def build_single_page():
    path = fresh("single_page.db")
    conn = connect(path)
    conn.execute("CREATE TABLE s(id INTEGER PRIMARY KEY, v TEXT)")
    rows = [(i, "v%d" % i) for i in range(1, 4)]
    conn.executemany("INSERT INTO s VALUES(?,?)", rows)
    conn.commit()
    root = conn.execute(
        "SELECT rootpage FROM sqlite_master WHERE name='s'"
    ).fetchone()[0]
    count = conn.execute("SELECT count(*) FROM s").fetchone()[0]
    conn.close()
    return path, root, count


def build_without_rowid():
    path = fresh("without_rowid.db")
    conn = connect(path)
    conn.execute("CREATE TABLE w(k TEXT PRIMARY KEY, v TEXT) WITHOUT ROWID")
    rows = [("k%d" % i, "value-%d" % i) for i in range(1, 6)]
    conn.executemany("INSERT INTO w VALUES(?,?)", rows)
    conn.commit()
    root = conn.execute(
        "SELECT rootpage FROM sqlite_master WHERE name='w'"
    ).fetchone()[0]
    count = conn.execute("SELECT count(*) FROM w").fetchone()[0]
    conn.close()
    return path, root, count


def main():
    print("sqlite version:", sqlite3.sqlite_version)
    for name, builder in [
        ("large_table.db", build_large),
        ("single_page.db", build_single_page),
        ("without_rowid.db", build_without_rowid),
    ]:
        path, root, count = builder()
        pages = size_of(path) // PAGE_SIZE
        print(
            "%-18s root_page=%-3d rows=%-3d bytes=%-6d pages=%d"
            % (name, root, count, size_of(path), pages)
        )


if __name__ == "__main__":
    main()
