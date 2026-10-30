// JSON 输出测试：字段顺序、浮点表示、纯 ASCII 转义、WITHOUT ROWID 的 rowid。

///|
test "value_json renders every storage class" {
  assert_eq(value_json(@format.Value::Null), "{\"type\":\"null\"}")
  assert_eq(
    value_json(@format.Value::Int(42L)),
    "{\"type\":\"integer\",\"value\":42}",
  )
  assert_eq(
    value_json(@format.Value::Int(-9223372036854775807L)),
    "{\"type\":\"integer\",\"value\":-9223372036854775807}",
  )
  assert_eq(
    value_json(@format.Value::Real(1.5)),
    "{\"type\":\"real\",\"value\":1.5}",
  )
  assert_eq(
    value_json(@format.Value::Text("hi")),
    "{\"type\":\"text\",\"value\":\"hi\"}",
  )
  assert_eq(
    value_json(@format.Value::Blob(b"\x00\xff")),
    "{\"type\":\"blob\",\"value\":\"00ff\"}",
  )
}

///|
test "json_escape keeps the document ASCII and escapes markup" {
  assert_eq(json_escape("a\"b"), "a\\\"b")
  assert_eq(json_escape("a\\b"), "a\\\\b")
  assert_eq(json_escape("a\nb"), "a\\nb")
  assert_eq(json_escape("a\tb"), "a\\tb")
  assert_eq(json_escape("\u{01}"), "\\u0001")
  // 非 ASCII 一律 \uXXXX，emoji 拆成代理对
  assert_eq(json_escape("中"), "\\u4e2d")
  assert_eq(json_escape("🚀"), "\\ud83d\\ude80")
  assert_eq(json_escape("a😀b"), "a\\ud83d\\ude00b")
  assert_eq(json_escape("𝄞"), "\\ud834\\udd1e")
}

///|
test "json_real always stays a JSON number" {
  assert_eq(json_real(1.0), "1.0")
  assert_eq(json_real(-2.5), "-2.5")
  assert_eq(json_real(0.0), "0.0")
  assert_eq(json_real(1.5), "1.5")
}

///|
test "row_json emits a null rowid for WITHOUT ROWID tables" {
  let row : Row = {
    rowid: 7L,
    values: [@format.Value::Int(1L), @format.Value::Text("a")],
  }
  assert_eq(
    row_json("t", row, false),
    "{\"table\":\"t\",\"rowid\":7,\"values\":[{\"type\":\"integer\",\"value\":1},{\"type\":\"text\",\"value\":\"a\"}]}",
  )
  assert_eq(
    row_json("w", row, true),
    "{\"table\":\"w\",\"rowid\":null,\"values\":[{\"type\":\"integer\",\"value\":1},{\"type\":\"text\",\"value\":\"a\"}]}",
  )
}

///|
test "table_json keeps field order and column flags" {
  let table : TableInfo = {
    name: "t",
    sql: "CREATE TABLE t (id INTEGER PRIMARY KEY)",
    root_page: 2,
    columns: [
      {
        name: "id",
        declared_type: "INTEGER",
        not_null: true,
        primary_key: true,
      },
    ],
    without_rowid: false,
  }
  assert_eq(
    table_json(table),
    "{\"name\":\"t\",\"sql\":\"CREATE TABLE t (id INTEGER PRIMARY KEY)\",\"root_page\":2,\"without_rowid\":false,\"columns\":[{\"name\":\"id\",\"declared_type\":\"INTEGER\",\"not_null\":true,\"primary_key\":true}]}",
  )
}
