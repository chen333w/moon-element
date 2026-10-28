// 随机树的不变量测试：无负尺寸、盒子数正确、前序下标一致、两次布局一致、线性访问。

// —— 简易确定性 PRNG（不用标准库，保证可复现）——

///|
priv struct Rng {
  s : Array[Int32]
}

///|
fn rng(seed : Int32) -> Rng {
  { s: [seed], }
}

///|
fn rnd(r : Rng) -> Int32 {
  r.s[0] = (r.s[0] * 37 + 11) % 1009
  r.s[0]
}

///|
fn pick(r : Rng, n : Int32) -> Int32 {
  let v = rnd(r) % n
  if v < 0 {
    -v
  } else {
    v
  }
}

///|
fn pick_px(r : Rng, lo : Int32, hi : Int32) -> @style.Length {
  @style.Length::Px((lo + pick(r, hi - lo + 1)).to_double())
}

///|
fn pick_pad(r : Rng) -> @style.Edges {
  @style.Edges::all(pick(r, 7).to_double())
}

///|
// 随机样式：尺寸取 Auto/Px/Percent 混合，避免所有框都退化。
fn rand_style(r : Rng) -> @style.ComputedStyle {
  let mut st = base_style()
  let display = pick(r, 100)
  if display < 5 {
    st = { ..st, display: @style.Display::None, }
  } else if display < 30 {
    st = { ..st, display: @style.Display::Flex, }
    if pick(r, 2) == 0 {
      st = { ..st, flex_direction: @style.FlexDirection::Column, }
    }
    if pick(r, 100) < 40 {
      st = { ..st, flex_wrap: @style.FlexWrap::Wrap, }
    }
    st = { ..st, gap: pick(r, 5).to_double() * 3.0, }
    st = {
      ..st,
      justify_content: match pick(r, 6) {
        0 => @style.Justify::Start
        1 => @style.Justify::Center
        2 => @style.Justify::End
        3 => @style.Justify::SpaceBetween
        4 => @style.Justify::SpaceAround
        _ => @style.Justify::SpaceEvenly
      },
      align_items: match pick(r, 4) {
        0 => @style.Align::Stretch
        1 => @style.Align::Start
        2 => @style.Align::Center
        _ => @style.Align::End
      },
    }
  }
  st = {
    ..st,
    padding: pick_pad(r),
    border: @style.Edges::all(pick(r, 4).to_double()),
    margin: @style.Edges::all(pick(r, 6).to_double()),
  }
  let w = pick(r, 10)
  if w < 2 {
    st = { ..st, width: pick_px(r, 20, 120), }
  } else if w < 4 {
    st = {
      ..st,
      width: @style.Length::Percent((10 + pick(r, 91)).to_double()),
    }
  }
  if pick(r, 10) < 3 {
    st = { ..st, height: pick_px(r, 5, 60), }
  }
  if pick(r, 10) < 2 {
    st = { ..st, min_width: pick_px(r, 10, 40), }
  }
  if pick(r, 10) < 2 {
    st = { ..st, max_width: pick_px(r, 50, 150), }
  }
  st = {
    ..st,
    flex_grow: pick(r, 4).to_double(),
    flex_shrink: pick(r, 3).to_double(),
    flex_basis: if pick(r, 10) < 4 {
      pick_px(r, 10, 80)
    } else {
      @style.Length::Auto
    },
  }
  st
}

///|
// 根节点必须产出盒子（即使 display:none 也返回一个零尺寸盒），
// 所以随机树里把根的 display 归一化为可见。
fn normalize_root(n : StyleNode) -> StyleNode {
  match n.text {
    Some(_) => n
    None =>
      if n.style.display == @style.Display::None {
        { ..n, style: { ..n.style, display: @style.Display::Block, }, }
      } else {
        n
      }
  }
}

///|
fn repeat_x(n : Int32) -> String {
  let mut s = ""
  let mut i = 0
  while i < n {
    s = s + "x"
    i = i + 1
  }
  s
}

