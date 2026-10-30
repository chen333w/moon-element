// b-tree 页结构（SQLite 官方文档 §1.5 与 §1.6）。
//
// 页号从 1 开始，第 N 页的文件偏移是 (N-1)*page_size。
// 第 1 页前 100 字节是数据库文件头，b-tree 页头从页内 offset 100 开始；
// cell pointer 数组里的偏移一律相对「页首」而不是页头。
// page_size 参数按「可用页大小 usable」解释（保留字节为 0 时等于页大小）。

///|
// SQLite b-tree 页类型。
const PAGE_INTERIOR_INDEX : Int32 = 2

///|
const PAGE_INTERIOR_TABLE : Int32 = 5

///|
const PAGE_LEAF_INDEX : Int32 = 10

///|
const PAGE_LEAF_TABLE : Int32 = 13

///|
fn page_start_of(page : Int32, page_size : Int32) -> Int32 {
  (page - 1) * page_size
}

///|
fn in_range(bytes : Bytes, at : Int32, n : Int32) -> Bool {
  at >= 0 && n >= 0 && at + n <= bytes.length()
}

///|
fn u16_at(bytes : Bytes, at : Int32) -> Int32 {
  if in_range(bytes, at, 2) {
    @format.be_u16(bytes, at)
  } else {
    0
  }
}

///|
fn u32_at(bytes : Bytes, at : Int32) -> Int32 {
  if in_range(bytes, at, 4) {
    @format.be_u32(bytes, at).reinterpret_as_int()
  } else {
    0
  }
}

///|
fn header_len_of(typ : Int32) -> Int32 {
  if typ == PAGE_INTERIOR_INDEX || typ == PAGE_INTERIOR_TABLE {
    12
  } else {
    8
  }
}

///|
// 返回 b-tree 页头的绝对文件偏移；页号越界或页不完整时返回 -1。
fn page_header_at(bytes : Bytes, page : Int32, page_size : Int32) -> Int32 {
  if page_size <= 0 || page < 1 {
    return -1
  }
  let start = page_start_of(page, page_size)
  if start + page_size > bytes.length() {
    return -1
  }
  if page == 1 {
    start + 100
  } else {
    start
  }
}

///|
pub fn page_type(bytes : Bytes, page : Int32, page_size : Int32) -> Int32 {
  let hdr = page_header_at(bytes, page, page_size)
  if hdr < 0 || !in_range(bytes, hdr, 1) {
    return 0
  }
  let t = bytes[hdr].to_int()
  if t == PAGE_INTERIOR_INDEX ||
    t == PAGE_INTERIOR_TABLE ||
    t == PAGE_LEAF_INDEX ||
    t == PAGE_LEAF_TABLE {
    t
  } else {
    0
  }
}

///|
// 页头的 cell 数；异常值按页容量截断，避免用坏数据做越界读。
fn cell_count_of(
  bytes : Bytes,
  page : Int32,
  page_size : Int32,
  hdr : Int32,
) -> Int32 {
  let start = page_start_of(page, page_size)
  let typ = bytes[hdr].to_int()
  let hlen = header_len_of(typ)
  let avail = page_size - (hdr - start) - hlen
  if avail < 2 {
    return 0
  }
  let raw = u16_at(bytes, hdr + 3)
  let max_cells = avail / 2
  if raw > max_cells {
    max_cells
  } else {
    raw
  }
}

///|
// 第 i 个 cell 的绝对文件偏移；指针越界时返回 -1。
fn cell_offset(
  bytes : Bytes,
  page : Int32,
  page_size : Int32,
  i : Int32,
) -> Int32 {
  let hdr = page_header_at(bytes, page, page_size)
  if hdr < 0 {
    return -1
  }
  let start = page_start_of(page, page_size)
  let typ = bytes[hdr].to_int()
  let hlen = header_len_of(typ)
  let ptr = hdr + hlen + 2 * i
  if !in_range(bytes, ptr, 2) {
    return -1
  }
  let off = u16_at(bytes, ptr)
  // cell 只能落在 cell 内容区里：指针指向页头/页外都是坏数据。
  let content_start = u16_at(bytes, hdr + 5)
  let header_end = hdr - start + hlen
  let min_off = if content_start >= header_end && content_start < page_size {
    content_start
  } else {
    header_end
  }
  if off < min_off || off >= page_size {
    return -1
  }
  start + off
}
