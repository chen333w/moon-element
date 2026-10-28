// layout 包的白盒测试：盒模型、块级流、flexbox 的精确几何。

// —— 测试辅助 ——

///|
fn near(a : Double, b : Double) -> Bool {
  let d = a - b
  let ad = if d < 0.0 { -d } else { d }
  ad < 1.0e-6
}

///|
fn assert_near(a : Double, b : Double) -> Unit raise {
  assert_true(near(a, b))
}

///|
// 确定性假测量：每字符 8px，行高 1.2 * font_size。
fn m8(s : String, fs : Double) -> (Double, Double) {
  (8.0 * s.char_length().to_double(), 1.2 * fs)
}

///|
fn base_style() -> @style.ComputedStyle {
  @style.ComputedStyle::initial()
}

///|
fn block_style() -> @style.ComputedStyle {
  base_style()
}

///|
fn flex_row(w : Double) -> @style.ComputedStyle {
  {
    ..base_style(),
    display: @style.Display::Flex,
    width: @style.Length::Px(w),
    flex_direction: @style.FlexDirection::Row,
  }
}

///|
fn flex_col(w : Double) -> @style.ComputedStyle {
  {
    ..base_style(),
    display: @style.Display::Flex,
    width: @style.Length::Px(w),
    flex_direction: @style.FlexDirection::Column,
  }
}

///|
fn elem(
  tag : String,
  style : @style.ComputedStyle,
  kids : Array[StyleNode],
) -> StyleNode {
  {
    info: { tag, id: "", classes: [], inline: [], parent: -1, },
    style,
    children: kids,
    text: None,
  }
}

///|
fn text_node(s : String) -> StyleNode {
  {
    info: { tag: "#text", id: "", classes: [], inline: [], parent: -1, },
    style: base_style(),
    children: [],
    text: Some(s),
  }
}

///|
fn item_style(
  basis : Double,
  grow : Double,
  h : Double,
) -> @style.ComputedStyle {
  {
    ..base_style(),
    flex_basis: @style.Length::Px(basis),
    flex_grow: grow,
    flex_shrink: 1.0,
    height: @style.Length::Px(h),
  }
}

///|
fn wrap_item(basis : Double, h : Double) -> @style.ComputedStyle {
  {
    ..base_style(),
    flex_basis: @style.Length::Px(basis),
    height: @style.Length::Px(h),
    flex_shrink: 1.0,
  }
}

///|
fn as_box(b : LayoutBox) -> BoxData {
  match b {
    LayoutBox::Box(d) => d
    LayoutBox::Text(_) => abort("expected a box")
  }
}

///|
fn as_text(b : LayoutBox) -> TextData {
  match b {
    LayoutBox::Text(d) => d
    LayoutBox::Box(_) => abort("expected a text box")
  }
}

///|
fn edges(v : Double) -> @style.Edges {
  @style.Edges::all(v)
}

// —— grow ——

///|
test "flex grow distributes free space by factor" {
  let kids = [
    elem("a", item_style(0.0, 1.0, 10.0), []),
    elem("b", item_style(0.0, 2.0, 10.0), []),
    elem("c", item_style(0.0, 3.0, 10.0), []),
  ]
  let root = elem("root", flex_row(300.0), kids)
  let box = as_box(layout(root, 300.0, m8))
  assert_near(box.rect.w, 300.0)
  let c0 = as_box(box.children[0])
  let c1 = as_box(box.children[1])
  let c2 = as_box(box.children[2])
  assert_near(c0.rect.x, 0.0)
  assert_near(c0.rect.w, 50.0)
  assert_near(c1.rect.x, 50.0)
  assert_near(c1.rect.w, 100.0)
  assert_near(c2.rect.x, 150.0)
  assert_near(c2.rect.w, 150.0)
}

// —— shrink ——

///|
test "flex shrink never goes negative" {
  let kids = [
    elem("a", item_style(100.0, 0.0, 10.0), []),
    elem("b", item_style(100.0, 0.0, 10.0), []),
    elem("c", item_style(100.0, 0.0, 10.0), []),
  ]
  let root = elem("root", flex_row(200.0), kids)
  let box = as_box(layout(root, 200.0, m8))
  let c0 = as_box(box.children[0])
  let c1 = as_box(box.children[1])
  let c2 = as_box(box.children[2])
  assert_near(c0.rect.w, 200.0 / 3.0)
  assert_near(c1.rect.x, 200.0 / 3.0)
  assert_near(c2.rect.x, 400.0 / 3.0)
  assert_true(c0.rect.w >= 0.0 && c1.rect.w >= 0.0 && c2.rect.w >= 0.0)
  // 极端收缩：可用空间为负也不能产出负尺寸
  let tiny = elem("root", flex_row(10.0), [
    elem("a", item_style(100.0, 0.0, 10.0), []),
    elem("b", item_style(100.0, 0.0, 10.0), []),
  ])
  let tb = as_box(layout(tiny, 10.0, m8))
  let t0 = as_box(tb.children[0])
  assert_true(t0.rect.w >= 0.0)
}

