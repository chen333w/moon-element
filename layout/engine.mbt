// 布局引擎：盒模型 + 块级流 + flexbox。
//
// 约定（与 types.mbt 的冻结接口一致）：
// - rect 一律是边框盒；style.width / style.height 是内容盒尺寸。
// - 相邻 margin 不合并（简化）。
// - 文本不换行：宽度直接取注入的 measure，超宽交给父级裁切。
// - 文本节点由 StyleNode.text = Some(内容) 标识（info.tag 固定 "#text"）。
// - flex_wrap 只对 row 方向生效；column 方向按单行处理。

///|
// 上一次 layout 的节点访问次数（测量一次 + 定位一次，每个节点至多一次）。
let g_visits : Array[Int32] = [0]

///|
pub fn layout_visit_count() -> Int32 {
  g_visits[0]
}

///|
fn bump() -> Unit {
  g_visits[0] = g_visits[0] + 1
}

///|
fn max2(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn clamp0(v : Double) -> Double {
  if v < 0.0 {
    0.0
  } else {
    v
  }
}

///|
fn some_d(v : Double?) -> Bool {
  match v {
    Some(_) => true
    None => false
  }
}

///|
// 解析长度；base 是包含块对应轴的内容盒尺寸，未知时传 None。
fn resolve_len(
  len : @style.Length,
  base : Double?,
  font_size : Double,
) -> Double? {
  match len {
    @style.Length::Px(v) => Some(v)
    @style.Length::Percent(p) =>
      match base {
        Some(b) => Some(b * p / 100.0)
        None => None
      }
    @style.Length::Em(v) => Some(v * font_size)
    @style.Length::Rem(v) => Some(v * 16.0)
    @style.Length::Auto => None
  }
}

///|
// 按 min_width / max_width 夹取内容盒宽。
fn clamp_w(st : @style.ComputedStyle, v : Double, cb : Double) -> Double {
  let mut r = v
  match resolve_len(st.min_width, Some(cb), st.font_size) {
    Some(lo) => if r < lo { r = lo }
    None => ()
  }
  match resolve_len(st.max_width, Some(cb), st.font_size) {
    Some(hi) => if r > hi { r = hi }
    None => ()
  }
  clamp0(r)
}

///|
// 固有尺寸缓存 + 文本测量函数。
priv struct Ctx {
  iw : Array[Double]
  ih : Array[Double]
  tw : Array[Double]
  lh : Array[Double]
  sub : Array[Int32]
  measure : TextMeasure
}

///|
// 前序遍历：分配前序下标，并算出固有宽高（iw/ih，边框盒）与子树节点数。
fn measure_tree(ctx : Ctx, node : StyleNode) -> Int32 {
  bump()
  let idx = ctx.iw.length()
  ctx.iw.push(0.0)
  ctx.ih.push(0.0)
  ctx.tw.push(0.0)
  ctx.lh.push(0.0)
  ctx.sub.push(1)
  let st = node.style
  match node.text {
    Some(s) => {
      let f = ctx.measure
      let (w, h) = f(s, st.font_size)
      ctx.tw[idx] = w
      ctx.lh[idx] = h
      ctx.iw[idx] = clamp0(w + st.padding.horizontal() + st.border.horizontal())
      ctx.ih[idx] = clamp0(h + st.padding.vertical() + st.border.vertical())
    }
    None => {
      let mut sum_w = 0.0
      let mut sum_h = 0.0
      let mut peak_w = 0.0
      let mut peak_h = 0.0
      let mut total = 1
      for c in node.children {
        let ci = measure_tree(ctx, c)
        total = total + ctx.sub[ci]
        let m = c.style.margin
        let cw = ctx.iw[ci] + m.horizontal()
        let ch = ctx.ih[ci] + m.vertical()
        sum_w = sum_w + cw
        sum_h = sum_h + ch
        peak_w = max2(peak_w, cw)
        peak_h = max2(peak_h, ch)
      }
      ctx.sub[idx] = total
      if st.display != @style.Display::None {
        let p = st.padding
        let b = st.border
        let n = node.children.length()
        let gaps = if n > 1 { st.gap * (n - 1).to_double() } else { 0.0 }
        let (cw, ch) = if st.display == @style.Display::Flex {
          if st.flex_direction == @style.FlexDirection::Row {
            (sum_w + gaps, peak_h)
          } else {
            (peak_w, sum_h + gaps)
          }
        } else {
          (peak_w, sum_h)
        }
        let mut bw = cw + p.horizontal() + b.horizontal()
        let mut bh = ch + p.vertical() + b.vertical()
        match st.width {
          @style.Length::Px(v) => bw = v + p.horizontal() + b.horizontal()
          _ => ()
        }
        match st.height {
          @style.Length::Px(v) => bh = v + p.vertical() + b.vertical()
          _ => ()
        }
        ctx.iw[idx] = clamp0(bw)
        ctx.ih[idx] = clamp0(bh)
      }
    }
  }
  idx
}

///|
fn layout_block(
  ctx : Ctx,
  node : StyleNode,
  idx : Int32,
  cx : Double,
  cy : Double,
  cw : Double,
) -> (Array[LayoutBox], Double) {
  let out : Array[LayoutBox] = []
  let mut y = 0.0
  let mut cur = idx + 1
  for c in node.children {
    let ci = cur
    cur = cur + ctx.sub[ci]
    if c.style.display != @style.Display::None {
      let m = c.style.margin
      let (box, outer_h) = layout_node(
        ctx,
        c,
        ci,
        cx + m.left,
        cy + y + m.top,
        cw,
        None,
        None,
        None,
      )
      out.push(box)
      y = y + outer_h
    }
  }
  (out, y)
}

///|
// flex 子项：基准尺寸与增长/收缩因子。
priv struct FlexItem {
  node : StyleNode
  idx : Int32
  base : Double
  extra_main : Double
  extra_cross : Double
  cross_content : Double
  cross_auto : Bool
  grow : Double
  shrink : Double
}

///|
fn make_item(
  ctx : Ctx,
  node : StyleNode,
  idx : Int32,
  row : Bool,
  main_base : Double?,
  cross_base : Double?,
) -> FlexItem {
  let st = node.style
  let p = st.padding
  let b = st.border
  let m = st.margin
  let (extra_main, extra_cross) = if row {
    (
      m.horizontal() + p.horizontal() + b.horizontal(),
      m.vertical() + p.vertical() + b.vertical(),
    )
  } else {
    (
      m.vertical() + p.vertical() + b.vertical(),
      m.horizontal() + p.horizontal() + b.horizontal(),
    )
  }
  // 主轴基准：flex_basis → 显式尺寸 → 内容固有尺寸。
  let basis = match resolve_len(st.flex_basis, main_base, st.font_size) {
    Some(v) => Some(v)
    None =>
      if row {
        resolve_len(st.width, main_base, st.font_size)
      } else {
        resolve_len(st.height, main_base, st.font_size)
      }
  }
  let mut base = match basis {
    Some(v) => v
    None =>
      if row {
        ctx.iw[idx] - p.horizontal() - b.horizontal()
      } else {
        ctx.ih[idx] - p.vertical() - b.vertical()
      }
  }
  base = clamp0(base)
  if row {
    let cb = match main_base {
      Some(v) => v
      None => base
    }
    base = clamp_w(st, base, cb)
  }
  let cross_len = if row { st.height } else { st.width }
  let (cross_content, cross_def) = match
    resolve_len(cross_len, cross_base, st.font_size) {
    Some(v) => (v, true)
    None =>
      (
        if row {
          ctx.ih[idx] - p.vertical() - b.vertical()
        } else {
          ctx.iw[idx] - p.horizontal() - b.horizontal()
        },
        false,
      )
  }
  {
    node,
    idx,
    base,
    extra_main,
    extra_cross,
    cross_content: clamp0(cross_content),
    cross_auto: !cross_def,
    grow: st.flex_grow,
    shrink: st.flex_shrink,
  }
}

///|
fn layout_flex(
  ctx : Ctx,
  node : StyleNode,
  idx : Int32,
  cx : Double,
  cy : Double,
  cw : Double,
  ch : Double?,
) -> (Array[LayoutBox], Double) {
  let st = node.style
  let row = st.flex_direction == @style.FlexDirection::Row
  let wrap = st.flex_wrap == @style.FlexWrap::Wrap
  let main_avail : Double? = if row { Some(cw) } else { ch }
  let cross_avail : Double? = if row { ch } else { Some(cw) }
  let items : Array[FlexItem] = []
  let mut cur = idx + 1
  for c in node.children {
    let ci = cur
    cur = cur + ctx.sub[ci]
    if c.style.display != @style.Display::None {
      items.push(make_item(ctx, c, ci, row, main_avail, cross_avail))
    }
  }
  let n = items.length()
  let out : Array[LayoutBox] = []
  if n == 0 {
    (out, 0.0)
  } else {
    // 分行：只有 wrap 且有确定主轴尺寸时才分行；column 按单行处理。
    let lines : Array[Array[Int32]] = []
    let main_size = match main_avail {
      Some(v) => v
      None => 0.0
    }
    if wrap && row && some_d(main_avail) {
      let mut line : Array[Int32] = []
      let mut used = 0.0
      for i in 0..<n {
        let it = items[i]
        let add = if line.length() == 0 {
          it.base + it.extra_main
        } else {
          it.base + it.extra_main + st.gap
        }
        if line.length() > 0 && used + add > main_size + 1.0e-9 {
          lines.push(line)
          // 新建数组而不是 clear：lines 里保存的是引用。
          line = [i]
          used = it.base + it.extra_main
        } else {
          used = used + add
          line.push(i)
        }
      }
      if line.length() > 0 {
        lines.push(line)
      }
    } else {
      let all : Array[Int32] = []
      for i in 0..<n {
        all.push(i)
      }
      lines.push(all)
    }
    // 逐行分配主尺寸并放置。
    let mut cross_cursor = 0.0
    let mut column_main = 0.0
    for li in 0..<lines.length() {
      let line = lines[li]
      let ln = line.length()
      let mut sum_outer = 0.0
      let mut sum_grow = 0.0
      let mut sum_scaled = 0.0
      for k in 0..<ln {
        let it = items[line[k]]
        sum_outer = sum_outer + it.base + it.extra_main
        sum_grow = sum_grow + it.grow
        sum_scaled = sum_scaled + it.shrink * it.base
      }
      let gaps = if ln > 1 { st.gap * (ln - 1).to_double() } else { 0.0 }
      let free = match main_avail {
        Some(v) => v - sum_outer - gaps
        None => 0.0
      }
      // 按 flex_grow / flex_shrink 分配主轴尺寸。
      let finals : Array[Double] = []
      let mut used_main = 0.0
      for k in 0..<ln {
        let it = items[line[k]]
        let mut v = it.base
        if free > 0.0 {
          if sum_grow > 0.0 {
            v = v + free * it.grow / sum_grow
          }
        } else if free < 0.0 {
          if sum_scaled > 0.0 {
            v = v + free * (it.shrink * it.base) / sum_scaled
          }
        }
        v = clamp0(v)
        if row {
          v = clamp_w(it.node.style, v, cw)
        }
        finals.push(v)
        used_main = used_main + v + it.extra_main
      }
      // 行交叉尺寸：单行且交叉轴确定时取容器交叉尺寸，否则取最高子项。
      let mut line_cross = 0.0
      for k in 0..<ln {
        let it = items[line[k]]
        line_cross = max2(line_cross, it.cross_content + it.extra_cross)
      }
      if !wrap && some_d(cross_avail) {
        line_cross = match cross_avail {
          Some(v) => v
          None => line_cross
        }
      }
      // 逐项定交叉尺寸与偏移。
      let crosses : Array[Double] = []
      let offs : Array[Double] = []
      for k in 0..<ln {
        let it = items[line[k]]
        let mut ic = it.cross_content
        if st.align_items == @style.Align::Stretch && it.cross_auto {
          ic = clamp0(line_cross - it.extra_cross)
        }
        let outer_cross = ic + it.extra_cross
        let off = match st.align_items {
          @style.Align::Start => 0.0
          @style.Align::Stretch => 0.0
          @style.Align::Center => (line_cross - outer_cross) / 2.0
          @style.Align::End => line_cross - outer_cross
        }
        crosses.push(ic)
        offs.push(off)
      }
      // justify_content 的主轴起始偏移与项间额外间距。
      let leftover = match main_avail {
        Some(v) => clamp0(v - used_main - gaps)
        None => 0.0
      }
      let (leading, extra) = match st.justify_content {
        @style.Justify::Start => (0.0, 0.0)
        @style.Justify::Center => (leftover / 2.0, 0.0)
        @style.Justify::End => (leftover, 0.0)
        @style.Justify::SpaceBetween =>
          if ln > 1 {
            (0.0, leftover / (ln - 1).to_double())
          } else {
            (0.0, 0.0)
          }
        @style.Justify::SpaceAround => {
          let g = leftover / ln.to_double()
          (g / 2.0, g)
        }
        @style.Justify::SpaceEvenly => {
          let g = leftover / (ln + 1).to_double()
          (g, g)
        }
      }
      let mut cursor = leading
      for k in 0..<ln {
        let it = items[line[k]]
        let main_content = finals[k]
        let cross_content = crosses[k]
        let off = offs[k]
        let im = it.node.style.margin
        let (ix, iy) = if row {
          (cx + cursor + im.left, cy + cross_cursor + off + im.top)
        } else {
          (cx + off + im.left, cy + cursor + im.top)
        }
        let (fw, fh) = if row {
          (Some(main_content), Some(cross_content))
        } else {
          (Some(cross_content), Some(main_content))
        }
        let (box, _) = layout_node(ctx, it.node, it.idx, ix, iy, cw, ch, fw, fh)
        out.push(box)
        cursor = cursor + main_content + it.extra_main + st.gap + extra
      }
      if row {
        cross_cursor = cross_cursor + line_cross + st.gap
      } else {
        column_main = column_main + used_main + gaps
      }
    }
    let used_h = if row {
      match ch {
        Some(v) => v
        None => {
          let tail = if lines.length() > 0 { st.gap } else { 0.0 }
          clamp0(cross_cursor - tail)
        }
      }
    } else {
      match ch {
        Some(v) => v
        None => column_main
      }
    }
    (out, used_h)
  }
}

///|
// 布局一个节点：x,y 是边框盒左上角；cb 是包含块内容盒；forced_* 是父级
// （flex 分配或 stretch）定下的内容盒尺寸。
fn layout_node(
  ctx : Ctx,
  node : StyleNode,
  idx : Int32,
  x : Double,
  y : Double,
  cb_w : Double,
  cb_h : Double?,
  forced_w : Double?,
  forced_h : Double?,
) -> (LayoutBox, Double) {
  bump()
  let st = node.style
  let p = st.padding
  let b = st.border
  let m = st.margin
  match node.text {
    Some(s) => {
      let w = match forced_w {
        Some(v) => v
        None => ctx.tw[idx]
      }
      let h = match forced_h {
        Some(v) => v
        None => ctx.lh[idx]
      }
      let rect = {
        x,
        y,
        w: clamp0(w + p.horizontal() + b.horizontal()),
        h: clamp0(h + p.vertical() + b.vertical()),
      }
      // 基线取行盒高度的 0.8 处，仅为下游绘制提供一个稳定的近似值。
      let baseline = b.top + p.top + ctx.lh[idx] * 0.8
      let data = { node: idx, text: s, rect, baseline, }
      (LayoutBox::Text(data), rect.h + m.vertical())
    }
    None =>
      // display:none 不产生盒子；根节点也要返回一个零尺寸盒占位。
      if st.display == @style.Display::None {
        let empty : Array[LayoutBox] = []
        let rect = { x, y, w: 0.0, h: 0.0, }
        let data = { node: idx, rect, children: empty, }
        (LayoutBox::Box(data), 0.0)
      } else {
        let content_w = {
          let raw = match forced_w {
            Some(v) => v
            None =>
              match resolve_len(st.width, Some(cb_w), st.font_size) {
                Some(v) => v
                None => cb_w - m.horizontal() - p.horizontal() - b.horizontal()
              }
          }
          clamp_w(st, raw, cb_w)
        }
        let content_h_opt = match forced_h {
          Some(v) => Some(v)
          None => resolve_len(st.height, cb_h, st.font_size)
        }
        let cx = x + b.left + p.left
        let cy = y + b.top + p.top
        let (children, used_h) = match st.display {
          @style.Display::Flex =>
            layout_flex(ctx, node, idx, cx, cy, content_w, content_h_opt)
          @style.Display::Block =>
            layout_block(ctx, node, idx, cx, cy, content_w)
          @style.Display::None => {
            let empty : Array[LayoutBox] = []
            (empty, 0.0)
          }
        }
        let content_h = match content_h_opt {
          Some(v) => v
          None => used_h
        }
        let rect = {
          x,
          y,
          w: clamp0(content_w + p.horizontal() + b.horizontal()),
          h: clamp0(content_h + p.vertical() + b.vertical()),
        }
        let data = { node: idx, rect, children, }
        (LayoutBox::Box(data), rect.h + m.vertical())
      }
  }
}

///|
pub fn layout(
  root : StyleNode,
  width : Double,
  measure : TextMeasure,
) -> LayoutBox {
  g_visits[0] = 0
  let ctx = {
    iw: ([] : Array[Double]),
    ih: ([] : Array[Double]),
    tw: ([] : Array[Double]),
    lh: ([] : Array[Double]),
    sub: ([] : Array[Int32]),
    measure,
  }
  let _ = measure_tree(ctx, root)
  let (box, _) = layout_node(ctx, root, 0, 0.0, 0.0, width, None, None, None)
  box
}