///|
fn rand_leaf(r : Rng, st : @style.ComputedStyle) -> StyleNode {
  if pick(r, 2) == 0 {
    {
      info: { tag: "#text", id: "", classes: [], inline: [], parent: -1, },
      style: st,
      children: [],
      text: Some(repeat_x(pick(r, 6))),
    }
  } else {
    elem("leaf", st, [])
  }
}

///|
// 随机树：深度 ≤ 4，每层 ≤ 5 个子节点。
fn rand_tree(r : Rng, depth : Int32) -> StyleNode {
  let st = rand_style(r)
  if depth >= 4 || pick(r, 100) < 25 {
    rand_leaf(r, st)
  } else {
    let k = pick(r, 6)
    let kids : Array[StyleNode] = []
    for i in 0..<k {
      let _ = i
      kids.push(rand_tree(r, depth + 1))
    }
    elem("n", st, kids)
  }
}

// —— 不变量检查 ——

///|
fn rect_of(b : LayoutBox) -> Rect {
  match b {
    LayoutBox::Box(d) => d.rect
    LayoutBox::Text(d) => d.rect
  }
}

///|
// 尺寸必须非负；坐标允许为负（溢出时居中/靠尾对齐会把子项推到起点之外）。
fn usable_size(v : Double) -> Bool {
  v >= 0.0 && finite(v)
}

///|
fn finite(v : Double) -> Bool {
  v == v && v > -1.0e9 && v < 1.0e9
}

///|
fn check_sizes(b : LayoutBox, bad : Array[Int32]) -> Unit {
  match b {
    LayoutBox::Box(d) => {
      if !(usable_size(d.rect.w) && usable_size(d.rect.h)) {
        bad[0] = bad[0] + 1
      }
      if !(finite(d.rect.x) && finite(d.rect.y)) {
        bad[0] = bad[0] + 1
      }
      for c in d.children {
        check_sizes(c, bad)
      }
    }
    LayoutBox::Text(d) =>
      if !(usable_size(d.rect.w) && usable_size(d.rect.h) && finite(d.baseline)) {
        bad[0] = bad[0] + 1
      }
  }
}

///|
fn collect_boxes(b : LayoutBox, out : Array[Int32]) -> Unit {
  match b {
    LayoutBox::Box(d) => {
      out.push(d.node)
      for c in d.children {
        collect_boxes(c, out)
      }
    }
    LayoutBox::Text(d) => out.push(d.node)
  }
}

///|
// 独立走一遍输入树，按前序给出可见节点的下标。
// 祖先 display:none 时整棵子树都不产生盒子，所以 hidden 要往下传。
fn collect_visible(
  n : StyleNode,
  ctr : Array[Int32],
  out : Array[Int32],
  inherited_hidden : Bool,
) -> Unit {
  let idx = ctr[0]
  ctr[0] = ctr[0] + 1
  let hidden = inherited_hidden || n.style.display == @style.Display::None
  match n.text {
    Some(_) => if !hidden { out.push(idx) }
    None => {
      if !hidden {
        out.push(idx)
      }
      for c in n.children {
        collect_visible(c, ctr, out, hidden)
      }
    }
  }
}

///|
fn count_all(n : StyleNode) -> Int32 {
  match n.text {
    Some(_) => 1
    None => {
      let mut t = 1
      for c in n.children {
        t = t + count_all(c)
      }
      t
    }
  }
}