// —— gap + justify ——

///|
test "gap and justify start" {
  let s = { ..flex_row(300.0), gap: 20.0, }
  let root = elem("root", s, [
    elem("a", item_style(50.0, 0.0, 10.0), []),
    elem("b", item_style(50.0, 0.0, 10.0), []),
  ])
  let box = as_box(layout(root, 300.0, m8))
  assert_near(as_box(box.children[0]).rect.x, 0.0)
  assert_near(as_box(box.children[1]).rect.x, 70.0)
}

///|
test "gap and justify center" {
  let s = {
    ..flex_row(300.0),
    gap: 20.0,
    justify_content: @style.Justify::Center,
  }
  let root = elem("root", s, [
    elem("a", item_style(50.0, 0.0, 10.0), []),
    elem("b", item_style(50.0, 0.0, 10.0), []),
  ])
  let box = as_box(layout(root, 300.0, m8))
  assert_near(as_box(box.children[0]).rect.x, 90.0)
  assert_near(as_box(box.children[1]).rect.x, 160.0)
}

///|
test "gap and justify space-between" {
  let s = {
    ..flex_row(300.0),
    gap: 20.0,
    justify_content: @style.Justify::SpaceBetween,
  }
  let root = elem("root", s, [
    elem("a", item_style(50.0, 0.0, 10.0), []),
    elem("b", item_style(50.0, 0.0, 10.0), []),
  ])
  let box = as_box(layout(root, 300.0, m8))
  assert_near(as_box(box.children[0]).rect.x, 0.0)
  assert_near(as_box(box.children[1]).rect.x, 250.0)
}

// —— wrap ——

///|
test "wrap breaks into rows and each row takes its tallest item" {
  let s = { ..flex_row(100.0), flex_wrap: @style.FlexWrap::Wrap, }
  let root = elem("root", s, [
    elem("a", wrap_item(40.0, 10.0), []),
    elem("b", wrap_item(40.0, 20.0), []),
    elem("c", wrap_item(40.0, 30.0), []),
    elem("d", wrap_item(40.0, 40.0), []),
    elem("e", wrap_item(40.0, 50.0), []),
  ])
  let box = as_box(layout(root, 100.0, m8))
  assert_eq(box.children.length(), 5)
  let c0 = as_box(box.children[0])
  let c1 = as_box(box.children[1])
  let c2 = as_box(box.children[2])
  let c3 = as_box(box.children[3])
  let c4 = as_box(box.children[4])
  // 第一行 [a,b]：高取 20
  assert_near(c0.rect.y, 0.0)
  assert_near(c1.rect.y, 0.0)
  // 第二行 [c,d]：高取 40
  assert_near(c2.rect.y, 20.0)
  assert_near(c3.rect.y, 20.0)
  // 第三行 [e]：高取 50
  assert_near(c4.rect.y, 60.0)
  // 行内按基准宽度放置
  assert_near(c0.rect.x, 0.0)
  assert_near(c1.rect.x, 40.0)
  assert_near(c2.rect.x, 0.0)
  assert_near(box.rect.h, 110.0)
}

// —— 盒模型 ——

///|
test "padding border and margin offset the child" {
  let s = { ..block_style(), padding: edges(10.0), border: edges(5.0), }
  let child = {
    ..base_style(),
    height: @style.Length::Px(20.0),
    margin: edges(4.0),
  }
  let root = elem("root", s, [elem("a", child, []), elem("b", child, [])])
  let box = as_box(layout(root, 400.0, m8))
  // 边框盒宽 = 400；内容盒宽 = 400 - 2*(5+10)
  assert_near(box.rect.w, 400.0)
  assert_near(box.rect.h, 2.0 * 5.0 + 2.0 * 10.0 + 2.0 * (20.0 + 8.0))
  let c0 = as_box(box.children[0])
  let c1 = as_box(box.children[1])
  assert_near(c0.rect.x, 19.0)
  assert_near(c0.rect.y, 19.0)
  assert_near(c0.rect.h, 20.0)
  assert_near(c1.rect.y, 19.0 + 28.0)
}

// —— 百分比 ——

