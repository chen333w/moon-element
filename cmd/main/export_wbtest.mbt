///|
test "csv_field quotes only when the value needs it" {
  assert_eq(csv_field("plain"), "plain")
  assert_eq(csv_field("has, comma"), "\"has, comma\"")
  assert_eq(csv_field("quo\"te"), "\"quo\"\"te\"")
  assert_eq(csv_field("two\nlines"), "\"two\nlines\"")
  assert_eq(csv_field(""), "")
}

///|
test "csv and sql render values the way sqlite reads them back" {
  assert_eq(value_text(@format.Value::Null), "")
  assert_eq(value_text(@format.Value::Int(-7L)), "-7")
  assert_eq(value_text(@format.Value::Blob(b"\x00\xff")), "00ff")
  assert_eq(sql_literal(@format.Value::Null), "NULL")
  assert_eq(sql_literal(@format.Value::Int(3L)), "3")
  assert_eq(sql_literal(@format.Value::Text("it's")), "'it''s'")
  assert_eq(sql_literal(@format.Value::Blob(b"\x00\xff")), "x'00ff'")
}

///|
test "identifiers are quoted and escaped" {
  assert_eq(quote_ident("users"), "\"users\"")
  assert_eq(quote_ident("my table"), "\"my table\"")
  assert_eq(quote_ident("we\"ird"), "\"we\"\"ird\"")
}

///|
test "json_string stays ascii and round-trips" {
  assert_eq(json_string("plain"), "\"plain\"")
  assert_eq(json_string("a\"b"), "\"a\\\"b\"")
  assert_eq(json_string("line\nbreak"), "\"line\\nbreak\"")
  // 非 ASCII 一律转义，保证输出是纯 ASCII
  assert_eq(json_string("中"), "\"\\u4e2d\"")
  assert_eq(json_string("😀"), "\"\\ud83d\\ude00\"")
}

///|
test "hex_lower renders bytes without prefix" {
  assert_eq(hex_lower(b""), "")
  assert_eq(hex_lower(b"\x00\x01\xfe\xff"), "0001feff")
}
