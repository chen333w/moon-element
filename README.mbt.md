# moon-lite

A pure MoonBit reader for the [SQLite 3 file format](https://www.sqlite.org/fileformat2.html): it
reads a database file as bytes and gives back tables, columns and rows. No C library, no FFI, no
`sqlite3` binary — so it works on every backend, including wasm and the browser.

```moonbit
let bytes = @fs.read_file("example.db")          // any way you get the bytes
let db = @db.Database::open(bytes)
for table in db.tables() {
  println(table.name)                            // columns, declared types, WITHOUT ROWID
  for row in db.rows(table.name) {
    println(row.rowid, row.values)               // Value: Null, Int, Real, Text, Blob
  }
}
```

## What it reads

- the 100-byte file header: page size (including 65536), write/read versions, payload fractions,
  encoding, schema cookie, freelist head, schema format number
- `sqlite_master` (page 1) and the `CREATE TABLE` text, to recover table names, root pages, column
  names, declared types, `NOT NULL` and `PRIMARY KEY`
- table b-trees: leaf and interior cells, the cell pointer array, rowid order
- record decoding: every serial type, including 1/2/3/4/6/8-byte integers, IEEE-754 doubles,
  UTF-8 and UTF-16 text
- payload overflow chains: a record larger than the local payload area spills into overflow pages,
  with the local length following the M/K rule from the format documentation rather than the
  spill threshold

## What it does not do

- no query engine: there is no SQL, only full-table scans in rowid order
- no writing: the file is only read
- no WAL or rollback-journal recovery, no incremental blob I/O, no encryption
- indexes are not traversed; `WITHOUT ROWID` tables read their storage b-tree directly

## Conformance

`tools/verify_sqlite.py` generates databases with Python's `sqlite3`, dumps them with this reader
and compares every row and value against SQLite's own answer:

```bash
python3 tools/verify_sqlite.py
```

## Commands

```bash
moon check --deny-warn --target all
moon test --target all --deny-warn
moon run cmd/main --target native -- schema example.db     # page size, encoding, tables and columns
moon run cmd/main --target native -- dump example.db       # one JSON line per row
```

## Layout

```
format/   byte cursor, varints, serial types, record and text decoding
btree/    page headers, cell decoding, table b-tree traversal, overflow chains
schema/   sqlite_master scan and CREATE TABLE column parsing
db/       the public Database API
cmd/main/ the CLI
```

## License

Apache-2.0.
