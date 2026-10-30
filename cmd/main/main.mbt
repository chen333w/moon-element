// moon-lite CLI：把库文件读成确定性 JSON。tools/verify_sqlite.py 也走这套输出对拍。

///|
fn usage() -> Unit {
  eprintln("moon-lite: read a SQLite 3 database file, no C dependency")
  eprintln("")
  eprintln("Usage:")
  eprintln("  moon run cmd/main -- schema <file.db>")
  eprintln("  moon run cmd/main -- dump <file.db> [--table NAME] [--limit N]")
  eprintln("")
  eprintln("  schema   one JSON line: page size, encoding, tables and columns")
  eprintln(
    "  dump     one JSON line per row: table, rowid, values (--format json|csv|sql)",
  )
  eprintln("  stats    one JSON line: file size, page count, rows per table")
}

///|
priv struct Options {
  file : String
  table : String?
  limit : Int32?
  format : String
}

///|
fn char_or(s : String, i : Int32) -> Char {
  match s.get_char(i) {
    Some(c) => c
    None => ' '
  }
}

///|
fn parse_count(text : String) -> Int32? {
  let n = text.char_length()
  if n == 0 {
    return None
  }
  let mut value = 0
  let mut i : Int32 = 0
  while i < n {
    let v = char_or(text, i).to_int()
    if v < 48 || v > 57 {
      return None
    }
    value = value * 10 + (v - 48)
    if value > 100000000 {
      return None
    }
    i = i + 1
  }
  Some(value)
}

///|
/// 子命令之后的参数：一个文件位置，可选 --table / --limit。
fn parse_options(args : Array[String], from : Int32) -> Options? {
  let mut file : String? = None
  let mut table : String? = None
  let mut limit : Int32? = None
  let mut format = "json"
  let mut i = from
  while i < args.length() {
    let arg = args[i]
    if arg == "--table" {
      if i + 1 >= args.length() {
        return None
      }
      table = Some(args[i + 1])
      i = i + 2
    } else if arg == "--format" {
      if i + 1 >= args.length() {
        return None
      }
      let value = args[i + 1]
      if value != "json" && value != "csv" && value != "sql" {
        eprintln(
          "Error: --format only accepts json, csv or sql, got \"" + value + "\"",
        )
        return None
      }
      format = value
      i = i + 2
    } else if arg == "--limit" {
      if i + 1 >= args.length() {
        return None
      }
      match parse_count(args[i + 1]) {
        Some(n) => limit = Some(n)
        None => return None
      }
      i = i + 2
    } else if arg == "--help" || arg == "-h" || arg.has_prefix("--") {
      return None
    } else {
      match file {
        Some(_) => return None
        None => {
          file = Some(arg)
          i = i + 1
        }
      }
    }
  }
  match file {
    Some(path) => Some({ file: path, table, limit, format, })
    None => None
  }
}

///|
fn read_bytes(path : String) -> Bytes? {
  Some(@fs.read_file_to_bytes(path)) catch {
    _ => None
  }
}

///|
fn schema_json(db : @db.Database) -> String {
  let mut acc = "{\"page_size\":" + db.page_size().to_string()
  acc = acc + ",\"encoding\":\"" + db.encoding_label() + "\""
  acc = acc + ",\"sqlite_version\":" + db.sqlite_version().to_string()
  acc = acc + ",\"tables\":["
  let mut first = true
  for table in db.tables() {
    if !first {
      acc = acc + ","
    }
    first = false
    acc = acc + @db.table_json(table)
  }
  acc + "]}"
}

///|
fn dump_lines(db : @db.Database, options : Options) -> Array[String] raise {
  let out : Array[String] = []
  for table in db.tables() {
    let wanted = match options.table {
      Some(name) => name == table.name
      None => true
    }
    if wanted {
      let mut emitted = 0
      for row in db.rows(table.name) {
        let full = match options.limit {
          Some(n) => emitted >= n
          None => false
        }
        if !full {
          out.push(@db.row_json(table.name, row, table.without_rowid))
          emitted = emitted + 1
        }
      }
    }
  }
  out
}