///|
test "percentage widths resolve against the containing block chain" {
  let half = { ..base_style(), width: @style.Length::Percent(50.0), }
  let inner = elem("inner", half, [])
  let outer = elem("outer", half, [inner])
  let root = elem("root", base_style(), [outer])
  let box = as_box(layout(root, 400.0, m8))
  let o = as_box(box.children[0])
  let i = as_box(o.children[0])
  assert_near(o.rect.w, 200.0)
  assert_near(i.rect.w, 100.0)
}

// —— min/max ——

///|
test "min and max width clamp the final width" {
  let maxed = {
    ..base_style(),
    width: @style.Length::Percent(50.0),
    max_width: @style.Length::Px(100.0),
  }
  let mined = {
    ..base_style(),
    width: @style.Length::Px(10.0),
    min_width: @style.Length::Px(50.0),
  }
  let root = elem("root", base_style(), [
    elem("a", maxed, []),
    elem("b", mined, []),
  ])
  let box = as_box(layout(root, 400.0, m8))
  assert_near(as_box(box.children[0]).rect.w, 100.0)
  assert_near(as_box(box.children[1]).rect.w, 50.0)
}

// —— column 主轴 ——

///|
test "column direction grows and justifies along the main axis" {
  // 容器高 200，两个 0 基准项各 grow 1 → 各 100
  let col = {
    ..flex_col(100.0),
    height: @style.Length::Px(200.0),
    flex_direction: @style.FlexDirection::Column,
  }
  let tall = {
    ..base_style(),
    flex_basis: @style.Length::Px(0.0),
    flex_grow: 1.0,
    flex_shrink: 1.0,
  }
  let root = elem("root", col, [elem("a", tall, []), elem("b", tall, [])])
  let box = as_box(layout(root, 100.0, m8))
  let a = as_box(box.children[0])
  let b = as_box(box.children[1])
  assert_near(a.rect.y, 0.0)
  assert_near(a.rect.h, 100.0)
  assert_near(b.rect.y, 100.0)
  assert_near(b.rect.h, 100.0)
  // 居中：剩余 160 平分到两侧 → 首项 y = 80
  let centred = {
    ..flex_col(100.0),
    height: @style.Length::Px(200.0),
    flex_direction: @style.FlexDirection::Column,
    justify_content: @style.Justify::Center,
  }
  let fixed = {
    ..base_style(),
    flex_basis: @style.Length::Px(20.0),
    flex_grow: 0.0,
    flex_shrink: 0.0,
  }
  let root2 = elem("root", centred, [elem("a", fixed, []), elem("b", fixed, [])])
  let b2 = as_box(layout(root2, 100.0, m8))
  assert_near(as_box(b2.children[0]).rect.y, 80.0)
  assert_near(as_box(b2.children[1]).rect.y, 100.0)
}

// —— align_items ——

///|
test "align items positions the cross axis" {
  let mk = fn(y : @style.Align) -> Double {
    let s = {
      ..flex_row(300.0),
      height: @style.Length::Px(100.0),
      align_items: y,
    }
    let child = {
      ..base_style(),
      flex_basis: @style.Length::Px(50.0),
      height: @style.Length::Px(20.0),
      flex_grow: 0.0,
      flex_shrink: 0.0,
    }
    let root = elem("root", s, [elem("a", child, [])])
    let box = as_box(layout(root, 300.0, m8))
    as_box(box.children[0]).rect.y
  }
  assert_near(mk(@style.Align::Start), 0.0)
  assert_near(mk(@style.Align::Center), 40.0)
  assert_near(mk(@style.Align::End), 80.0)
  // stretch：子项没有显式高度时填满行高
  let s = { ..flex_row(300.0), height: @style.Length::Px(100.0), }
  let child = {
    ..base_style(),
    flex_basis: @style.Length::Px(50.0),
    flex_grow: 0.0,
    flex_shrink: 0.0,
  }
  let root = elem("root", s, [elem("a", child, [])])
  let box = as_box(layout(root, 300.0, m8))
  assert_near(as_box(box.children[0]).rect.h, 100.0)
}

// —— 嵌套 flex ——

