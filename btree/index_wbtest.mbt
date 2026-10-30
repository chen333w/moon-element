// 索引 b-tree 叶扫描的测试（WITHOUT ROWID 表的数据走这条路径）。

///|
test "scan a single leaf index page" {
  let p0 = make_payload(11, 4)
  let p1 = make_payload(12, 6)
  let page = make_page(
    512,
    10,
    [index_leaf_cell(p0), index_leaf_cell(p1)],
    0,
    true,
  )
  let bytes = concat([page])
  let recs = scan_index_leaves(bytes, 512, 1)
  assert_eq(recs.length(), 2)
  assert_eq(recs[0].1, 4)
  assert_eq(recs[1].1, 6)
  assert_true(
    bytes_eq(read_index_payload(bytes, 512, recs[0].0, recs[0].1), p0),
  )
  assert_true(
    bytes_eq(read_index_payload(bytes, 512, recs[1].0, recs[1].1), p1),
  )
}

///|
test "interior index page only contributes its children" {
  let leaf2 = make_page(
    512,
    10,
    [index_leaf_cell(make_payload(21, 3))],
    0,
    false,
  )
  let leaf3 = make_page(
    512,
    10,
    [index_leaf_cell(make_payload(22, 3))],
    0,
    false,
  )
  // interior index cell 自己带 payload（分隔键），全叶扫描必须忽略它。
  let root = make_page(
    512,
    2,
    [index_interior_cell(2, make_payload(99, 5))],
    3,
    true,
  )
  let bytes = concat([root, leaf2, leaf3])
  let recs = scan_index_leaves(bytes, 512, 1)
  assert_eq(recs.length(), 2)
  assert_eq(recs[0].1, 3)
  assert_eq(recs[1].1, 3)
  assert_true(
    bytes_eq(
      read_index_payload(bytes, 512, recs[0].0, recs[0].1),
      make_payload(21, 3),
    ),
  )
  assert_true(
    bytes_eq(
      read_index_payload(bytes, 512, recs[1].0, recs[1].1),
      make_payload(22, 3),
    ),
  )
}

///|
test "index leaf overflow uses the index local payload rule" {
  let page_size = 512
  let total = 1245
  let payload = make_payload(31, total)
  // 两种页类的本地长度在这里必须不同：表叶规则给 K=229，索引页规则给 M=39。
  let table_local = expected_local(page_size, total)
  let index_local = expected_local_index(page_size, total)
  assert_eq(table_local, 229)
  assert_eq(index_local, 39)
  let local_bytes : Array[Byte] = []
  for i in 0..<index_local {
    local_bytes.push(payload[i])
  }
  let chunk = page_size - 4
  let leaf = make_page(
    page_size,
    10,
    [index_leaf_cell_overflow(total, local_bytes, 3)],
    0,
    false,
  )
  let mut rest = total - index_local
  let mut offset = index_local
  let overflow : Array[Array[Byte]] = []
  let mut next_page = 3
  while rest > 0 {
    let ov = buf_new(page_size)
    let take = if rest > chunk { chunk } else { rest }
    let after = if rest > chunk { next_page + 1 } else { 0 }
    put_u32(ov, 0, after)
    let mut i = 0
    while i < take {
      ov.data[4 + i] = payload[offset + i]
      i = i + 1
    }
    overflow.push(ov.data)
    rest = rest - take
    offset = offset + take
    next_page = next_page + 1
  }
  let pages : Array[Cell] = [buf_new(page_size).data, leaf]
  for p in overflow {
    pages.push(p)
  }
  let bytes = concat(pages)
  let recs = scan_index_leaves(bytes, page_size, 2)
  assert_eq(recs.length(), 1)
  assert_eq(recs[0].1, total)
  let got = read_index_payload(bytes, page_size, recs[0].0, recs[0].1)
  assert_eq(got.length(), total)
  assert_true(bytes_eq(got, payload))
}

///|
test "index scan ignores table btree pages and bad roots" {
  let table_leaf = concat([
    make_page(512, 13, [leaf_cell(1, make_payload(1, 2))], 0, true),
  ])
  assert_eq(scan_index_leaves(table_leaf, 512, 1).length(), 0)
  let index_leaf = concat([
    make_page(512, 10, [index_leaf_cell(make_payload(1, 2))], 0, true),
  ])
  assert_eq(scan_index_leaves(index_leaf, 512, 9).length(), 0)
  assert_eq(scan_index_leaves(index_leaf, 512, 0).length(), 0)
  let empty : Array[Byte] = []
  assert_eq(scan_index_leaves(Bytes::from_array(empty[:]), 512, 1).length(), 0)
}
