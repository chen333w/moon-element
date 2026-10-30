// 页结构测试：页类型识别，特别是第 1 页的 100 字节文件头偏移。

///|
test "page type reads the btree header after the 100 byte file header" {
  // 页首 offset 0 写 13、页内 offset 100 写 5：必须读到 5（第 1 页的 b-tree 页头在 100）。
  let b = buf_new(512)
  put_u8(b, 0, 13)
  put_u8(b, 100, 5)
  let bytes = Bytes::from_array(b.data[:])
  assert_eq(page_type(bytes, 1, 512), 5)
}

///|
test "page type accepts all four btree page types" {
  let leaf = concat([make_page(512, 13, [], 0, true)])
  assert_eq(page_type(leaf, 1, 512), 13)
  let interior = concat([make_page(512, 5, [], 3, true)])
  assert_eq(page_type(interior, 1, 512), 5)
  let index_leaf = concat([make_page(512, 10, [], 0, true)])
  assert_eq(page_type(index_leaf, 1, 512), 10)
  let index_interior = concat([make_page(512, 2, [], 0, true)])
  assert_eq(page_type(index_interior, 1, 512), 2)
}

///|
test "page type rejects out-of-range pages and unknown type bytes" {
  let bytes = concat([make_page(512, 13, [], 0, true)])
  // 页号 0 / 越界 / 页大小不合法 / 文件不完整
  assert_eq(page_type(bytes, 0, 512), 0)
  assert_eq(page_type(bytes, 2, 512), 0)
  assert_eq(page_type(bytes, 1, 0), 0)
  assert_eq(page_type(bytes, 1, 4096), 0)
  // 未知类型字节
  let b = buf_new(512)
  put_u8(b, 0, 7)
  assert_eq(page_type(Bytes::from_array(b.data[:]), 1, 512), 0)
  // 空字节流
  let empty : Array[Byte] = []
  assert_eq(page_type(Bytes::from_array(empty[:]), 1, 512), 0)
}
