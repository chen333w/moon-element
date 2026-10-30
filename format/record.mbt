// record 解码：头部是「头长度 + 每列 serial type」，数据区紧随头部之后。
// 格式见 https://www.sqlite.org/fileformat2.html#record_format
//
// 容错规则（上层可通过 RecordResult.malformed 识别）：
// 1. 偏移非法、头长度 varint 读不出、头长度 < 自身 varint 长度、头长度越过 buffer
//    → 整条记录视为畸形，返回 ncols 个 Null。
// 2. 头部的 serial type 读到一半越界 → 已读到的列照常解，其余列保持 Null。
// 3. 数据区剩余字节不够某列 → 该列及其后所有列保持 Null。
// 4. 保留类型 10/11、负 serial（varint 实际不会产生）、超大长度 → 该列 Null 并停止。
// 无论如何返回的数组长度都等于 ncols（ncols 为负时返回空数组）。

///|
/// serial type 对应的数据形状。
priv enum Shape {
  SNull
  /// 1/2/3/4/6/8 字节的大端有符号整数
  SInteger(Int)
  SZero
  SOne
  SReal
  /// 数据区字节数
  SBlob(Int)
  SText(Int)
  /// 10/11：SQLite 内部保留，长度未知，无法继续
  SReserved
  SInvalid
}

///|
/// 记录解码结果。malformed 为 true 时 values 是能解出的前缀，其余为 Null。
pub(all) struct RecordResult {
  values : Array[Value]
  malformed : Bool
}

///|
/// 区间是否完整落在 buffer 内（用 Int64 相加，避免接近上限时溢出）。
fn fits(bytes : Bytes, at : Int, n : Int) -> Bool {
  at >= 0 && n >= 0 && at.to_int64() + n.to_int64() <= bytes.length().to_int64()
}

///|
/// 带边界检查的 varint，语义与 cursor.mbt 的 varint 一致，只是越界返回 None。
fn read_varint(bytes : Bytes, at : Int, limit : Int) -> (Int64, Int)? {
  if at < 0 || at >= limit {
    return None
  }
  let mut v : Int64 = 0L
  let mut i = 0
  while i < 8 {
    if at + i >= limit {
      return None
    }
    let b = at_byte(bytes, at + i)
    v = (v << 7) | (b & 0x7f).to_int64()
    i = i + 1
    if (b & 0x80) == 0 {
      return Some((v, i))
    }
  }
  if at + 8 >= limit {
    return None
  }
  let last = at_byte(bytes, at + 8)
  Some(((v << 8) | last.to_int64(), 9))
}

///|
/// 大端有符号整数：n ∈ [1,8]，按最高位做符号扩展。
fn read_be_int(bytes : Bytes, at : Int, n : Int) -> Int64? {
  if n <= 0 || n > 8 || !fits(bytes, at, n) {
    return None
  }
  let mut v : Int64 = 0L
  let mut i = 0
  while i < n {
    v = (v << 8) | at_byte(bytes, at + i).to_int64()
    i = i + 1
  }
  if n < 8 {
    // 先左移把符号位顶到最高位，再算术右移回来
    let shift = (8 - n) * 8
    v = (v << shift) >> shift
  }
  Some(v)
}

///|
/// serial type 7：IEEE754 大端 double。
fn read_be_double(bytes : Bytes, at : Int) -> Double? {
  match read_be_int(bytes, at, 8) {
    Some(bits) => Some(bits.reinterpret_as_double())
    None => None
  }
}

///|
fn slice_bytes(bytes : Bytes, at : Int, n : Int) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < n {
    out.push(bytes[at + i])
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
/// serial type → 形状（官方文档 §2.1 Serial Type Codes）。
fn shape_of(serial : Int64) -> Shape {
  if serial < 0L {
    return SInvalid
  }
  if serial == 0L {
    return SNull
  }
  if serial >= 1L && serial <= 6L {
    let width = match serial {
      1L => 1
      2L => 2
      3L => 3
      4L => 4
      5L => 6
      _ => 8
    }
    return SInteger(width)
  }
  if serial == 7L {
    return SReal
  }
  if serial == 8L {
    return SZero
  }
  if serial == 9L {
    return SOne
  }
  if serial == 10L || serial == 11L {
    return SReserved
  }
  // 12 起：偶数 blob、奇数 text
  if serial % 2L == 0L {
    let n = (serial - 12L) / 2L
    if n > 2147483647L {
      SInvalid
    } else {
      SBlob(n.to_int())
    }
  } else {
    let n = (serial - 13L) / 2L
    if n > 2147483647L {
      SInvalid
    } else {
      SText(n.to_int())
    }
  }
}

///|
/// 读 record，文本按给定数据库编码解（1=UTF-8、2=UTF-16LE、3=UTF-16BE）。
pub fn decode_record_with_encoding(
  bytes : Bytes,
  offset : Int,
  ncols : Int,
  encoding : Int,
) -> RecordResult {
  let total = if ncols < 0 { 0 } else { ncols }
  let values : Array[Value] = []
  let mut k = 0
  while k < total {
    values.push(Null)
    k = k + 1
  }
  if total == 0 {
    return { values, malformed: false }
  }
  let len = bytes.length()
  // 头长度：varint，包含它自身的字节
  let head = match read_varint(bytes, offset, len) {
    None => return { values, malformed: true }
    Some(p) => p
  }
  let hdr_size = head.0
  let size_width = head.1
  if hdr_size < 1L ||
    hdr_size < size_width.to_int64() ||
    offset.to_int64() + hdr_size > len.to_int64() {
    return { values, malformed: true }
  }
  let hdr_end = offset + hdr_size.to_int()
  // 每列一个 serial type；记录里的列数可能少于 ncols（尾部列省略）
  let serials : Array[Int64] = []
  let mut pos = offset + size_width
  let mut malformed = false
  while pos < hdr_end && serials.length() < total {
    match read_varint(bytes, pos, hdr_end) {
      None => {
        malformed = true
        // 头部里 varint 越界：结束循环
        pos = hdr_end
      }
      Some(p) => {
        serials.push(p.0)
        pos = pos + p.1
      }
    }
  }
  // 数据区从头部末尾开始；列数多于 ncols 时多出来的被忽略
  let mut data = hdr_end
  let mut i = 0
  while i < serials.length() && !malformed {
    match shape_of(serials[i]) {
      SNull => ()
      SZero => values[i] = Int(0L)
      SOne => values[i] = Int(1L)
      SInteger(width) =>
        match read_be_int(bytes, data, width) {
          Some(v) => {
            values[i] = Int(v)
            data = data + width
          }
          None => malformed = true
        }
      SReal =>
        match read_be_double(bytes, data) {
          Some(d) => {
            values[i] = Real(d)
            data = data + 8
          }
          None => malformed = true
        }
      SBlob(n) =>
        if fits(bytes, data, n) {
          values[i] = Blob(slice_bytes(bytes, data, n))
          data = data + n
        } else {
          malformed = true
        }
      SText(n) =>
        if fits(bytes, data, n) {
          values[i] = Text(decode_text(bytes, data, n, encoding))
          data = data + n
        } else {
          malformed = true
        }
      SReserved => malformed = true
      SInvalid => malformed = true
    }
    i = i + 1
  }
  { values, malformed }
}

///|
/// 读 record，文本按 UTF-8 解（SQLite 默认编码）。
/// 返回值长度固定为 ncols：缺的列补 Null，畸形输入见文件头注释的容错规则。
pub fn decode_record(bytes : Bytes, offset : Int, ncols : Int) -> Array[Value] {
  decode_record_with_encoding(bytes, offset, ncols, 1).values
}