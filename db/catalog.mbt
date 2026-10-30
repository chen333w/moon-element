// 读 page 1 的 sqlite_master：表清单、列信息、整表行。

///|
/// sqlite_master 的列：type、name、tbl_name、rootpage、sql。
const MASTER_COLUMNS : Int = 5

///|
fn text_at(values : Array[@format.Value], index : Int) -> String {
  if index < 0 || index >= values.length() {
    return ""
  }
  match values[index] {
    @format.Value::Text(s) => s
    _ => ""
  }
}

///|
fn int_at(values : Array[@format.Value], index : Int) -> Int {
  if index < 0 || index >= values.length() {
    return 0
  }
  match values[index] {
    @format.Value::Int(v) => v.to_int()
    _ => 0
  }
}

///|
/// 从 page 1 读出所有表（跳过 sqlite_ 开头的内部表）。
pub fn Database::tables(self : Database) -> Array[TableInfo] {
  let out : Array[TableInfo] = []
  for entry in @btree.scan_table(self.bytes(), self.page_size(), 1) {
    let (_, offset, size) = entry
    let payload = @btree.read_payload(self.bytes(), self.page_size(), offset, size)
    let values = @format.decode_record_with_encoding(
      payload,
      0,
      MASTER_COLUMNS,
      self.encoding(),
    ).values
    if text_at(values, 0) == "table" {
      let name = text_at(values, 1)
      if !name.has_prefix("sqlite_") {
        let sql = text_at(values, 4)
        let parsed = @schema.parse_columns(sql)
        let columns : Array[ColumnInfo] = []
        for column in parsed {
          columns.push(
            {
              name: column.name,
              declared_type: column.declared_type,
              not_null: column.not_null,
              primary_key: column.primary_key,
            },
          )
        }
        let without_rowid = @schema.has_without_rowid(sql)
        if without_rowid {
          // WITHOUT ROWID 表的主键列隐含 NOT NULL
          let mut index = 0
          for column in columns {
            if column.primary_key {
              columns[index] = {
                name: column.name,
                declared_type: column.declared_type,
                not_null: true,
                primary_key: column.primary_key,
              }
            }
            index = index + 1
          }
        }
        out.push(
          {
            name: name,
            sql: sql,
            root_page: int_at(values, 3),
            columns: columns,
            without_rowid: without_rowid,
          },
        )
      }
    }
  }
  out
}

///|
/// sqlite_master 里按名字找一张表。
/// 返回 None 表示没有这张表；WITHOUT ROWID 表也返回（调用方自己看 without_rowid）。
pub fn Database::table(self : Database, name : String) -> TableInfo? {
  let mut found : TableInfo? = None
  for info in self.tables() {
    if info.name == name {
      found = Some(info)
    }
  }
  found
}

///|
/// 整表扫描，按 rowid 升序（WITHOUT ROWID 表走索引 b-tree，暂时读不到）。
pub fn Database::rows(self : Database, table : String) -> Array[Row] raise {
  let info = match self.table(table) {
    Some(info) => info
    None => {
      raise DbError("no such table: \{table}")
    }
  }
  let out : Array[Row] = []
  let ncols = info.columns.length()
  let alias = rowid_alias_index(info.columns, info.without_rowid)
  for entry in @btree.scan_table(self.bytes(), self.page_size(), info.root_page) {
    let (rowid, offset, size) = entry
    let payload = @btree.read_payload(self.bytes(), self.page_size(), offset, size)
    let values = @format.decode_record_with_encoding(
      payload,
      0,
      ncols,
      self.encoding(),
    ).values
    let values = if alias >= 0 && alias < values.length() {
      values[alias] = @format.Value::Int(rowid)
      values
    } else {
      values
    }
    out.push({ rowid: rowid, values: apply_affinity(values, info.columns) })
  }
  out
}

///|
fn trim_ascii(s : String) -> String {
  let chars = s.to_array()
  let n = chars.length()
  let mut start = 0
  while start < n && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  let mut stop = n
  while stop > start && (chars[stop - 1] == ' ' || chars[stop - 1] == '\t') {
    stop = stop - 1
  }
  let out : Array[Char] = []
  let mut i = start
  while i < stop {
    out.push(chars[i])
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
/// INTEGER PRIMARY KEY 是 rowid 别名：记录体里存 NULL，读回时要用 rowid 顶替。
/// 返回该列的下标；没有别名时返回 -1。
fn rowid_alias_index(columns : Array[ColumnInfo], without_rowid : Bool) -> Int {
  if without_rowid {
    return -1
  }
  let mut found = -1
  let mut pk_count = 0
  let mut i = 0
  for column in columns {
    if column.primary_key {
      pk_count = pk_count + 1
      if trim_ascii(lower_ascii(column.declared_type)) == "integer" {
        found = i
      }
    }
    i = i + 1
  }
  if pk_count == 1 {
    found
  } else {
    -1
  }
}

///|
fn lower_ascii(s : String) -> String {
  let out : Array[Char] = []
  let n = s.char_length()
  let mut i : Int32 = 0
  while i < n {
    match s.get_char(i) {
      Some(c) => {
        let v = c.to_int()
        if v >= 65 && v <= 90 {
          out.push((v + 32).unsafe_to_char())
        } else {
          out.push(c)
        }
      }
      None => ()
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
fn contains_ascii(haystack : String, needle : String) -> Bool {
  let hn = haystack.char_length()
  let nn = needle.char_length()
  if nn == 0 {
    return true
  }
  let mut i : Int32 = 0
  while i + nn <= hn {
    let mut k : Int32 = 0
    let mut same = true
    while k < nn {
      if char_at2(haystack, i + k) != char_at2(needle, k) {
        same = false
        k = nn
      } else {
        k = k + 1
      }
    }
    if same {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn char_at2(s : String, i : Int32) -> Char {
  match s.get_char(i) {
    Some(c) => c
    None => ' '
  }
}

///|
/// REAL 亲和性：这类列里存成整数的值，SQLite 读回时会强制成浮点。
fn has_real_affinity(declared_type : String) -> Bool {
  let t = lower_ascii(declared_type)
  contains_ascii(t, "real") || contains_ascii(t, "floa") || contains_ascii(t, "doub")
}

///|
fn apply_affinity(
  values : Array[@format.Value],
  columns : Array[ColumnInfo],
) -> Array[@format.Value] {
  let out : Array[@format.Value] = []
  let mut i = 0
  for value in values {
    let real = if i < columns.length() {
      has_real_affinity(columns[i].declared_type)
    } else {
      false
    }
    if real {
      match value {
        @format.Value::Int(v) => out.push(@format.Value::Real(v.to_double()))
        _ => out.push(value)
      }
    } else {
      out.push(value)
    }
    i = i + 1
  }
  out
}
