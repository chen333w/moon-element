// 表 b-tree 遍历、溢出页与防御性读取的测试。

///|
test "scan a single leaf page" {
  let p0 = make_payload(1, 7)
  let p1 = make_payload(2, 4)
  let page = make_page(512, 13, [leaf_cell(1, p0), leaf_cell(2, p1)], 0, true)
  let bytes = concat([page])
  let recs = scan_table(bytes, 512, 1)
  assert_eq(recs.length(), 2)
  assert_eq(recs[0].0, 1L)
  assert_eq(recs[1].0, 2L)
  assert_eq(recs[0].2, 7)
  assert_eq(recs[1].2, 4)
  assert_true(bytes_eq(read_payload(bytes, 512, recs[0].1, recs[0].2), p0))
  assert_true(bytes_eq(read_payload(bytes, 512, recs[1].1, recs[1].2), p1))
}

///|
test "interior page visits children in key order" {
  let leaf2 = make_page(
    512,
    13,
    [leaf_cell(1, make_payload(1, 3)), leaf_cell(2, make_payload(2, 3))],
    0,
    false,
  )
  let leaf3 = make_page(
    512,
    13,
    [leaf_cell(10, make_payload(3, 3)), leaf_cell(11, make_payload(4, 3))],
    0,
    false,
  )
  // 根页 1：一个 interior cell（左孩子 2，分隔 rowid 5），最右孩子 3。
  let root = make_page(512, 5, [interior_cell(2, 5)], 3, true)
  let bytes = concat([root, leaf2, leaf3])
  let recs = scan_table(bytes, 512, 1)
  assert_eq(recs.length(), 4)
  assert_eq(recs[0].0, 1L)
  assert_eq(recs[1].0, 2L)
  assert_eq(recs[2].0, 10L)
  assert_eq(recs[3].0, 11L)
  // interior 页自己的分隔 rowid 不是记录
  assert_true(recs[0].0 != 5L && recs[1].0 != 5L && recs[2].0 != 5L)
}

///|
test "overflow chain rebuilds a payload larger than a page" {
  let page_size = 512
  let total = 1000
  let payload = make_payload(9, total)
  let local_len = expected_local(page_size, total)
  let chunk = page_size - 4
  let local_bytes : Array[Byte] = []
  for i in 0..<local_len {
    local_bytes.push(payload[i])
  }
  // 根 leaf 在第 2 页（第 1 页只有文件头区）。
  let leaf = make_page(
    page_size,
    13,
    [leaf_cell_overflow(1, total, local_bytes, 3)],
    0,
    false,
  )
  let ov1 = buf_new(page_size)
  put_u32(ov1, 0, 4)
  let mut i = 0
  while i < chunk {
    ov1.data[4 + i] = payload[local_len + i]
    i = i + 1
  }
  let ov2 = buf_new(page_size)
  put_u32(ov2, 0, 0)
  let rest = total - local_len - chunk
  let mut j = 0
  while j < rest {
    ov2.data[4 + j] = payload[local_len + chunk + j]
    j = j + 1
  }
  let bytes = concat([buf_new(page_size).data, leaf, ov1.data, ov2.data])
  assert_eq(page_type(bytes, 2, page_size), 13)
  let recs = scan_table(bytes, page_size, 2)
  assert_eq(recs.length(), 1)
  assert_eq(recs[0].0, 1L)
  assert_eq(recs[0].2, total)
  let got = read_payload(bytes, page_size, recs[0].1, recs[0].2)
  assert_eq(got.length(), total)
  assert_true(bytes_eq(got, payload))
}

///|
test "payload that fits locally does not follow an overflow pointer" {
  let page_size = 512
  let total = page_size - 35
  let payload = make_payload(3, total)
  let leaf = make_page(page_size, 13, [leaf_cell(1, payload)], 0, false)
  // 后面接一个全零页；本地放得下时不应读它。
  let bytes = concat([buf_new(page_size).data, leaf])
  let recs = scan_table(bytes, page_size, 2)
  assert_eq(recs.length(), 1)
  assert_true(
    bytes_eq(read_payload(bytes, page_size, recs[0].1, recs[0].2), payload),
  )
}

