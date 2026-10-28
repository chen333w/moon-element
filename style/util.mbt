// CSS 文本按 ASCII 处理。字符串工具逐码点构建，避免用已废弃的 substring。

///|
fn is_ascii_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// 取指定下标的字符；越界时返回空格（调用方都已做边界检查）。
fn char_at(s : String, i : Int32) -> Char {
  match s.get_char(i) {
    Some(c) => c
    None => ' '
  }
}

///|
fn is_ws_at(s : String, i : Int32) -> Bool {
  is_ascii_ws(char_at(s, i))
}

///|
/// 取 [from, to) 的子串，下标自动夹到合法范围。
fn slice_text(s : String, from : Int32, to : Int32) -> String {
  let n = s.char_length()
  let start = if from < 0 { 0 } else { from }
  let stop = if to > n { n } else { to }
  let out : Array[Char] = []
  let mut i = start
  while i < stop {
    match s.get_char(i) {
      Some(c) => out.push(c)
      None => ()
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
fn trim_ws(s : String) -> String {
  let n = s.char_length()
  let mut start = 0
  while start < n && is_ws_at(s, start) {
    start = start + 1
  }
  let mut stop = n
  while stop > start && is_ws_at(s, stop - 1) {
    stop = stop - 1
  }
  slice_text(s, start, stop)
}

///|
fn split_on(s : String, sep : Char) -> Array[String] {
  let out : Array[String] = []
  let n = s.char_length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if char_at(s, i) == sep {
      out.push(slice_text(s, start, i))
      start = i + 1
    }
    i = i + 1
  }
  out.push(slice_text(s, start, n))
  out
}

///|
/// 按空白切分，连续空白视作一个分隔符。
fn split_ws(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.char_length()
  let mut i = 0
  while i < n {
    let mut start = i
    while start < n && is_ws_at(s, start) {
      start = start + 1
    }
    let mut stop = start
    while stop < n && !is_ws_at(s, stop) {
      stop = stop + 1
    }
    if stop > start {
      out.push(slice_text(s, start, stop))
    }
    i = if stop > start { stop } else { n }
  }
  out
}

///|
fn find_char(s : String, ch : Char) -> Int32? {
  let n = s.char_length()
  let mut i = 0
  while i < n {
    if char_at(s, i) == ch {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn starts_with(s : String, prefix : String) -> Bool {
  let n = s.char_length()
  let m = prefix.char_length()
  if m > n {
    return false
  }
  slice_text(s, 0, m) == prefix
}

///|
fn ends_with(s : String, suffix : String) -> Bool {
  let n = s.char_length()
  let m = suffix.char_length()
  if m > n || m == 0 {
    return false
  }
  slice_text(s, n - m, n) == suffix
}

///|
/// 标识符字符：ASCII 字母、数字、连字符、下划线。
fn is_ident_char(c : Char) -> Bool {
  let v = c.to_int()
  (v >= 97 && v <= 122) ||
  (v >= 65 && v <= 90) ||
  (v >= 48 && v <= 57) ||
  v == 45 ||
  v == 95
}

///|
fn read_ident(s : String, start : Int32) -> (String, Int32) {
  let n = s.char_length()
  let mut i = start
  while i < n && is_ident_char(char_at(s, i)) {
    i = i + 1
  }
  (slice_text(s, start, i), i)
}

///|
fn digit_of(c : Char) -> Int32? {
  let v = c.to_int() - 48
  if v >= 0 && v <= 9 {
    Some(v)
  } else {
    None
  }
}

///|
fn hex_of(c : Char) -> Int32? {
  let v = c.to_int()
  if v >= 48 && v <= 57 {
    Some(v - 48)
  } else if v >= 97 && v <= 102 {
    Some(v - 87)
  } else if v >= 65 && v <= 70 {
    Some(v - 55)
  } else {
    None
  }
}

///|
/// 从 start 处扫描一个十进制数（可选符号、整数、可选小数），返回 (值, 结束下标)。
fn scan_number_at(s : String, start : Int32) -> (Double, Int32)? {
  let n = s.char_length()
  let mut i = start
  let mut negative = false
  if i < n {
    let c = char_at(s, i)
    if c == '-' {
      negative = true
      i = i + 1
    } else if c == '+' {
      i = i + 1
    }
  }
  let mut int_part : Int32 = 0
  let mut int_digits = 0
  while i < n {
    let ok = match s.get_char(i) {
      Some(c) =>
        match digit_of(c) {
          Some(d) => {
            int_part = int_part * 10 + d
            int_digits = int_digits + 1
            true
          }
          None => false
        }
      None => false
    }
    if !ok {
      break
    }
    i = i + 1
  }
  let mut frac_part : Int32 = 0
  let mut frac_digits = 0
  if i < n && char_at(s, i) == '.' {
    i = i + 1
    while i < n {
      let ok = match s.get_char(i) {
        Some(c) =>
          match digit_of(c) {
            Some(d) => {
              frac_part = frac_part * 10 + d
              frac_digits = frac_digits + 1
              true
            }
            None => false
          }
        None => false
      }
      if !ok {
        break
      }
      i = i + 1
    }
  }
  if int_digits == 0 && frac_digits == 0 {
    return None
  }
  let mut value = Double::from_int(int_part)
  if frac_digits > 0 {
    let mut scale = 1.0
    let mut k = 0
    while k < frac_digits {
      scale = scale * 10.0
      k = k + 1
    }
    value = value + Double::from_int(frac_part) / scale
  }
  if negative {
    value = -value
  }
  Some((value, i))
}

///|
/// 取尾部 `!important`，返回 (去掉它的值, 是否 important)。
fn strip_important(raw : String) -> (String, Bool) {
  let t = trim_ws(raw)
  let lower = t.to_lower()
  if ends_with(lower, "!important") {
    let cut = t.char_length() - 10
    (trim_ws(slice_text(t, 0, cut)), true)
  } else {
    (t, false)
  }
}
