// 表 b-tree 遍历与溢出页拼接。
//
// leaf table cell：varint payload 总长 P、varint rowid、payload。
// interior table cell：4 字节左孩子页号、varint rowid（没有 payload）。
// 溢出链每个页：4 字节下一页号 + 最多 usable-4 字节数据，页号 0 结束。
//
// 本地 payload 长度（文档 §1.6，等价 sqlite3 的 btreeComputeLocalSize）：
//   表叶页阈值 X = usable - 35
//   索引页阈值 X = ((usable-12)*64/255) - 23      （见 index.mbt）
//   若 P <= X：local = P
//   否则：M = ((usable-12)*32/255) - 23
//         K = M + ((P - M) % (usable - 4))
//         local = (K <= X) ? K : M
// 注意不是「P <= K ? K : M」——K 的作用就是让超出本地的部分恰好是 usable-4 的
// 整数倍，溢出链上每个页都装满，链尾不会留下半页；按 M 取会让溢出指针位置错位，
// 表现为读回的 payload 只有本地那几十/几百字节（真库上就是这样抓到的）。
//
// 所有读取都带边界检查：坏文件只会得到空结果或截断结果，不会 panic。

///|
// 带边界的 varint：超出 limit 返回 None，行为与 @format.varint 一致。
fn varint_at(bytes : Bytes, at : Int32, limit : Int32) -> (Int64, Int32)? {
  if at < 0 || at >= limit {
    return None
  }
  let mut v : Int64 = 0L
  let mut i = 0
  while i < 8 {
    if at + i >= limit {
      return None
    }
    let b = bytes[at + i].to_int()
    v = (v << 7) | (b & 0x7f).to_int64()
    i = i + 1
    if (b & 0x80) == 0 {
      return Some((v, i))
    }
  }
  if at + 8 >= limit {
    return None
  }
  Some(((v << 8) | bytes[at + 8].to_int64(), 9))
}

///|
// 本地 payload 长度（官方文档 §1.6，对应 sqlite3 的 btreeComputeLocalSize）。
// 阈值是 X = usable-35；超过 X 时用 M/K 公式：
//   M = ((usable-12)*32/255) - 23
//   K = M + ((P-M) % (usable-4))
//   local = (K <= X) ? K : M
// 注意不是「P <= K ? K : M」——那会把本地长度算成 M，溢出指针位置就偏了。
fn local_payload_len(page_size : Int32, payload_size : Int32) -> Int32 {
  let x = if page_size > 35 { page_size - 35 } else { 0 }
  if payload_size <= x {
    payload_size
  } else {
    let m0 = (page_size - 12) * 32 / 255 - 23
    let m = if m0 < 0 { 0 } else { m0 }
    let span = if page_size > 4 { page_size - 4 } else { 1 }
    let k = m + (payload_size - m) % span
    if k <= x {
      k
    } else {
      m
    }
  }
}

///|
// 解析一个 leaf table cell，返回 (rowid, payload 起始偏移, payload 总长)。
fn parse_leaf_cell(
  bytes : Bytes,
  at : Int32,
  limit : Int32,
  page_size : Int32,
) -> (Int64, Int32, Int32)? {
  match varint_at(bytes, at, limit) {
    Some((p, n1)) =>
      if p < 0L {
        None
      } else {
        match varint_at(bytes, at + n1, limit) {
          Some((rowid, n2)) => {
            let size = p.to_int()
            let payload_at = at + n1 + n2
            if size < 0 {
              return None
            }
            let local_len = local_payload_len(page_size, size)
            // 本地部分 + 溢出页号（如有）都必须落在页内
            let need = if local_len < size { local_len + 4 } else { local_len }
            if payload_at + need > limit {
              None
            } else {
              Some((rowid, payload_at, size))
            }
          }
          None => None
        }
      }
    None => None
  }
}

