// format 包的黑盒测试：serial type 逐项断言、记录结构、UTF-8/16 编解码、畸形输入与随机字节。

// ---------------------------------------------------------------- 构造字节的小工具

///|
/// 把 0~255 的整数列表拼成 Bytes。
fn bytes_of(list : Array[Int]) -> Bytes {
  let out : Array[Byte] = []
  for v in list {
    out.push(v.to_byte())
  }
  Bytes::from_array(out)
}

///|
/// 编码 varint（1~8 字节，测试用到的值都小于 2^56）。
fn encode_varint(v : Int64) -> Array[Byte] {
  if v < 128L {
    return [v.to_int().to_byte()]
  }
  // 先按 7 位一组从低到高收集，再反向输出
  let groups : Array[Int] = []
  let mut rest = v
  while rest >= 128L {
    groups.push((rest & 0x7FL).to_int())
    rest = rest >> 7
  }
  groups.push(rest.to_int())
  let out : Array[Byte] = []
  let mut i = groups.length() - 1
  while i >= 0 {
    if i == 0 {
      out.push(groups[i].to_byte())
    } else {
      out.push((groups[i] | 0x80).to_byte())
    }
    i = i - 1
  }
  out
}

///|
/// 拼一条 record：头长度 varint + 每列 serial type + 数据区。
fn build_record(serials : Array[Int64], data : Array[Int]) -> Bytes {
  let serial_bytes : Array[Byte] = []
  for s in serials {
    for b in encode_varint(s) {
      serial_bytes.push(b)
    }
  }
  // 头长度包含自身的 varint，先按 1 字节估，超过 127 再加宽
  let mut width = 1
  if serial_bytes.length() + 1 > 127 {
    width = 2
  }
  let hdr_len = serial_bytes.length() + width
  let out : Array[Byte] = []
  for b in encode_varint(hdr_len.to_int64()) {
    out.push(b)
  }
  for b in serial_bytes {
    out.push(b)
  }
  for v in data {
    out.push(v.to_byte())
  }
  Bytes::from_array(out)
}

// ---------------------------------------------------------------- 断言工具
// Value 没有 derive(Eq)/Debug，所以逐形态断言；类型不符时用 type_name 给出可读失败信息。

///|
fn expect_null(v : @format.Value) -> Unit raise {
  assert_eq(v.type_name(), "null")
}

///|
fn expect_int(v : @format.Value, want : Int64) -> Unit raise {
  match v {
    @format.Int(got) => assert_eq(got, want)
    _ => assert_eq(v.type_name(), "integer")
  }
}

///|
fn expect_real(v : @format.Value, want : Double) -> Unit raise {
  match v {
    @format.Real(got) => assert_true(got.is_close(want))
    _ => assert_eq(v.type_name(), "real")
  }
}

///|
fn expect_text(v : @format.Value, want : String) -> Unit raise {
  match v {
    @format.Text(got) => assert_eq(got, want)
    _ => assert_eq(v.type_name(), "text")
  }
}

///|
fn expect_blob(v : @format.Value, want : Array[Int]) -> Unit raise {
  match v {
    @format.Blob(got) => {
      assert_eq(got.length(), want.length())
      let mut i = 0
      while i < want.length() {
        assert_eq(got[i].to_int(), want[i])
        i = i + 1
      }
    }
    _ => assert_eq(v.type_name(), "blob")
  }
}

///|
/// 把 record 解成 ncols 列；顺带断言长度与「不是畸形」。
fn decode_ok(bytes : Bytes, ncols : Int) -> Array[@format.Value] raise {
  let res = @format.decode_record_with_encoding(bytes, 0, ncols, 1)
  assert_false(res.malformed)
  assert_eq(res.values.length(), ncols)
  res.values
}

// ---------------------------------------------------------------- serial type：逐项

///|
test "serial type: null and the two constant integers" {
  // 0 = NULL，8 = 整数 0，9 = 整数 1；三者都不占数据区
  let bytes = build_record([0L, 8L, 9L], [])
  let vals = decode_ok(bytes, 3)
  expect_null(vals[0])
  expect_int(vals[1], 0L)
  expect_int(vals[2], 1L)
}