///|
test "nested flex lays a column inside a row" {
  let col = { ..flex_col(100.0), flex_basis: @style.Length::Px(100.0), }
  let col_node = elem("col", col, [text_node("ab"), text_node("cd")])
  let right = { ..base_style(), flex_basis: @style.Length::Px(200.0), }
  let root = elem("root", flex_row(300.0), [col_node, elem("right", right, [])])
  let box = as_box(layout(root, 300.0, m8))
  let c = as_box(box.children[0])
  assert_near(c.rect.x, 0.0)
  assert_near(c.rect.w, 100.0)
  assert_eq(c.children.length(), 2)
  let t0 = as_text(c.children[0])
  let t1 = as_text(c.children[1])
  // 列方向：子项自上而下堆叠，行高 1.2*16
  assert_near(t0.rect.y, 0.0)
  assert_near(t0.rect.h, 19.2)
  assert_near(t1.rect.y, 19.2)
  // 交叉轴 stretch 到列宽 100
  assert_near(t0.rect.w, 100.0)
  let r = as_box(box.children[1])
  assert_near(r.rect.x, 100.0)
  assert_near(r.rect.w, 200.0)
}

// —— 文本 ——

///|
test "text box width comes from the injected measure" {
  let root = elem("root", base_style(), [text_node("abcd")])
  let box = as_box(layout(root, 100.0, m8))
  let t = as_text(box.children[0])
  assert_near(t.rect.x, 0.0)
  assert_near(t.rect.w, 32.0)
  assert_near(t.rect.h, 19.2)
  assert_near(t.baseline, 19.2 * 0.8)
  assert_eq(t.text, "abcd")
  assert_near(box.rect.h, 19.2)
}

// —— display:none ——

///|
test "display none subtree produces no boxes but keeps indices" {
  let hidden = { ..base_style(), display: @style.Display::None, }
  let h = elem("h", hidden, [elem("hh", base_style(), [])])
  let root = elem("root", base_style(), [
    elem("a", { ..base_style(), height: @style.Length::Px(10.0), }, []),
    h,
    elem("c", { ..base_style(), height: @style.Length::Px(10.0), }, []),
  ])
  let lb = layout(root, 100.0, m8)
  // root + a + c
  assert_eq(lb.count(), 3)
  // 前序下标：root=0, a=1, h=2, hh=3, c=4
  assert_true(lb.find(4) is Some(_))
  assert_true(lb.find(2) is None)
  assert_true(lb.find(3) is None)
  let box = as_box(lb)
  let c = as_box(box.children[1])
  assert_near(c.rect.y, 10.0)
  assert_near(box.rect.h, 20.0)
}

// —— 根节点 display:none ——

///|
test "a hidden root still yields one zero-sized box" {
  let hidden = { ..base_style(), display: @style.Display::None, }
  let root = elem("root", hidden, [elem("a", base_style(), [])])
  let lb = layout(root, 100.0, m8)
  assert_eq(lb.count(), 1)
  let b = as_box(lb)
  assert_eq(b.children.length(), 0)
  assert_near(b.rect.w, 0.0)
  assert_near(b.rect.h, 0.0)
  assert_true(lb.find(1) is None)
}

// —— find / count ——

///|
test "find returns rectangles and none for unknown nodes" {
  let root = elem("root", base_style(), [
    elem("a", { ..base_style(), height: @style.Length::Px(10.0), }, []),
    text_node("x"),
  ])
  let box = layout(root, 100.0, m8)
  assert_eq(box.count(), 3)
  match box.find(0) {
    Some(r) => assert_near(r.w, 100.0)
    None => abort("root must be found")
  }
  match box.find(2) {
    Some(r) => assert_near(r.w, 8.0)
    None => abort("text must be found")
  }
  assert_true(box.find(99) is None)
}

// —— 复杂度 ——

///|
test "layout visit count stays linear in the node count" {
  let kids : Array[StyleNode] = []
  for i in 0..<20 {
    let _ = i
    kids.push(elem("k", item_style(10.0, 1.0, 5.0), [text_node("ab")]))
  }
  let root = elem("root", flex_row(400.0), kids)
  let box = layout(root, 400.0, m8)
  let nodes = box.count()
  assert_eq(nodes, 41) // root + 20 个项 + 20 段文本
  let visits = layout_visit_count()
  assert_true(visits <= 4 * nodes)
  assert_true(visits > 0)
}

// —— 确定性 ——

///|
test "two layouts of the same tree agree" {
  let root = elem("root", flex_row(300.0), [
    elem("a", item_style(0.0, 1.0, 10.0), [text_node("hi")]),
    elem("b", item_style(0.0, 2.0, 20.0), []),
  ])
  let b1 = as_box(layout(root, 300.0, m8))
  let b2 = as_box(layout(root, 300.0, m8))
  assert_near(b1.rect.w, b2.rect.w)
  assert_near(b1.rect.h, b2.rect.h)
  assert_eq(b1.children.length(), b2.children.length())
  let c1 = as_box(b1.children[0])
  let c2 = as_box(b2.children[0])
  assert_near(c1.rect.x, c2.rect.x)
  assert_near(c1.rect.y, c2.rect.y)
}
