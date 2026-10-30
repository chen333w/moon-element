// 从 sqlite_master 里的 CREATE TABLE 文本恢复列信息与 WITHOUT ROWID 标记。
// 只覆盖这个读取器要展示的字段，不做完整 SQL 解析。
// 所有扫描都在 Array[Char] 上做：MoonBit 的字符串按 UTF-16 单位取值，
// 直接拿 char_length() 配合下标循环会漏掉最后一个字符（emoji 这类代理对）。

///|
pub(all) struct ParsedColumn {
  name : String
  declared_type : String
  not_null : Bool
  primary_key : Bool
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn lower_char(c : Char) -> Char {
  let v = c.to_int()
  if v >= 65 && v <= 90 {
    (v + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn lower(s : String) -> String {
  let out : Array[Char] = []
  for c in s {
    out.push(lower_char(c))
  }
  String::from_iter(out.iter())
}

///|
fn slice_chars(chars : Array[Char], from : Int32, to : Int32) -> String {
  let n = chars.length()
  let start = if from < 0 { 0 } else if from > n { n } else { from }
  let stop = if to > n { n } else if to < start { start } else { to }
  let out : Array[Char] = []
  let mut i = start
  while i < stop {
    out.push(chars[i])
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
fn contains_ci(haystack : String, needle : String) -> Bool {
  let hay = lower(haystack).to_array()
  let pat = lower(needle).to_array()
  let hn = hay.length()
  let pn = pat.length()
  if pn == 0 {
    return true
  }
  let mut i = 0
  while i + pn <= hn {
    let mut k = 0
    let mut same = true
    while k < pn {
      if hay[i + k] != pat[k] {
        same = false
        k = pn
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
/// 词法切分：括号与逗号各自成块，引号里的名字去掉引号，其余按空白切。
fn tokenize(chars : Array[Char]) -> Array[String] {
  let out : Array[String] = []
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if is_space(c) {
      i = i + 1
    } else if c == '(' || c == ')' || c == ',' {
      out.push(slice_chars(chars, i, i + 1))
      i = i + 1
    } else if c == '"' || c == '`' || c == '\'' || c == '[' {
      let close = if c == '[' { ']' } else { c }
      let start = i + 1
      i = i + 1
      while i < n && chars[i] != close {
        i = i + 1
      }
      out.push(slice_chars(chars, start, i))
      i = i + 1
    } else {
      let start = i
      while i < n {
        let d = chars[i]
        if is_space(d) || d == '(' || d == ')' || d == ',' {
          break
        }
        i = i + 1
      }
      out.push(slice_chars(chars, start, i))
    }
  }
  out
}

///|
fn is_constraint_word(word : String) -> Bool {
  let w = lower(word)
  w == "not" ||
  w == "null" ||
  w == "primary" ||
  w == "unique" ||
  w == "check" ||
  w == "default" ||
  w == "references" ||
  w == "collate" ||
  w == "generated" ||
  w == "as" ||
  w == "constraint"
}

///|
/// 类型块拼接：`VARCHAR(20)` 不插空格，`UNSIGNED BIG INT` 保留空格。
fn join_type(tokens : Array[String]) -> String {
  let out : Array[Char] = []
  let mut previous = ""
  for token in tokens {
    let tight = token == "(" ||
      token == ")" ||
      token == "," ||
      previous == "(" ||
      previous == ","
    if previous != "" && !tight {
      out.push(' ')
    }
    for c in token {
      out.push(c)
    }
    previous = token
  }
  String::from_iter(out.iter())
}

///|
/// 在 [from, to) 里按顶层逗号切分（括号内的逗号不切）。
fn split_top_level(
  chars : Array[Char],
  from : Int32,
  to : Int32,
) -> Array[String] {
  let out : Array[String] = []
  let mut depth = 0
  let mut start = from
  let mut i = from
  while i < to {
    let c = chars[i]
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      depth = depth - 1
    } else if c == ',' && depth == 0 {
      out.push(slice_chars(chars, start, i))
      start = i + 1
    }
    i = i + 1
  }
  out.push(slice_chars(chars, start, to))
  out
}

///|
fn token_texts(
  tokens : Array[String],
  from : Int32,
  to : Int32,
) -> Array[String] {
  let out : Array[String] = []
  let mut i = from
  while i < to {
    out.push(tokens[i])
    i = i + 1
  }
  out
}

///|
/// 最外层括号的位置：`(open, close)`。
fn body_range(chars : Array[Char]) -> (Int32, Int32)? {
  let n = chars.length()
  let mut open = -1
  let mut depth = 0
  let mut last_close = -1
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '(' {
      if open < 0 {
        open = i
      }
      depth = depth + 1
    } else if c == ')' {
      depth = depth - 1
      if depth == 0 {
        last_close = i
      }
    }
    i = i + 1
  }
  if open < 0 || last_close <= open {
    None
  } else {
    Some((open, last_close))
  }
}

///|
/// 是否 WITHOUT ROWID 表（索引 b-tree，没有 rowid）。
pub fn has_without_rowid(sql : String) -> Bool {
  contains_ci(sql, "without")
}

///|
/// 从 CREATE TABLE 文本解析列。表级 PRIMARY KEY(a, b) 会把列标记为 primary_key。
pub fn parse_columns(sql : String) -> Array[ParsedColumn] {
  let columns : Array[ParsedColumn] = []
  let chars = sql.to_array()
  match body_range(chars) {
    None => columns
    Some(range) => {
      let parts = split_top_level(chars, range.0 + 1, range.1)
      let pk_names : Array[String] = []
      for part in parts {
        let tokens = tokenize(part.to_array())
        if tokens.length() == 0 {
          continue
        }
        let head = lower(tokens[0])
        if head == "primary" ||
          head == "unique" ||
          head == "check" ||
          head == "foreign" ||
          head == "constraint" {
          // 表级约束：只关心 PRIMARY KEY 的列名列表
          let mut at = 0
          if head == "constraint" {
            at = 2
          }
          if at + 1 < tokens.length() &&
            lower(tokens[at]) == "primary" &&
            lower(tokens[at + 1]) == "key" {
            let mut k = at + 2
            while k < tokens.length() {
              let t = tokens[k]
              if t == "(" || t == "," || t == ")" {
                k = k + 1
                continue
              }
              pk_names.push(lower(t))
              k = k + 1
            }
          }
          continue
        }
        // 列定义：名字 + 类型 + 约束
        let name = tokens[0]
        let mut not_null = false
        let mut primary_key = false
        let mut type_end = tokens.length()
        let mut k = 1
        while k < tokens.length() {
          if is_constraint_word(tokens[k]) {
            type_end = k
            break
          }
          k = k + 1
        }
        let declared_type = join_type(token_texts(tokens, 1, type_end))
        let mut k = type_end
        while k < tokens.length() {
          let word = lower(tokens[k])
          if word == "not" &&
            k + 1 < tokens.length() &&
            lower(tokens[k + 1]) == "null" {
            not_null = true
            k = k + 2
            continue
          }
          if word == "primary" &&
            k + 1 < tokens.length() &&
            lower(tokens[k + 1]) == "key" {
            primary_key = true
            k = k + 2
            continue
          }
          k = k + 1
        }
        columns.push({ name, declared_type, not_null, primary_key, })
      }
      // 表级 PRIMARY KEY 命中的列补标记
      let mut index = 0
      for column in columns {
        let mut hit = false
        for pk in pk_names {
          if pk == lower(column.name) {
            hit = true
          }
        }
        if hit {
          columns[index] = {
            name: column.name,
            declared_type: column.declared_type,
            not_null: column.not_null,
            primary_key: true,
          }
        }
        index = index + 1
      }
      columns
    }
  }
}