///|
test "serial type: 1 byte integer is sign extended" {
  let pos = decode_ok(build_record([1L], [0x7F]), 1)
  expect_int(pos[0], 127L)
  let neg = decode_ok(build_record([1L], [0xFF]), 1)
  expect_int(neg[0], -1L)
  let min = decode_ok(build_record([1L], [0x80]), 1)
  expect_int(min[0], -128L)
}

///|
test "serial type: 2 byte integer" {
  let vals = decode_ok(build_record([2L], [0x80, 0x00]), 1)
  expect_int(vals[0], -32768L)
  let vals2 = decode_ok(build_record([2L], [0x12, 0x34]), 1)
  expect_int(vals2[0], 0x1234L)
}

///|
test "serial type: 3 byte integer" {
  let vals = decode_ok(build_record([3L], [0xFF, 0xFF, 0x80]), 1)
  expect_int(vals[0], -128L)
  let vals2 = decode_ok(build_record([3L], [0x00, 0x00, 0x7F]), 1)
  expect_int(vals2[0], 127L)
}

///|
test "serial type: 4 byte integer" {
  let vals = decode_ok(build_record([4L], [0xFF, 0xFF, 0xFF, 0xFF]), 1)
  expect_int(vals[0], -1L)
  let vals2 = decode_ok(build_record([4L], [0x7F, 0xFF, 0xFF, 0xFF]), 1)
  expect_int(vals2[0], 2147483647L)
}

///|
test "serial type: 6 byte integer" {
  // 0x010203040506 = 1108152157446
  let vals = decode_ok(build_record([5L], [1, 2, 3, 4, 5, 6]), 1)
  expect_int(vals[0], 1108152157446L)
  // 6 个 0xFF 是 -1
  let neg = decode_ok(build_record([5L], [255, 255, 255, 255, 255, 255]), 1)
  expect_int(neg[0], -1L)
}

///|
test "serial type: 8 byte integer" {
  let max = decode_ok(build_record([6L], [
    0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
  ]), 1)
  expect_int(max[0], 9223372036854775807L)
  let neg = decode_ok(build_record([6L], [
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
  ]), 1)
  expect_int(neg[0], -1L)
  // -2^40
  let big = decode_ok(build_record([6L], [
    0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]), 1)
  expect_int(big[0], -1099511627776L)
}

///|
test "serial type: 7 is a big-endian double" {
  // 1.5 = 0x3FF8000000000000
  let vals = decode_ok(build_record([7L], [0x3F, 0xF8, 0, 0, 0, 0, 0, 0]), 1)
  expect_real(vals[0], 1.5)
  // -2.0 = 0xC000000000000000
  let neg = decode_ok(build_record([7L], [0xC0, 0, 0, 0, 0, 0, 0, 0]), 1)
  expect_real(neg[0], -2.0)
  // +0.0
  let zero = decode_ok(build_record([7L], [0, 0, 0, 0, 0, 0, 0, 0]), 1)
  expect_real(zero[0], 0.0)
}

///|
test "serial type: empty text and empty blob" {
  // 12 = blob(0)，13 = text(0)
  let vals = decode_ok(build_record([12L, 13L], []), 2)
  expect_blob(vals[0], [])
  expect_text(vals[1], "")
}

///|
test "serial type: 1 byte blob and 1 byte text" {
  // 14 = blob(1)，15 = text(1)
  let vals = decode_ok(build_record([14L, 15L], [0xAB, 0x41]), 2)
  expect_blob(vals[0], [0xAB])
  expect_text(vals[1], "A")
}

///|
test "serial type: blob length uses a multi-byte varint" {
  // 100 字节 blob → serial = 12 + 200 = 212，varint 占 2 字节
  let data : Array[Int] = []
  let mut i = 0
  while i < 100 {
    data.push(i)
    i = i + 1
  }
  let vals = decode_ok(build_record([212L], data), 1)
  let expected : Array[Int] = []
  let mut k = 0
  while k < 100 {
    expected.push(k)
    k = k + 1
  }
  expect_blob(vals[0], expected)
}

