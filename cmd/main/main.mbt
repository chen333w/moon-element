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
  eprintln("  dump     one JSON line per row: table, rowid, values")
}

///|
priv struct Options {
  file : String
  table : String?
  limit : Int?
}

///|
fn char_or(s : String, i : Int32) -> Char {
  match s.get_char(i) {
    Some(c) => c
    None => ' '
  }
}

///|
fn parse_count(text : String) -> Int? {
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
fn parse_options(args : Array[String], from : Int) -> Options? {
  let mut file : String? = None
  let mut table : String? = None
  let mut limit : Int? = None
  let mut i = from
  while i < args.length() {
    let arg = args[i]
    if arg == "--table" {
      if i + 1 >= args.length() {
        return None
      }
      table = Some(args[i + 1])
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
    Some(path) => Some({ file: path, table: table, limit: limit })
    None => None
  }
}

///|
fn read_bytes(path : String) -> Bytes? {
  try {
    Some(@fs.read_file_to_bytes(path))
  } catch {
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
fn run(args : Array[String]) -> Int raise {
  let mut index = 0
  let mut command = ""
  while index < args.length() {
    let arg = args[index]
    if arg == "schema" || arg == "dump" {
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
    _ => {
      eprintln("Error: \{options.file} is not a readable SQLite 3 database")
      return 2
    }
  }
  if command == "schema" {
    println(schema_json(db))
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