///|
fn run(args : Array[String]) -> Int32 raise {
  let mut index = 0
  let mut command = ""
  while index < args.length() {
    let arg = args[index]
    if arg == "schema" || arg == "dump" || arg == "stats" {
      command = arg
      break
    }
    index = index + 1
  }
  if command == "" {
    usage()
    return 2
  }
  let options = match parse_options(args, index + 1) {
    Some(o) => o
    None => {
      usage()
      return 2
    }
  }
  if !@fs.path_exists(options.file) {
    eprintln("Error: no such file: \{options.file}")
    return 2
  }
  let bytes = match read_bytes(options.file) {
    Some(b) => b
    None => {
      eprintln("Error: cannot read \{options.file}")
      return 2
    }
  }
  let db = @db.Database::open(bytes) catch {
    @db.DbError(message) => {
      eprintln("Error: " + message)
      return 2
    }
    _ => {
      eprintln("Error: \{options.file} is not a readable SQLite 3 database")
      return 2
    }
  }
  if command == "schema" {
    println(schema_json(db))
  } else if command == "stats" {
    println(stats_json(db, bytes.length()))
  } else if options.format == "csv" {
    for line in csv_lines(db, options) {
      println(line)
    }
  } else if options.format == "sql" {
    for line in sql_lines(db, options) {
      println(line)
    }
  } else {
    for line in dump_lines(db, options) {
      println(line)
    }
  }
  0
}

///|
fn main {
  let code = run(@env.args()) catch {
    _ => {
      eprintln(
        "Error: cannot read the database (corrupt file, or a table the reader does not support)",
      )
      2
    }
  }
  @sys.exit(code)
}

///|
fn wanted(options : Options, table : @db.TableInfo) -> Bool {
  match options.table {
    Some(name) => name == table.name
    None => true
  }
}

///|
fn under_limit(options : Options, emitted : Int32) -> Bool {
  match options.limit {
    Some(n) => emitted < n
    None => true
  }
}

