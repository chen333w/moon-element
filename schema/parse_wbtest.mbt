// CREATE TABLE 文本解析：列名、声明类型、NOT NULL、PRIMARY KEY、WITHOUT ROWID。

///|
test "parse_columns reads names, declared types and constraints" {
  let columns = parse_columns(
    "CREATE TABLE t (a INTEGER, b TEXT NOT NULL, c, d BLOB DEFAULT x'00')",
  )
  assert_eq(columns.length(), 4)
  assert_eq(columns[0].name, "a")
  assert_eq(columns[0].declared_type, "INTEGER")
  assert_false(columns[0].not_null)
  assert_eq(columns[1].name, "b")
  assert_eq(columns[1].declared_type, "TEXT")
  assert_true(columns[1].not_null)
  assert_eq(columns[2].name, "c")
  assert_eq(columns[2].declared_type, "")
  assert_eq(columns[3].name, "d")
  assert_eq(columns[3].declared_type, "BLOB")
}

///|
test "parse_columns strips quotes and keeps keyword column names" {
  let columns = parse_columns(
    "CREATE TABLE \"t\" (\"select\" INTEGER, `from` TEXT, [order] REAL, 'group' BLOB)",
  )
  assert_eq(columns.length(), 4)
  assert_eq(columns[0].name, "select")
  assert_eq(columns[1].name, "from")
  assert_eq(columns[2].name, "order")
  assert_eq(columns[3].name, "group")
}

///|
test "parse_columns keeps parenthesised types together" {
  let columns = parse_columns(
    "CREATE TABLE t (a VARCHAR(20) NOT NULL, b NUMERIC(10, 2), c UNSIGNED BIG INT)",
  )
  assert_eq(columns[0].declared_type, "VARCHAR(20)")
  assert_eq(columns[1].declared_type, "NUMERIC(10,2)")
  assert_eq(columns[2].declared_type, "UNSIGNED BIG INT")
}

///|
test "an inline PRIMARY KEY marks the column" {
  let columns = parse_columns(
    "CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)",
  )
  assert_true(columns[0].primary_key)
  assert_false(columns[1].primary_key)
}

///|
test "a table level PRIMARY KEY marks every listed column" {
  let columns = parse_columns(
    "CREATE TABLE pair (a INTEGER NOT NULL, b TEXT NOT NULL, payload TEXT, PRIMARY KEY (a, b))",
  )
  assert_eq(columns.length(), 3)
  assert_true(columns[0].primary_key)
  assert_true(columns[1].primary_key)
  assert_false(columns[2].primary_key)
  // PRIMARY KEY 不是列定义，不能多出一列
  assert_eq(columns[2].name, "payload")
}

///|
test "a named table constraint still marks its columns" {
  let columns = parse_columns(
    "CREATE TABLE t (a INTEGER, b TEXT, CONSTRAINT pk PRIMARY KEY (b))",
  )
  assert_false(columns[0].primary_key)
  assert_true(columns[1].primary_key)
}

///|
test "has_without_rowid spots the WITHOUT ROWID table" {
  assert_true(
    has_without_rowid(
      "CREATE TABLE w (k TEXT PRIMARY KEY, v INTEGER) WITHOUT ROWID",
    ),
  )
  assert_false(
    has_without_rowid("CREATE TABLE t (k TEXT PRIMARY KEY, v INTEGER)"),
  )
}

///|
test "non-ASCII column names survive the tokenizer" {
  // 走 Array[Char] 扫描：emoji 是代理对，按 UTF-16 下标会截断
  let columns = parse_columns(
    "CREATE TABLE t (\"名😀\" TEXT NOT NULL, \"列\" INTEGER)",
  )
  assert_eq(columns.length(), 2)
  assert_eq(columns[0].name, "名😀")
  assert_eq(columns[1].name, "列")
}

///|
test "unparsable SQL yields no columns" {
  assert_eq(parse_columns("").length(), 0)
  assert_eq(parse_columns("CREATE TABLE t").length(), 0)
  assert_eq(parse_columns("CREATE TABLE t ()").length(), 0)
}
