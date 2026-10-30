// 文件头测试：magic、page size（含 1 表示 65536）、编码、库版本。

///|
fn header_bytes(
  page_size_raw : Int32,
  encoding : Int32,
  version : Int32,
) -> Bytes {
  let out : Array[Byte] = []
  for c in b"SQLite format 3\x00" {
    out.push(c)
  }
  out.push((page_size_raw >> 8).to_byte())
  out.push((page_size_raw & 0xff).to_byte())
  while out.length() < 56 {
    out.push((0).to_byte())
  }
  out.push((encoding >> 24).to_byte())
  out.push(((encoding >> 16) & 0xff).to_byte())
  out.push(((encoding >> 8) & 0xff).to_byte())
  out.push((encoding & 0xff).to_byte())
  while out.length() < 96 {
    out.push((0).to_byte())
  }
  out.push((version >> 24).to_byte())
  out.push(((version >> 16) & 0xff).to_byte())
  out.push(((version >> 8) & 0xff).to_byte())
  out.push((version & 0xff).to_byte())
  while out.length() < 512 {
    out.push((0).to_byte())
  }
  Bytes::from_array(out[:])
}

///|
fn raises_on(bytes : Bytes) -> Bool {
  try {
    let _ = Database::open(bytes)
    false
  } catch {
    _ => true
  }
}

///|
test "open reads page size, encoding and library version" {
  let db = Database::open(header_bytes(4096, 1, 3053004))
  assert_eq(db.page_size(), 4096)
  assert_eq(db.encoding(), 1)
  assert_eq(db.encoding_label(), "UTF-8")
  assert_eq(db.sqlite_version(), 3053004)
}

///|
test "a page size field of 1 means 65536" {
  let db = Database::open(header_bytes(1, 2, 0))
  assert_eq(db.page_size(), 65536)
  assert_eq(db.encoding_label(), "UTF-16le")
}

///|
test "open rejects bad magic, short files, odd page sizes and bad encodings" {
  let good = header_bytes(4096, 1, 0)
  // 短文件
  assert_true(raises_on(b"SQLite format 3\x00"))
  // magic 被改
  let broken : Array[Byte] = []
  for c in good {
    broken.push(c)
  }
  broken[0] = 'X'.to_int().to_byte()
  assert_true(raises_on(Bytes::from_array(broken[:])))
  // 非 2 的幂
  assert_true(raises_on(header_bytes(1000, 1, 0)))
  // 非法编码
  assert_true(raises_on(header_bytes(4096, 0, 0)))
  assert_true(raises_on(header_bytes(4096, 4, 0)))
}

///|
test "encoding labels cover the three text encodings" {
  assert_eq(Database::open(header_bytes(4096, 1, 0)).encoding_label(), "UTF-8")
  assert_eq(
    Database::open(header_bytes(4096, 2, 0)).encoding_label(),
    "UTF-16le",
  )
  assert_eq(
    Database::open(header_bytes(4096, 3, 0)).encoding_label(),
    "UTF-16be",
  )
}
