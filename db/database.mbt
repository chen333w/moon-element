// 文件头解析与 Database 的构造。100 字节头之后的页面读取交给 btree/。

///|
/// 打开数据库时报告的错误：文件太小、不是 SQLite、头部字段非法。
pub suberror DbError {
  DbError(String)
}

///|
fn has_magic(bytes : Bytes) -> Bool {
  let magic = "SQLite format 3"
  let n = magic.char_length()
  let mut i : Int32 = 0
  while i < n {
    match magic.get_char(i) {
      Some(c) => if bytes[i].to_int() != c.to_int() { return false }
      None => ()
    }
    i = i + 1
  }
  bytes[15].to_int() == 0
}

///|
fn is_power_of_two(v : Int32) -> Bool {
  v > 0 && (v & (v - 1)) == 0
}

///|
/// 已打开的数据库：保留原始字节，页面访问按需从 bytes 里切。
pub struct Database {
  bytes : Bytes
  page_size : Int32
  encoding : Int32
  version : Int32
}

///|
/// 校验 `SQLite format 3\0`、page size 与编码。page_size 字段为 1 表示 65536。
pub fn Database::open(bytes : Bytes) -> Database raise {
  if bytes.length() < 100 {
    raise DbError("file is shorter than the 100-byte SQLite header")
  }
  if !has_magic(bytes) {
    raise DbError("not a SQLite 3 database (bad header magic)")
  }
  // 文件头第 18/19 字节是写/读格式版本：1 = 回滚日志，2 = WAL。
  // WAL 库的最新数据在 -wal 文件里，只读主文件会读到旧快照，所以明确拒绝而不是静默返回旧数据。
  let write_version = bytes[18].to_int()
  let read_version = bytes[19].to_int()
  if write_version == 2 || read_version == 2 {
    raise DbError(
      "database is in WAL mode: uncommitted frames live in the -wal file, so reading only the main file would return a stale snapshot; checkpoint it first",
    )
  }
  let raw = @format.be_u16(bytes, 16)
  let page_size = if raw == 1 { 65536 } else { raw }
  if page_size < 512 || page_size > 65536 || !is_power_of_two(page_size) {
    raise DbError("invalid page size \{page_size}")
  }
  let encoding = @format.be_i32(bytes, 56)
  if encoding < 1 || encoding > 3 {
    raise DbError("unsupported text encoding \{encoding}")
  }
  let version = @format.be_i32(bytes, 96)
  { bytes, page_size, encoding, version, }
}

///|
pub fn Database::page_size(self : Database) -> Int32 {
  self.page_size
}

///|
pub fn Database::encoding(self : Database) -> Int32 {
  self.encoding
}

///|
/// 文件头里记录的是写库时的库版本号（如 3053004）。
pub fn Database::sqlite_version(self : Database) -> Int32 {
  self.version
}

///|
/// 编码的人类可读名，CLI 的 JSON 用它。
pub fn Database::encoding_label(self : Database) -> String {
  match self.encoding {
    1 => "UTF-8"
    2 => "UTF-16le"
    3 => "UTF-16be"
    _ => "unknown"
  }
}

///|
/// 原始字节，供 btree 层使用。
pub fn Database::bytes(self : Database) -> Bytes {
  self.bytes
}

///|
/// sqlite_master 里所有建表 SQL 按表名顺序拼起来。
pub fn Database::schema_sql(self : Database) -> String {
  let out : Array[Char] = []
  for table in self.tables() {
    for c in table.sql {
      out.push(c)
    }
    out.push('\n')
  }
  String::from_iter(out.iter())
}