///|
test "defensive reads do not panic on corrupt input" {
  let page_size = 512
  let empty : Array[Byte] = []
  assert_eq(scan_table(Bytes::from_array(empty[:]), page_size, 1).length(), 0)
  let leaf = concat([
    make_page(page_size, 13, [leaf_cell(1, make_payload(1, 2))], 0, true),
  ])
  // 根页越界
  assert_eq(scan_table(leaf, page_size, 7).length(), 0)
  assert_eq(scan_table(leaf, page_size, 0).length(), 0)
  // 0 cell 的叶页
  let zero = concat([make_page(page_size, 13, [], 0, true)])
  assert_eq(scan_table(zero, page_size, 1).length(), 0)
  // 索引 b-tree 页不是表 b-tree
  let idx = concat([
    make_page(page_size, 10, [leaf_cell(1, make_payload(1, 2))], 0, true),
  ])
  assert_eq(scan_table(idx, page_size, 1).length(), 0)
  // cell 数被写坏：截断而不是越界读
  let good = make_page(
    page_size,
    13,
    [leaf_cell(1, make_payload(1, 2))],
    0,
    true,
  )
  let bb : Buf = { data: good, }
  put_u16(bb, 100 + 3, 0xffff)
  let bad = Bytes::from_array(bb.data[:])
  let recs = scan_table(bad, page_size, 1)
  assert_true(recs.length() <= 1)
  // payload 偏移越界
  assert_eq(read_payload(leaf, page_size, 100000, 10).length(), 0)
  assert_eq(read_payload(leaf, page_size, -5, 10).length(), 0)
  // payload 长度为 0
  assert_eq(read_payload(leaf, page_size, 200, 0).length(), 0)
}

///|
test "overflow chain that points at itself terminates" {
  let page_size = 512
  // 547 = 39 字节本地 + 正好一页（508）溢出数据，自环页只装一次。
  let total = 547
  let payload = make_payload(5, total)
  let local_len = expected_local(page_size, total)
  let local_bytes : Array[Byte] = []
  for i in 0..<local_len {
    local_bytes.push(payload[i])
  }
  let leaf = make_page(
    page_size,
    13,
    [leaf_cell_overflow(1, total, local_bytes, 3)],
    0,
    false,
  )
  let ov = buf_new(page_size)
  put_u32(ov, 0, 3) // 指向自己
  let rest = total - local_len
  let mut i = 0
  while i < rest {
    ov.data[4 + i] = payload[local_len + i]
    i = i + 1
  }
  let bytes = concat([buf_new(page_size).data, leaf, ov.data])
  let recs = scan_table(bytes, page_size, 2)
  assert_eq(recs.length(), 1)
  let got = read_payload(bytes, page_size, recs[0].1, recs[0].2)
  // 自环必须终止：只读一页就停，长度等于声明值且不无限增长
  assert_true(got.length() <= total)
  assert_eq(got.length(), total)
}

///|
test "property: random leaf cells scan in ascending rowid order" {
  let p = prng(7)
  for round in 0..<30 {
    let n = pick(p, 12) + 1
    let ids : Array[Int32] = []
    let mut tries = 0
    while ids.length() < n && tries < 300 {
      tries = tries + 1
      let cand = pick(p, 500) + 1
      let mut dup = false
      for x in ids {
        if x == cand {
          dup = true
        }
      }
      if !dup {
        ids.push(cand)
      }
    }
    sort_ints(ids)
    let payloads : Array[Cell] = []
    let cells : Array[Cell] = []
    for i in 0..<ids.length() {
      let pl = make_payload(round + i, pick(p, 8) + 1)
      payloads.push(pl)
      cells.push(leaf_cell(ids[i], pl))
    }
    let bytes = concat([make_page(512, 13, cells, 0, true)])
    let recs = scan_table(bytes, 512, 1)
    assert_eq(recs.length(), ids.length())
    let mut prev = -1L
    for i in 0..<recs.length() {
      assert_eq(recs[i].0, ids[i].to_int64())
      assert_true(recs[i].0 > prev)
      prev = recs[i].0
      assert_true(
        bytes_eq(read_payload(bytes, 512, recs[i].1, recs[i].2), payloads[i]),
      )
    }
  }
}

///|
test "property: interior root keeps global order across two leaves" {
  let p = prng(21)
  for round in 0..<20 {
    let n = pick(p, 10) + 2
    let ids : Array[Int32] = []
    let mut tries = 0
    while ids.length() < n && tries < 300 {
      tries = tries + 1
      let cand = pick(p, 900) + 1
      let mut dup = false
      for x in ids {
        if x == cand {
          dup = true
        }
      }
      if !dup {
        ids.push(cand)
      }
    }
    sort_ints(ids)
    let mid = ids.length() / 2
    let left_cells : Array[Cell] = []
    let right_cells : Array[Cell] = []
    for i in 0..<ids.length() {
      let cell = leaf_cell(ids[i], make_payload(round + i, 3))
      if i < mid {
        left_cells.push(cell)
      } else {
        right_cells.push(cell)
      }
    }
    let root = make_page(512, 5, [interior_cell(2, ids[mid])], 3, true)
    let leaf2 = make_page(512, 13, left_cells, 0, false)
    let leaf3 = make_page(512, 13, right_cells, 0, false)
    let bytes = concat([root, leaf2, leaf3])
    let recs = scan_table(bytes, 512, 1)
    assert_eq(recs.length(), ids.length())
    let mut prev = -1L
    for i in 0..<recs.length() {
      assert_eq(recs[i].0, ids[i].to_int64())
      assert_true(recs[i].0 > prev)
      prev = recs[i].0
    }
  }
}
