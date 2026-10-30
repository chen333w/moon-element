// 索引 b-tree 的叶扫描（WITHOUT ROWID 表的数据就存在这里）。
//
// 与表 b-tree 的差别：
// - 索引 cell 没有 rowid：
//     leaf index cell      = varint payload 长度 + payload
//     interior index cell  = 4 字节左孩子页号 + varint payload 长度 + payload
// - 本地 payload 的阈值公式不同：索引页 X = ((usable-12)*64/255)-23，
//   表叶页 X = usable-35。M/K 部分两者一样。
// - 全叶扫描只需要叶子的 payload，interior 页自身的 payload 直接忽略，只递归子树。

///|
// 索引页的本地 payload 长度。X 用索引页公式，M/K 与表叶相同：
//   local = (K <= X) ? K : M
fn local_payload_len_index(page_size : Int32, payload_size : Int32) -> Int32 {
  let u = page_size
  let x = (u - 12) * 64 / 255 - 23
  if payload_size <= x {
    payload_size
  } else {
    let m0 = (u - 12) * 32 / 255 - 23
    let m = if m0 < 0 { 0 } else { m0 }
    let span = if u > 4 { u - 4 } else { 1 }
    let k = m + (payload_size - m) % span
    if k <= x {
      k
    } else {
      m
    }
  }
}

///|
// 解析一个 leaf index cell，返回 (payload 起始偏移, payload 总长)。
fn parse_index_leaf_cell(
  bytes : Bytes,
  at : Int32,
  limit : Int32,
  page_size : Int32,
) -> (Int32, Int32)? {
  match varint_at(bytes, at, limit) {
    Some((p, n1)) => {
      let size = p.to_int()
      if size < 0 {
        return None
      }
      let payload_at = at + n1
      let local_len = local_payload_len_index(page_size, size)
      // 本地部分 + 溢出页号（如有）都必须落在页内
      let need = if local_len < size { local_len + 4 } else { local_len }
      if payload_at + need > limit {
        None
      } else {
        Some((payload_at, size))
      }
    }
    None => None
  }
}

///|
fn walk_index(
  bytes : Bytes,
  page_size : Int32,
  page : Int32,
  out : Array[(Int32, Int32)],
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
  if typ != PAGE_LEAF_INDEX && typ != PAGE_INTERIOR_INDEX {
    return
  }
  budget[0] = budget[0] - 1
  let n = cell_count_of(bytes, page, page_size, hdr)
  let page_end = page_start_of(page, page_size) + page_size
  let limit = if page_end > bytes.length() { bytes.length() } else { page_end }
  if typ == PAGE_LEAF_INDEX {
    for i in 0..<n {
      let at = cell_offset(bytes, page, page_size, i)
      if at >= 0 {
        match parse_index_leaf_cell(bytes, at, limit, page_size) {
          Some(rec) => out.push(rec)
          None => ()
        }
      }
    }
  } else {
    // interior index cell 自己的 payload 不属于叶记录，只走孩子。
    for i in 0..<n {
      let at = cell_offset(bytes, page, page_size, i)
      if at >= 0 && at + 4 <= limit {
        let child = u32_at(bytes, at)
        if child > 0 {
          walk_index(bytes, page_size, child, out, budget, depth + 1)
        }
      }
    }
    let right = u32_at(bytes, hdr + 8)
    if right > 0 {
      walk_index(bytes, page_size, right, out, budget, depth + 1)
    }
  }
}

///|
/// 索引 b-tree 的全叶扫描：返回每个叶 cell 的 (payload 偏移, payload 长度)。
/// WITHOUT ROWID 表用这个入口；payload 里含全部列值（key 列也在里面）。
pub fn scan_index_leaves(
  bytes : Bytes,
  page_size : Int32,
  root_page : Int32,
) -> Array[(Int32, Int32)] {
  let out : Array[(Int32, Int32)] = []
  if page_size <= 0 || root_page < 1 {
    return out
  }
  let pages = bytes.length() / page_size
  if pages < 1 {
    return out
  }
  let budget : Array[Int32] = [pages]
  walk_index(bytes, page_size, root_page, out, budget, 0)
  out
}

///|
/// 索引 b-tree 的 payload 读取：本地长度按索引页规则算，溢出链与表 b-tree 相同。
pub fn read_index_payload(
  bytes : Bytes,
  page_size : Int32,
  payload_offset : Int32,
  payload_size : Int32,
) -> Bytes {
  read_payload_kind(bytes, page_size, payload_offset, payload_size, true)
}