///|
test "serial type: mixed record keeps values in column order" {
  let bytes = build_record([1L, 13L, 7L, 12L, 0L], [
    0x2A, 0x3F, 0xF0, 0, 0, 0, 0, 0, 0,
  ])
  let vals = decode_ok(bytes, 5)
  expect_int(vals[0], 42L)
  expect_text(vals[1], "")
  expect_real(vals[2], 1.0)
  expect_blob(vals[3], [])
  expect_null(vals[4])
}

// ---------------------------------------------------------------- 记录结构

///|
test "record: missing trailing columns are filled with null" {
  // 记录只有 1 列，表定义 3 列
  let bytes = build_record([1L], [0x05])
  let vals = decode_ok(bytes, 3)
  expect_int(vals[0], 5L)
  expect_null(vals[1])
  expect_null(vals[2])
}

///|
test "record: extra columns are truncated to ncols" {
  // 记录有 3 列，只要求 2 列
  let bytes = build_record([1L, 2L, 3L], [0x01, 0x00, 0x02, 0x00, 0x00, 0x03])
  let vals = decode_ok(bytes, 2)
  assert_eq(vals.length(), 2)
  expect_int(vals[0], 1L)
  expect_int(vals[1], 2L)
}

///|
test "record: gold bytes of a two column record" {
  // 手写字节：头长度 3，serial 1（整数）、15（text 1 字节），数据 01 41
  let bytes = bytes_of([0x03, 0x01, 0x0F, 0x01, 0x41])
  let vals = decode_ok(bytes, 2)
  expect_int(vals[0], 1L)
  expect_text(vals[1], "A")
  // 同一份字节，列数多要两列 → 尾部补 Null
  let wider = decode_ok(bytes, 4)
  assert_eq(wider.length(), 4)
  expect_null(wider[2])
  expect_null(wider[3])
}

///|
test "record: offset in the middle of a buffer" {
  let record = bytes_of([0x03, 0x01, 0x0F, 0x01, 0x41])
  let prefix = bytes_of([0xAA, 0xBB])
  // 手工拼：前缀 + record
  let merged : Array[Byte] = []
  for b in prefix {
    merged.push(b)
  }
  for b in record {
    merged.push(b)
  }
  let bytes = Bytes::from_array(merged)
  let res = @format.decode_record_with_encoding(bytes, 2, 2, 1)
  assert_false(res.malformed)
  expect_int(res.values[0], 1L)
  expect_text(res.values[1], "A")
}

///|
test "record: zero columns returns empty array" {
  let bytes = build_record([1L], [0x01])
  assert_eq(@format.decode_record(bytes, 0, 0).length(), 0)
  // 负数按 0 处理
  assert_eq(@format.decode_record(bytes, 0, -3).length(), 0)
}

// ---------------------------------------------------------------- 文本编码

///|
test "utf8: multibyte text decodes inside a record" {
  // "héllo" = 68 C3 A9 6C 6C 6F，6 字节 → serial 25
  let vals = decode_ok(build_record([25L], [0x68, 0xC3, 0xA9, 0x6C, 0x6C, 0x6F]), 1)
  expect_text(vals[0], "héllo")
  // "中文" = E4 B8 AD E6 96 87
  let cjk = decode_ok(build_record([25L], [0xE4, 0xB8, 0xAD, 0xE6, 0x96, 0x87]), 1)
  expect_text(cjk[0], "中文")
  // 四字节 emoji 😀 = F0 9F 98 80 → serial 21
  let emoji = decode_ok(build_record([21L], [0xF0, 0x9F, 0x98, 0x80]), 1)
  expect_text(emoji[0], "😀")
}

