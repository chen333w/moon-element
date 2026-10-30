// 确定性 JSON 输出：字段顺序固定，值按 SQLite 的存储类渲染。

///|
fn json_escape(s : String) -> String {
  let hexdg : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out : Array[Char] = []
  for c in s {
    let v = c.to_int()
    if v == 34 {
      out.push('\\')
      out.push('"')
    } else if v == 92 {
      out.push('\\')
      out.push('\\')
    } else if v == 10 {
      out.push('\\')
      out.push('n')
    } else if v == 13 {
      out.push('\\')
      out.push('r')
    } else if v == 9 {
      out.push('\\')
      out.push('t')
    } else if v < 32 {
      out.push('\\')
      out.push('u')
      out.push('0')
      out.push('0')
      out.push(hexdg[v / 16])
      out.push(hexdg[v % 16])
    } else {
      out.push(c)
    }
  }
  String::from_iter(out.iter())
}

///|
fn has_float_marker(text : String) -> Bool {
  for c in text {
    if c == '.' || c == 'e' || c == 'E' {
      return true
    }
  }
  false
}

///|
/// REAL 的稳定表示：必须是合法 JSON 数字，且解析回来还是同一个 double。
fn json_real(d : Double) -> String {
  let text = d.to_string()
  if text == "inf" {
    "1e999"
  } else if text == "-inf" {
    "-1e999"
  } else if text == "nan" {
    // JSON 没有 NaN；SQLite 也不会存 NaN
    "null"
  } else if has_float_marker(text) {
    text
  } else {
    text + ".0"
  }
}

///|
fn hex_of(bytes : Bytes) -> String {
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out : Array[Char] = []
  for i in 0..<bytes.length() {
    let b = bytes[i].to_int()
    out.push(digits[b / 16])
    out.push(digits[b % 16])
  }
  String::from_iter(out.iter())
}

///|
/// 一个值：`{"type":"integer","value":1}`；null 不带 value 字段。
pub fn value_json(value : @format.Value) -> String {
  match value {
    @format.Value::Null => "{\"type\":\"null\"}"
    @format.Value::Int(v) => "{\"type\":\"integer\",\"value\":\{v}}"
    @format.Value::Real(d) => "{\"type\":\"real\",\"value\":" + json_real(d) + "}"
    @format.Value::Text(s) => "{\"type\":\"text\",\"value\":\"" + json_escape(s) + "\"}"
    @format.Value::Blob(b) => "{\"type\":\"blob\",\"value\":\"" + hex_of(b) + "\"}"
  }
}

///|
/// schema 输出里的一个表。
pub fn table_json(table : TableInfo) -> String {
  let out : Array[Char] = []
  let push = fn(s : String) -> Unit {
    let n = s.char_length()
    let mut i : Int32 = 0
    while i < n {
      match s.get_char(i) {
        Some(c) => out.push(c)
        None => ()
      }
      i = i + 1
    }
  }
  push("{\"name\":\"" + json_escape(table.name) + "\",")
  push("\"sql\":\"" + json_escape(table.sql) + "\",")
  push("\"root_page\":\{table.root_page},")
  let wr = if table.without_rowid { "true" } else { "false" }
  push("\"without_rowid\":" + wr + ",")
  push("\"columns\":[")
  let mut first = true
  for column in table.columns {
    if !first {
      push(",")
    }
    first = false
    push("{\"name\":\"" + json_escape(column.name) + "\",")
    push("\"declared_type\":\"" + json_escape(column.declared_type) + "\",")
    let nn = if column.not_null { "true" } else { "false" }
    let pk = if column.primary_key { "true" } else { "false" }
    push("\"not_null\":" + nn + ",")
    push("\"primary_key\":" + pk + "}")
  }
  push("]}")
  String::from_iter(out.iter())
}

///|
/// dump 输出的一行。WITHOUT ROWID 表没有 rowid，输出 null。
pub fn row_json(table : String, row : Row, without_rowid : Bool) -> String {
  let out : Array[Char] = []
  let push = fn(s : String) -> Unit {
    let n = s.char_length()
    let mut i : Int32 = 0
    while i < n {
      match s.get_char(i) {
        Some(c) => out.push(c)
        None => ()
      }
      i = i + 1
    }
  }
  push("{\"table\":\"" + json_escape(table) + "\",\"rowid\":")
  if without_rowid {
    push("null")
  } else {
    push("\{row.rowid}")
  }
  push(",\"values\":[")
  let mut first = true
  for value in row.values {
    if !first {
      push(",")
    }
    first = false
    push(value_json(value))
  }
  push("]}")
  String::from_iter(out.iter())
}