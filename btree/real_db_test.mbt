// 真实 SQLite 文件的端到端校验。
//
// fixture 由 btree/testdata/make_fixtures.py 生成（Python 标准库 sqlite3，
// page_size 固定 512，保留字节 0），并提交进仓库。重新生成后如果根页或行数
// 变了，需要同步这里的常量。
//
// `moon test` 的工作目录是模块根，所以路径从 btree/testdata/ 开始。

///|
fn load_fixture(name : String) -> Bytes raise {
  @fs.read_file_to_bytes("btree/testdata/" + name)
}

///|
fn byte_at(bytes : Bytes, i : Int32) -> Int32 {
  if i >= 0 && i < bytes.length() {
    bytes[i].to_int()
  } else {
    -1
  }
}

///|
// 在 payload 里找一段长度 >= pairs*2 的 0xab,0xcd 交替字节。
// fixture 里的 blob 就是 b"\xab\xcd" * 600，用来确认溢出链拼出来的字节确实
// 是当初写进去的内容，而不只是长度对。
fn has_blob_run(bytes : Bytes, pairs : Int32) -> Bool {
  let n = bytes.length()
  let need = pairs * 2
  let mut start = 0
  while start + need <= n {
    if byte_at(bytes, start) == 0xab && byte_at(bytes, start + 1) == 0xcd {
      let mut i = 0
      let mut ok = true
      while ok && i < need {
        let want = if i % 2 == 0 { 0xab } else { 0xcd }
        if byte_at(bytes, start + i) != want {
          ok = false
        }
        i = i + 1
      }
      if ok {
        return true
      }
    }
    start = start + 1
  }
  false
}

///|
test "real fixture: interior root scans every rowid in order" {
  let page_size = 512
  let bytes = load_fixture("large_table.db")
  assert_eq(bytes.length(), 14848)
  // make_fixtures.py 生成：根页 2 是 interior table 页，14 个 cell，120 行。
  assert_eq(@btree.page_type(bytes, 2, page_size), 5)
  let recs = @btree.scan_table(bytes, page_size, 2)
  assert_eq(recs.length(), 120)
  let mut prev = 0L
  for i in 0..<recs.length() {
    assert_eq(recs[i].0, (i + 1).to_int64())
    assert_true(recs[i].0 > prev)
    prev = recs[i].0
    let payload = @btree.read_payload(bytes, page_size, recs[i].1, recs[i].2)
    assert_eq(payload.length(), recs[i].2)
  }
}

///|
test "real fixture: overflow payloads keep their bytes" {
  let page_size = 512
  let bytes = load_fixture("large_table.db")
  let recs = @btree.scan_table(bytes, page_size, 2)
  // 第 20/40/60/80/100/120 行带 1200 字节 blob，payload 必然跨页。
  let mut big = 0
  for i in 0..<recs.length() {
    if recs[i].2 > page_size {
      big = big + 1
      let payload = @btree.read_payload(bytes, page_size, recs[i].1, recs[i].2)
      assert_eq(payload.length(), recs[i].2)
      assert_true(has_blob_run(payload, 600))
    }
  }
  assert_eq(big, 6)
}

///|
test "real fixture: a table that fits in one leaf page" {
  let page_size = 512
  let bytes = load_fixture("single_page.db")
  assert_eq(@btree.page_type(bytes, 2, page_size), 13)
  let recs = @btree.scan_table(bytes, page_size, 2)
  assert_eq(recs.length(), 3)
  for i in 0..<recs.length() {
    assert_eq(recs[i].0, (i + 1).to_int64())
    assert_eq(
      @btree.read_payload(bytes, page_size, recs[i].1, recs[i].2).length(),
      recs[i].2,
    )
  }
}

///|
test "real fixture: WITHOUT ROWID lives in an index btree" {
  let page_size = 512
  let bytes = load_fixture("without_rowid.db")
  // 索引 b-tree 的叶页类型是 10，不是表 b-tree 的 13。
  assert_eq(@btree.page_type(bytes, 2, page_size), 10)
  // 表遍历只处理表 b-tree，遇到索引 b-tree 必须返回空而不是垃圾。
  assert_eq(@btree.scan_table(bytes, page_size, 2).length(), 0)
  // 索引入口能读到 5 行，每行 payload 都能完整读回。
  let recs = @btree.scan_index_leaves(bytes, page_size, 2)
  assert_eq(recs.length(), 5)
  for i in 0..<recs.length() {
    assert_true(recs[i].1 > 0)
    let payload = @btree.read_index_payload(
      bytes,
      page_size,
      recs[i].0,
      recs[i].1,
    )
    assert_eq(payload.length(), recs[i].1)
  }
}