///|
// 递归遍历：interior 页按 cell 顺序先走左孩子，最后走页头里的最右孩子。
fn walk_table(
  bytes : Bytes,
  page_size : Int32,
  page : Int32,
  out : Array[(Int64, Int32, Int32)],
  budget : Array[Int32],
  depth : Int32,
) -> Unit {
  if depth > 64 || budget[0] <= 0 {
    return
  }
  let typ = page_type(bytes, page, page_size)
  let hdr = page_header_at(bytes, page, page_size)
  if hdr < 0 {
    return
  }
  if typ != PAGE_LEAF_TABLE && typ != PAGE_INTERIOR_TABLE {
    return
  }
  budget[0] = budget[0] - 1
  let n = cell_count_of(bytes, page, page_size, hdr)
  let page_end = page_start_of(page, page_size) + page_size
  let limit = if page_end > bytes.length() { bytes.length() } else { page_end }
  if typ == PAGE_LEAF_TABLE {
    for i in 0..<n {
      let at = cell_offset(bytes, page, page_size, i)
      if at >= 0 {
        match parse_leaf_cell(bytes, at, limit, page_size) {
          Some(rec) => out.push(rec)
          None => ()
        }
      }
    }
  } else {
    for i in 0..<n {
      let at = cell_offset(bytes, page, page_size, i)
      if at >= 0 && at + 4 <= limit {
        let child = u32_at(bytes, at)
        if child > 0 {
          walk_table(bytes, page_size, child, out, budget, depth + 1)
        }
      }
    }
    let right = u32_at(bytes, hdr + 8)
    if right > 0 {
      walk_table(bytes, page_size, right, out, budget, depth + 1)
    }
  }
}

///|
pub fn scan_table(
  bytes : Bytes,
  page_size : Int32,
  root_page : Int32,
) -> Array[(Int64, Int32, Int32)] {
  let out : Array[(Int64, Int32, Int32)] = []
  if page_size <= 0 || root_page < 1 {
    return out
  }
  let pages = bytes.length() / page_size
  if pages < 1 {
    return out
  }
  // 预算 = 总页数：坏文件里的环最多走完一遍就停。
  let budget : Array[Int32] = [pages]
  walk_table(bytes, page_size, root_page, out, budget, 0)
  out
}

///|
fn copy_range(bytes : Bytes, at : Int32, n : Int32, out : Array[Byte]) -> Unit {
  let mut i = 0
  while i < n {
    let idx = at + i
    if idx < 0 || idx >= bytes.length() {
      return
    }
    out.push(bytes[idx])
    i = i + 1
  }
}

///|
fn read_payload_kind(
  bytes : Bytes,
  page_size : Int32,
  payload_offset : Int32,
  payload_size : Int32,
  index_pages : Bool,
) -> Bytes {
  let out : Array[Byte] = []
  if payload_size <= 0 || page_size <= 0 {
    return Bytes::from_array(out[:])
  }
  let local_len = if index_pages {
    local_payload_len_index(page_size, payload_size)
  } else {
    local_payload_len(page_size, payload_size)
  }
  if local_len <= 0 {
    return Bytes::from_array(out[:])
  }
  copy_range(bytes, payload_offset, local_len, out)
  let mut remaining = payload_size - local_len
  if remaining > 0 {
    let mut next = u32_at(bytes, payload_offset + local_len)
    let pages = bytes.length() / page_size
    let mut steps = 0
    while next > 0 && remaining > 0 && steps <= pages {
      steps = steps + 1
      if next < 1 || next > pages {
        break
      }
      let start = page_start_of(next, page_size)
      if start + 4 > bytes.length() {
        break
      }
      next = u32_at(bytes, start)
      let chunk = if remaining > page_size - 4 {
        page_size - 4
      } else {
        remaining
      }
      copy_range(bytes, start + 4, chunk, out)
      remaining = remaining - chunk
    }
  }
  Bytes::from_array(out[:])
}

///|
/// 表 b-tree 的 payload 读取：本地部分 + 溢出链。
pub fn read_payload(
  bytes : Bytes,
  page_size : Int32,
  payload_offset : Int32,
  payload_size : Int32,
) -> Bytes {
  read_payload_kind(bytes, page_size, payload_offset, payload_size, false)
}