///|
fn same(a : LayoutBox, b : LayoutBox) -> Bool {
  match (a, b) {
    (LayoutBox::Box(x), LayoutBox::Box(y)) => {
      let n = x.children.length()
      if x.node != y.node || n != y.children.length() {
        false
      } else if !(near(x.rect.x, y.rect.x) &&
        near(x.rect.y, y.rect.y) &&
        near(x.rect.w, y.rect.w) &&
        near(x.rect.h, y.rect.h)) {
        false
      } else {
        let mut ok = true
        for i in 0..<n {
          if ok && !same(x.children[i], y.children[i]) {
            ok = false
          }
        }
        ok
      }
    }
    (LayoutBox::Text(x), LayoutBox::Text(y)) =>
      x.node == y.node &&
      x.text == y.text &&
      near(x.rect.x, y.rect.x) &&
      near(x.rect.y, y.rect.y) &&
      near(x.rect.w, y.rect.w) &&
      near(x.rect.h, y.rect.h) &&
      near(x.baseline, y.baseline)
    _ => false
  }
}

// —— 测试 ——

///|
test "random trees keep their invariants" {
  for seed in 0..<100 {
    let r = rng(seed + 1)
    let root = normalize_root(rand_tree(r, 0))
    let b1 = layout(root, 300.0, m8)
    let visits = layout_visit_count()
    let b2 = layout(root, 300.0, m8)
    // 尺寸非负、非 NaN
    let bad : Array[Int32] = [0]
    check_sizes(b1, bad)
    assert_eq(bad[0], 0)
    // 盒子数 == 可见节点数
    let ctr : Array[Int32] = [0]
    let visible : Array[Int32] = []
    collect_visible(root, ctr, visible, false)
    assert_eq(b1.count(), visible.length())
    assert_true(b1.count() > 0)
    // 前序下标与输入树一致
    let ids : Array[Int32] = []
    collect_boxes(b1, ids)
    assert_eq(ids.length(), visible.length())
    for i in 0..<ids.length() {
      assert_eq(ids[i], visible[i])
      assert_true(b1.find(visible[i]) is Some(_))
    }
    // 两次布局逐字段相等
    assert_true(same(b1, b2))
    // 访问次数线性
    assert_true(visits <= 4 * count_all(root))
  }
}

///|
// 内容放得下时，子盒必须落在父的内容盒内。
fn assert_contained(node : StyleNode, box : LayoutBox) -> Unit raise {
  match box {
    LayoutBox::Box(d) => {
      let p = node.style.padding
      let b = node.style.border
      let cx = d.rect.x + b.left + p.left
      let cy = d.rect.y + b.top + p.top
      let cw = d.rect.w - p.horizontal() - b.horizontal()
      let ch = d.rect.h - p.vertical() - b.vertical()
      let mut i = 0
      for c in node.children {
        if c.style.display != @style.Display::None {
          let cb = d.children[i]
          i = i + 1
          let r = rect_of(cb)
          assert_true(r.x >= cx - 1.0e-6)
          assert_true(r.y >= cy - 1.0e-6)
          assert_true(r.x + r.w <= cx + cw + 1.0e-6)
          assert_true(r.y + r.h <= cy + ch + 1.0e-6)
          assert_contained(c, cb)
        }
      }
    }
    LayoutBox::Text(_) => ()
  }
}

///|
test "children stay inside the parent content box when content fits" {
  // 外层块：padding 10、border 5、宽 400
  let outer = {
    ..base_style(),
    padding: @style.Edges::all(10.0),
    border: @style.Edges::all(5.0),
  }
  // 内层 flex row：宽 300，三个 100 宽的项，正好填满
  let inner_s = {
    ..base_style(),
    display: @style.Display::Flex,
    width: @style.Length::Px(300.0),
    padding: @style.Edges::all(4.0),
  }
  let item = {
    ..base_style(),
    flex_basis: @style.Length::Px(100.0),
    flex_grow: 0.0,
    flex_shrink: 1.0,
    height: @style.Length::Px(20.0),
  }
  let inner = elem("inner", inner_s, [
    elem("a", item, [text_node("hi")]),
    elem("b", item, []),
    elem("c", item, []),
  ])
  let root = elem("root", outer, [inner])
  let lb = layout(root, 400.0, m8)
  assert_contained(root, lb)
}
