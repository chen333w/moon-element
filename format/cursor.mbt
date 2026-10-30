// 大端读取原语。SQLite 文件格式整篇是大端，唯一例外是 schema cookie 之类的杂项。

///|
pub fn be_u16(bytes : Bytes, at : Int32) -> Int32 {
  (bytes[at].to_int() << 8) | bytes[at + 1].to_int()
}

///|
pub fn be_u32(bytes : Bytes, at : Int32) -> UInt32 {
  (bytes[at].to_uint() << 24) |
  (bytes[at + 1].to_uint() << 16) |
  (bytes[at + 2].to_uint() << 8) |
  bytes[at + 3].to_uint()
}

///|
pub fn be_i32(bytes : Bytes, at : Int32) -> Int32 {
  be_u32(bytes, at).reinterpret_as_int()
}

///|
pub fn be_i64(bytes : Bytes, at : Int32) -> Int64 {
  let mut v : Int64 = 0L
  for i in 0..<8 {
    v = (v << 8) | bytes[at + i].to_int64()
  }
  v
}

///|
/// SQLite 的 varint：1~9 字节，大端，第 9 字节固定占 8 位。
/// 返回 (值, 消耗的字节数)。
pub fn varint(bytes : Bytes, at : Int32) -> (Int64, Int32) {
  let mut v : Int64 = 0L
  let mut i = 0
  while i < 8 {
    let b = bytes[at + i].to_int()
    v = (v << 7) | (b & 0x7f).to_int64()
    i = i + 1
    if (b & 0x80) == 0 {
      return (v, i)
    }
  }
  let last = bytes[at + 8].to_int()
  ((v << 8) | last.to_int64(), 9)
}