///|
test "utf8: invalid bytes become replacement characters and never panic" {
  // 孤立续字节
  assert_eq(@format.decode_utf8(bytes_of([0x80]), 0, 1), "\u{FFFD}")
  // 截断的 3 字节序列
  assert_eq(@format.decode_utf8(bytes_of([0xE4, 0xB8]), 0, 2), "\u{FFFD}\u{FFFD}")
  // 非法起始字节
  assert_eq(@format.decode_utf8(bytes_of([0xFF]), 0, 1), "\u{FFFD}")
  // 过长编码 C0 80
  assert_eq(@format.decode_utf8(bytes_of([0xC0, 0x80]), 0, 2), "\u{FFFD}")
  // 代理区的三字节编码 ED A0 80
  assert_eq(@format.decode_utf8(bytes_of([0xED, 0xA0, 0x80]), 0, 3), "\u{FFFD}")
  // 空区间
  assert_eq(@format.decode_utf8(bytes_of([0x41]), 0, 0), "")
}

///|
test "utf16: little and big endian, ascii and surrogate pairs" {
  // LE "AB" = 41 00 42 00
  assert_eq(@format.decode_utf16(bytes_of([0x41, 0, 0x42, 0]), 0, 4, false), "AB")
  // BE "AB" = 00 41 00 42
  assert_eq(@format.decode_utf16(bytes_of([0, 0x41, 0, 0x42]), 0, 4, true), "AB")
  // 😀 U+1F600 = 代理对 D83D DE00；LE
  assert_eq(
    @format.decode_utf16(bytes_of([0x3D, 0xD8, 0x00, 0xDE]), 0, 4, false),
    "😀",
  )
  // 同一字符 BE
  assert_eq(
    @format.decode_utf16(bytes_of([0xD8, 0x3D, 0xDE, 0x00]), 0, 4, true),
    "😀",
  )
  // 空串
  assert_eq(@format.decode_utf16(bytes_of([]), 0, 0, false), "")
  // 中文 "中" = 4E2D
  assert_eq(@format.decode_utf16(bytes_of([0x2D, 0x4E]), 0, 2, false), "中")
}

///|
test "utf16: lone surrogates and odd tails become replacement characters" {
  // 孤立高代理
  assert_eq(@format.decode_utf16(bytes_of([0x3D, 0xD8]), 0, 2, false), "\u{FFFD}")
  // 孤立低代理
  assert_eq(@format.decode_utf16(bytes_of([0x00, 0xDE]), 0, 2, false), "\u{FFFD}")
  // 高代理后面不是低代理
  assert_eq(
    @format.decode_utf16(bytes_of([0x3D, 0xD8, 0x41, 0x00]), 0, 4, false),
    "\u{FFFD}A",
  )
  // 末尾半个 code unit 被忽略
  assert_eq(@format.decode_utf16(bytes_of([0x41, 0, 0x42]), 0, 3, false), "A")
}

///|
test "utf16: out of range ranges are clamped without panic" {
  let bytes = bytes_of([0x41, 0, 0x42, 0])
  assert_eq(@format.decode_utf16(bytes, -5, 4, false), "AB")
  assert_eq(@format.decode_utf16(bytes, 2, 100, false), "B")
  assert_eq(@format.decode_utf16(bytes, 10, 4, false), "")
  assert_eq(@format.decode_utf16(bytes, 0, -1, false), "")
}

///|
test "record: text column follows the database encoding" {
  // 41 00 42 00：UTF-8 下是 "A\0B\0"，UTF-16LE 下是 "AB"
  let bytes = build_record([21L], [0x41, 0x00, 0x42, 0x00])
  let le = @format.decode_record_with_encoding(bytes, 0, 1, 2)
  assert_false(le.malformed)
  expect_text(le.values[0], "AB")
  let be = @format.decode_record_with_encoding(
    build_record([21L], [0x00, 0x41, 0x00, 0x42]), 0, 1, 3,
  )
  assert_false(be.malformed)
  expect_text(be.values[0], "AB")
  // 未知编码按 UTF-8 处理
  let unknown = @format.decode_record_with_encoding(bytes, 0, 1, 9)
  assert_false(unknown.malformed)
  match unknown.values[0] {
    @format.Text(s) => assert_eq(s.char_length(), 4)
    _ => assert_eq(unknown.values[0].type_name(), "text")
  }
}