///|
fn hex_lower(bytes : Bytes) -> String {
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
fn char_of(s : String, i : Int32) -> Char {
  match s.get_char(i) {
    Some(c) => c
    None => '\u{0}'
  }
}

///|
/// 把 old 全部替换成 new；只为 SQL 的单引号双写这种小场景服务。
fn replace_all(text : String, old : Char, new : String) -> String {
  let out : Array[Char] = []
  for i in 0..<text.length() {
    let c = char_of(text, i)
    if c == old {
      for j in 0..<new.length() {
        out.push(char_of(new, j))
      }
    } else {
      out.push(c)
    }
  }
  String::from_iter(out.iter())
}

///|
/// RFC 4180：含逗号、引号、换行的字段要用双引号包起来，内部引号写成两个。
fn csv_field(raw : String) -> String {
  let mut needs_quotes = false
  for i in 0..<raw.length() {
    let c = char_of(raw, i)
    if c == ',' || c == '"' || c == '\n' || c == '\r' {
      needs_quotes = true
    }
  }
  if !needs_quotes {
    return raw
  }
  "\"" + replace_all(raw, '"', "\"\"") + "\""
}

///|
fn value_text(value : @format.Value) -> String {
  match value {
    @format.Value::Null => ""
    @format.Value::Int(v) => v.to_string()
    @format.Value::Real(d) => "\{d}"
    @format.Value::Text(s) => s
    @format.Value::Blob(b) => hex_lower(b)
  }
}

///|
fn csv_lines(db : @db.Database, options : Options) -> Array[String] raise {
  let out : Array[String] = []
  for table in db.tables() {
    if wanted(options, table) {
      let mut header = ""
      let mut first = true
      for column in table.columns {
        if !first {
          header = header + ","
        }
        first = false
        header = header + csv_field(column.name)
      }
      out.push(header)
      let mut emitted : Int32 = 0
      for row in db.rows(table.name) {
        if under_limit(options, emitted) {
          let mut line = ""
          let mut first_cell = true
          for value in row.values {
            if !first_cell {
              line = line + ","
            }
            first_cell = false
            line = line + csv_field(value_text(value))
          }
          out.push(line)
          emitted = emitted + 1
        }
      }
    }
  }
  out
}

///|
fn sql_literal(value : @format.Value) -> String {
  match value {
    @format.Value::Null => "NULL"
    @format.Value::Int(v) => v.to_string()
    @format.Value::Real(d) => "\{d}"
    @format.Value::Text(s) => "'" + replace_all(s, '\'', "''") + "'"
    @format.Value::Blob(b) => "x'" + hex_lower(b) + "'"
  }
}

///|
fn quote_ident(name : String) -> String {
  "\"" + replace_all(name, '"', "\"\"") + "\""
}

///|
fn sql_lines(db : @db.Database, options : Options) -> Array[String] raise {
  let out : Array[String] = []
  // 先输出建表语句，导出的 SQL 才能独立重建一个库（sqlite_ 开头的内部表跳过）。
  for table in db.tables() {
    if wanted(options, table) && table.sql.length() > 0 {
      out.push(table.sql + ";")
    }
  }
  for table in db.tables() {
    if wanted(options, table) {
      let mut emitted : Int32 = 0
      for row in db.rows(table.name) {
        if under_limit(options, emitted) {
          let mut line = "INSERT INTO " + quote_ident(table.name) + " VALUES ("
          let mut first = true
          for value in row.values {
            if !first {
              line = line + ", "
            }
            first = false
            line = line + sql_literal(value)
          }
          out.push(line + ");")
          emitted = emitted + 1
        }
      }
    }
  }
  out
}

///|
fn stats_json(db : @db.Database, file_bytes : Int32) -> String {
  let page_size = db.page_size()
  let pages = if page_size == 0 { 0 } else { file_bytes / page_size }
  let mut acc = "{\"file_bytes\":" + file_bytes.to_string()
  acc = acc + ",\"page_size\":" + page_size.to_string()
  acc = acc + ",\"page_count\":" + pages.to_string()
  acc = acc + ",\"encoding\":\"" + db.encoding_label() + "\""
  acc = acc + ",\"sqlite_version\":" + db.sqlite_version().to_string()
  acc = acc + ",\"tables\":["
  let mut first_table = true
  for table in db.tables() {
    if !first_table {
      acc = acc + ","
    }
    first_table = false
    let rows = db.rows(table.name) catch { _ => [] }
    let without = if table.without_rowid { "true" } else { "false" }
    acc = acc + "{\"name\":" + json_string(table.name)
    acc = acc + ",\"rows\":" + rows.length().to_string()
    acc = acc + ",\"without_rowid\":" + without + "}"
  }
  acc + "]}"
}

///|
/// 纯 ASCII 的 JSON 字符串转义；非 ASCII 走 \uXXXX（BMP 外拆代理对），保证输出可被任何 JSON 解析器读回。
fn json_string(raw : String) -> String {
  let out : Array[Char] = ['"']
  let push_hex4 = fn(code : Int32) -> Unit {
    let digits : Array[Char] = [
      '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e',
      'f',
    ]
    out.push('\\')
    out.push('u')
    out.push(digits[(code >> 12) & 15])
    out.push(digits[(code >> 8) & 15])
    out.push(digits[(code >> 4) & 15])
    out.push(digits[code & 15])
  }
  for i in 0..<raw.length() {
    let c = char_of(raw, i)
    let code = c.to_int()
    if c == '"' {
      out.push('\\')
      out.push('"')
    } else if c == '\\' {
      out.push('\\')
      out.push('\\')
    } else if c == '\n' {
      out.push('\\')
      out.push('n')
    } else if c == '\r' {
      out.push('\\')
      out.push('r')
    } else if c == '\t' {
      out.push('\\')
      out.push('t')
    } else if code < 0x20 {
      push_hex4(code)
    } else if code < 0x7f {
      out.push(c)
    } else {
      push_hex4(code)
    }
  }
  out.push('"')
  String::from_iter(out.iter())
}
