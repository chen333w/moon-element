// 测试用的字节缓冲与页构造器：手工拼出最小的 SQLite 页与 DB 字节流。

///|
// cell 的字节序列。
type Cell = Array[Byte]

///|
priv struct Buf {
  data : Array[Byte]
}

///|
fn buf_new(n : Int32) -> Buf {
  { data: Array::make(n, (0).to_byte()), }
}

///|
fn put_u8(b : Buf, at : Int32, v : Int32) -> Unit {
  b.data[at] = (v & 0xff).to_byte()
}

///|
fn put_u16(b : Buf, at : Int32, v : Int32) -> Unit {
  put_u8(b, at, (v >> 8) & 0xff)
  put_u8(b, at + 1, v & 0xff)
}

///|
fn put_u32(b : Buf, at : Int32, v : Int32) -> Unit {
  put_u8(b, at, (v >> 24) & 0xff)
  put_u8(b, at + 1, (v >> 16) & 0xff)
  put_u8(b, at + 2, (v >> 8) & 0xff)
  put_u8(b, at + 3, v & 0xff)
}

///|
fn varint_len(v : Int32) -> Int32 {
  let mut n = 1
  let mut x = v
  while x >= 0x80 {
    x = x >> 7
    n = n + 1
  }
  n
}

///|
fn push_varint(out : Array[Byte], v : Int32) -> Unit {
  let n = varint_len(v)
  let mut i = 0
  while i < n {
    let shift = (n - 1 - i) * 7
    let mut b = (v >> shift) & 0x7f
    if i < n - 1 {
      b = b | 0x80
    }
    out.push(b.to_byte())
    i = i + 1
  }
}

///|
fn push_u32(out : Array[Byte], v : Int32) -> Unit {
  out.push(((v >> 24) & 0xff).to_byte())
  out.push(((v >> 16) & 0xff).to_byte())
  out.push(((v >> 8) & 0xff).to_byte())
  out.push((v & 0xff).to_byte())
}

///|
// leaf table cell：varint 总长、varint rowid、payload。
fn leaf_cell(rowid : Int32, payload : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  push_varint(out, payload.length())
  push_varint(out, rowid)
  for x in payload {
    out.push(x)
  }
  out
}

///|
// 带溢出页的 leaf table cell：总长用完整 payload 长度，本地部分只放 local_bytes 字节。
fn leaf_cell_overflow(
  rowid : Int32,
  total : Int32,
  local_bytes : Array[Byte],
  next : Int32,
) -> Array[Byte] {
  let out : Array[Byte] = []
  push_varint(out, total)
  push_varint(out, rowid)
  for x in local_bytes {
    out.push(x)
  }
  push_u32(out, next)
  out
}

///|
// 官方文档 §1.6 的本地 payload 长度（测试侧按文档独立实现，用于摆放手工 cell）。
fn expected_local(page_size : Int32, total : Int32) -> Int32 {
  let x = page_size - 35
  if total <= x {
    total
  } else {
    let m = (page_size - 12) * 32 / 255 - 23
    let k = m + (total - m) % (page_size - 4)
    if k <= x {
      k
    } else {
      m
    }
  }
}

///|
// 索引页的本地 payload 长度（X 用索引页公式，M/K 与表叶相同）。
fn expected_local_index(page_size : Int32, total : Int32) -> Int32 {
  let x = (page_size - 12) * 64 / 255 - 23
  if total <= x {
    total
  } else {
    let m = (page_size - 12) * 32 / 255 - 23
    let k = m + (total - m) % (page_size - 4)
    if k <= x {
      k
    } else {
      m
    }
  }
}

///|
// leaf index cell：varint payload 长度 + payload。
fn index_leaf_cell(payload : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  push_varint(out, payload.length())
  for x in payload {
    out.push(x)
  }
  out
}

///|
// 带溢出页的 leaf index cell。
fn index_leaf_cell_overflow(
  total : Int32,
  local_bytes : Array[Byte],
  next : Int32,
) -> Array[Byte] {
  let out : Array[Byte] = []
  push_varint(out, total)
  for x in local_bytes {
    out.push(x)
  }
  push_u32(out, next)
  out
}

///|
// interior index cell：4 字节左孩子 + varint payload 长度 + payload。
fn index_interior_cell(
  left_child : Int32,
  payload : Array[Byte],
) -> Array[Byte] {
  let out : Array[Byte] = []
  push_u32(out, left_child)
  push_varint(out, payload.length())
  for x in payload {
    out.push(x)
  }
  out
}

///|
fn interior_cell(left_child : Int32, rowid : Int32) -> Array[Byte] {
  let out : Array[Byte] = []
  push_u32(out, left_child)
  push_varint(out, rowid)
  out
}

///|
// 构造一页：cells 按 key 顺序从页尾向前布局，cell pointer 数组紧随页头。
fn make_page(
  page_size : Int32,
  typ : Int32,
  cells : Array[Cell],
  right_child : Int32,
  page1 : Bool,
) -> Array[Byte] {
  let b = buf_new(page_size)
  let hdr = if page1 { 100 } else { 0 }
  let hlen = if typ == 2 || typ == 5 { 12 } else { 8 }
  put_u8(b, hdr, typ)
  put_u16(b, hdr + 1, 0)
  put_u16(b, hdr + 3, cells.length())
  put_u8(b, hdr + 7, 0)
  if hlen == 12 {
    put_u32(b, hdr + 8, right_child)
  }
  let mut cursor = page_size
  for i in 0..<cells.length() {
    let c = cells[i]
    cursor = cursor - c.length()
    let mut k = 0
    while k < c.length() {
      b.data[cursor + k] = c[k]
      k = k + 1
    }
    put_u16(b, hdr + hlen + 2 * i, cursor)
  }
  put_u16(b, hdr + 5, if cells.length() > 0 { cursor } else { page_size })
  b.data
}

///|
fn concat(pages : Array[Cell]) -> Bytes {
  let out : Array[Byte] = []
  for p in pages {
    for x in p {
      out.push(x)
    }
  }
  Bytes::from_array(out[:])
}

///|
fn bytes_eq(bytes : Bytes, expected : Array[Byte]) -> Bool {
  if bytes.length() != expected.length() {
    false
  } else {
    let mut ok = true
    let mut i = 0
    while i < expected.length() {
      if bytes[i] != expected[i] {
        ok = false
      }
      i = i + 1
    }
    ok
  }
}

///|
// 确定性 payload：第 i 字节 = (i * 7 + seed) % 256。
fn make_payload(seed : Int32, n : Int32) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut i = 0
  while i < n {
    out.push(((i * 7 + seed) & 0xff).to_byte())
    i = i + 1
  }
  out
}

///|
priv struct Prng {
  s : Array[Int32]
}

///|
fn prng(seed : Int32) -> Prng {
  { s: [seed + 1], }
}

///|
fn prnd(p : Prng) -> Int32 {
  p.s[0] = (p.s[0] * 37 + 11) % 1009
  p.s[0]
}

///|
fn pick(p : Prng, n : Int32) -> Int32 {
  prnd(p) % n
}

///|
// 插入排序：把随机 rowid 排成页内必须的升序。
fn sort_ints(a : Array[Int32]) -> Unit {
  let mut i = 1
  while i < a.length() {
    let v = a[i]
    let mut j = i - 1
    while j >= 0 && a[j] > v {
      a[j + 1] = a[j]
      j = j - 1
    }
    a[j + 1] = v
    i = i + 1
  }
}