// ---------------------------------------------------------------- 畸形输入

///|
test "malformed: bad header or offset returns ncols nulls without panic" {
  let cases : Array[Bytes] = [
    bytes_of([]), // 空 buffer
    bytes_of([0x00]), // 头长度 0
    bytes_of([0x80]), // 头 varint 被截断
    bytes_of([0x05, 0x01]), // 头长度 5 但 buffer 只有 2 字节
    bytes_of([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]), // 9 字节头长度
    bytes_of([0x03, 0x01]), // 头部声明 3 字节但 serial 缺一个
  ]
  for bytes in cases {
    let res = @format.decode_record_with_encoding(bytes, 0, 3, 1)
    assert_true(res.malformed)
    assert_eq(res.values.length(), 3)
    expect_null(res.values[0])
    expect_null(res.values[1])
    expect_null(res.values[2])
  }
  // offset 越界
  let res = @format.decode_record_with_encoding(bytes_of([0x03, 0x01, 0x0F]), 5, 2, 1)
  assert_true(res.malformed)
  assert_eq(res.values.length(), 2)
}

///|
test "malformed: reserved and oversized serial types stop decoding" {
  // 10 / 11 是保留类型，长度未知
  for serial in [10L, 11L] {
    let res = @format.decode_record_with_encoding(
      build_record([1L, serial], [0x01]), 0, 2, 1,
    )
    assert_true(res.malformed)
    assert_eq(res.values.length(), 2)
    expect_int(res.values[0], 1L)
    expect_null(res.values[1])
  }
  // 超大 serial：长度超过 Int 可表示范围
  let huge = @format.decode_record_with_encoding(
    build_record([6000000012L], []), 0, 1, 1,
  )
  assert_true(huge.malformed)
  assert_eq(huge.values.length(), 1)
  expect_null(huge.values[0])
}

///|
test "malformed: truncated data area leaves the rest null" {
  // serial 6 需要 8 字节，只给 2 字节
  let res = @format.decode_record_with_encoding(
    build_record([6L, 1L], [0x01, 0x02]), 0, 2, 1,
  )
  assert_true(res.malformed)
  assert_eq(res.values.length(), 2)
  expect_null(res.values[0])
  expect_null(res.values[1])
  // 前几列已经解出，后面的列才缺
  let partial = @format.decode_record_with_encoding(
    build_record([1L, 14L, 9L], [0x07, 0xAB]), 0, 3, 1,
  )
  assert_false(partial.malformed)
  expect_int(partial.values[0], 7L)
  expect_blob(partial.values[1], [0xAB])
  expect_int(partial.values[2], 1L)
}

// ---------------------------------------------------------------- 随机输入

///|
/// 线性同余，参数固定，失败可复现；乘数取得小，避免 32 位溢出。
fn next_rand(seed : Int) -> Int {
  (seed * 75 + 74) % 65537
}

///|
test "fuzz: 500 random buffers never panic and keep length equal to ncols" {
  let mut seed : Int = 20261030
  let mut round = 0
  while round < 500 {
    seed = next_rand(seed)
    if seed < 0 {
      seed = -seed
    }
    let n = seed % 64
    let buf : Array[Byte] = []
    let mut k = 0
    while k < n {
      seed = next_rand(seed)
      if seed < 0 {
        seed = -seed
      }
      buf.push((seed % 256).to_byte())
      k = k + 1
    }
    let bytes = Bytes::from_array(buf)
    let ncols = seed % 6
    let offset = seed % (n + 4)
    // 公开 API 三后端都一样：不 panic、长度恒为 ncols
    let vals = @format.decode_record(bytes, offset, ncols)
    assert_eq(vals.length(), ncols)
    let encoded = @format.decode_record_with_encoding(
      bytes, offset, ncols, 1 + seed % 3,
    )
    assert_eq(encoded.values.length(), ncols)
    // 文本解码同样不能 panic
    ignore(@format.decode_utf8(bytes, offset, seed % 32))
    ignore(@format.decode_utf16(bytes, offset, seed % 32, seed % 2 == 0))
    round = round + 1
  }
}