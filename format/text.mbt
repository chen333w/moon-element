// 文本解码：SQLite 的文本列按数据库编码存储（1=UTF-8、2=UTF-16LE、3=UTF-16BE）。
// 非法、截断、过长编码一律替换成 U+FFFD，任何输入都不 panic。

///|
/// 把 [start, start+len) 夹到实际字节范围内，返回 (起点, 终点)。
fn clamp_range(bytes : Bytes, start : Int32, len : Int32) -> (Int32, Int32) {
  let total = bytes.length()
  let mut s = start
  if s < 0 {
    s = 0
  }
  if s > total {
    s = total
  }
  if len <= 0 {
    (s, s)
  } else if len > total - s {
    (s, total)
  } else {
    (s, s + len)
  }
}

///|
fn at_byte(bytes : Bytes, i : Int32) -> Int32 {
  bytes[i].to_int()
}

///|
/// 按 Unicode 标量值放字符；代理区与超出 0x10FFFF 的值都换成 U+FFFD。
fn push_code_point(out : Array[Char], cp : Int32) -> Unit {
  match cp.to_char() {
    Some(c) => out.push(c)
    None => out.push('\u{FFFD}')
  }
}

///|
/// UTF-8 解码。过长编码、孤立续字节、被截断的多字节序列都按 U+FFFD 处理，
/// 每次至少前进 1 字节，保证循环收敛。
fn decode_utf8_range(bytes : Bytes, start : Int32, end : Int32) -> String {
  let out : Array[Char] = []
  let mut i = start
  while i < end {
    let b0 = at_byte(bytes, i)
    if b0 < 0x80 {
      push_code_point(out, b0)
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 {
      // 2 字节：110xxxxx 10xxxxxx
      if i + 1 < end && (at_byte(bytes, i + 1) & 0xC0) == 0x80 {
        let cp = ((b0 & 0x1F) << 6) | (at_byte(bytes, i + 1) & 0x3F)
        if cp < 0x80 {
          out.push('\u{FFFD}')
        } else {
          push_code_point(out, cp)
        }
        i = i + 2
      } else {
        out.push('\u{FFFD}')
        i = i + 1
      }
    } else if (b0 & 0xF0) == 0xE0 {
      // 3 字节：1110xxxx 10xxxxxx 10xxxxxx
      if i + 2 < end &&
        (at_byte(bytes, i + 1) & 0xC0) == 0x80 &&
        (at_byte(bytes, i + 2) & 0xC0) == 0x80 {
        let cp = ((b0 & 0x0F) << 12) |
          ((at_byte(bytes, i + 1) & 0x3F) << 6) |
          (at_byte(bytes, i + 2) & 0x3F)
        if cp < 0x800 {
          out.push('\u{FFFD}')
        } else {
          // 代理区的 cp 会被 to_char 拒掉，自动变成 U+FFFD
          push_code_point(out, cp)
        }
        i = i + 3
      } else {
        out.push('\u{FFFD}')
        i = i + 1
      }
    } else if (b0 & 0xF8) == 0xF0 {
      // 4 字节：11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
      if i + 3 < end &&
        (at_byte(bytes, i + 1) & 0xC0) == 0x80 &&
        (at_byte(bytes, i + 2) & 0xC0) == 0x80 &&
        (at_byte(bytes, i + 3) & 0xC0) == 0x80 {
        let cp = ((b0 & 0x07) << 18) |
          ((at_byte(bytes, i + 1) & 0x3F) << 12) |
          ((at_byte(bytes, i + 2) & 0x3F) << 6) |
          (at_byte(bytes, i + 3) & 0x3F)
        if cp < 0x10000 || cp > 0x10FFFF {
          out.push('\u{FFFD}')
        } else {
          push_code_point(out, cp)
        }
        i = i + 4
      } else {
        out.push('\u{FFFD}')
        i = i + 1
      }
    } else {
      out.push('\u{FFFD}')
      i = i + 1
    }
  }
  String::from_iter(out.iter())
}

///|
/// 解码 UTF-8 字节区间；越界部分按实际长度截断。
pub fn decode_utf8(bytes : Bytes, start : Int32, len : Int32) -> String {
  let range = clamp_range(bytes, start, len)
  decode_utf8_range(bytes, range.0, range.1)
}

///|
/// 读一个 UTF-16 code unit（调用方保证 i+1 < end）。
fn utf16_unit(bytes : Bytes, i : Int32, big_endian : Bool) -> Int32 {
  if big_endian {
    (at_byte(bytes, i) << 8) | at_byte(bytes, i + 1)
  } else {
    (at_byte(bytes, i + 1) << 8) | at_byte(bytes, i)
  }
}

///|
/// UTF-16LE / UTF-16BE 解码，支持代理对。
/// 孤立代理、以及末尾凑不满一个 code unit 的字节都按 U+FFFD 处理。
pub fn decode_utf16(
  bytes : Bytes,
  start : Int32,
  len : Int32,
  big_endian : Bool,
) -> String {
  let range = clamp_range(bytes, start, len)
  let end = range.1
  let out : Array[Char] = []
  let mut i = range.0
  while i + 1 < end {
    let unit = utf16_unit(bytes, i, big_endian)
    if unit >= 0xD800 && unit <= 0xDBFF {
      // 高代理：后面必须紧跟低代理
      if i + 3 < end {
        let low = utf16_unit(bytes, i + 2, big_endian)
        if low >= 0xDC00 && low <= 0xDFFF {
          let cp = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
          push_code_point(out, cp)
          i = i + 4
        } else {
          out.push('\u{FFFD}')
          i = i + 2
        }
      } else {
        out.push('\u{FFFD}')
        i = i + 2
      }
    } else if unit >= 0xDC00 && unit <= 0xDFFF {
      out.push('\u{FFFD}')
      i = i + 2
    } else {
      push_code_point(out, unit)
      i = i + 2
    }
  }
  // 末尾不足一个 code unit 的 1 字节：SQLite 的文本长度总是偶数，这里直接忽略
  String::from_iter(out.iter())
}

///|
/// 按数据库编码解文本：1=UTF-8（默认）、2=UTF-16LE、3=UTF-16BE。
/// 未知编码按 UTF-8 处理。
pub fn decode_text(
  bytes : Bytes,
  start : Int32,
  len : Int32,
  encoding : Int32,
) -> String {
  if encoding == 2 {
    decode_utf16(bytes, start, len, false)
  } else if encoding == 3 {
    decode_utf16(bytes, start, len, true)
  } else {
    decode_utf8(bytes, start, len)
  }
}
