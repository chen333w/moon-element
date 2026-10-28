// style 包的黑盒测试：只通过公开 API 断言，覆盖层叠、简写、继承与畸形输入。

// ---------------------------------------------------------------- 断言辅助

///|
/// 固定三位小数：不依赖 Double::to_string，跨后端输出稳定。
fn fmt3(x : Double) -> String {
  let scaled = x * 1000.0
  let rounded : Int32 = if scaled >= 0.0 {
    (scaled + 0.5).to_int()
  } else {
    (scaled - 0.5).to_int()
  }
  let neg = rounded < 0
  let mag = if neg { -rounded } else { rounded }
  let whole = mag / 1000
  let frac = mag % 1000
  let sign = if neg { "-" } else { "" }
  let frac_text = if frac < 10 {
    "00" + frac.to_string()
  } else if frac < 100 {
    "0" + frac.to_string()
  } else {
    frac.to_string()
  }
  sign + whole.to_string() + "." + frac_text
}

///|
fn color_key(c : @style.Rgba) -> String {
  c.r.to_string() +
  "," +
  c.g.to_string() +
  "," +
  c.b.to_string() +
  "," +
  fmt3(c.a)
}

///|
fn edges_key(e : @style.Edges) -> String {
  fmt3(e.top) + "/" + fmt3(e.right) + "/" + fmt3(e.bottom) + "/" + fmt3(e.left)
}

///|
fn len_key(l : @style.Length) -> String {
  match l {
    Px(v) => "px:" + fmt3(v)
    Percent(v) => "%:" + fmt3(v)
    Em(v) => "em:" + fmt3(v)
    Rem(v) => "rem:" + fmt3(v)
    Auto => "auto"
  }
}

///|
fn node(
  tag : String,
  id : String,
  classes : Array[String],
  inline_pairs : Array[(String, String)],
  parent : Int32,
) -> @style.ElementInfo {
  { tag, id, classes, inline: inline_pairs, parent, }
}

///|
fn plain(
  tag : String,
  classes : Array[String],
  parent : Int32,
) -> @style.ElementInfo {
  node(tag, "", classes, [], parent)
}

///|
/// 用单个节点跑一份 CSS。节点带齐用例里出现的 class，
/// 这样每条用例只需要关心 CSS 本身。
fn only(css : String) -> @style.ComputedStyle {
  let classes = [
    "a", "b", "c", "f", "g", "i", "k", "m", "p1", "p2", "p3", "p4", "r", "u", "x",
  ]
  let sheet = @style.Stylesheet::parse(css)
  let nodes : Array[@style.ElementInfo] = [node("div", "i", classes, [], -1)]
  sheet.compute(nodes)[0]
}

// ---------------------------------------------------------------- 层叠

///|
test "cascade: id beats class beats tag" {
  let css = "#x { color: red } .a { color: blue } div { color: green }"
  let nodes : Array[@style.ElementInfo] = [node("div", "x", ["a"], [], -1)]
  let sheet = @style.Stylesheet::parse(css)
  assert_eq(color_key(sheet.compute(nodes)[0].color), "255,0,0,1.000")
  // 去掉 id 后 .a 赢
  let no_id : Array[@style.ElementInfo] = [node("div", "", ["a"], [], -1)]
  assert_eq(color_key(sheet.compute(no_id)[0].color), "0,0,255,1.000")
  // 只有 tag 匹配
  let bare : Array[@style.ElementInfo] = [node("div", "", [], [], -1)]
  assert_eq(color_key(sheet.compute(bare)[0].color), "0,128,0,1.000")
}

///|
test "cascade: compound selector beats a single class" {
  let css = ".a { color: red } div.a { color: blue }"
  let nodes : Array[@style.ElementInfo] = [plain("div", ["a"], -1)]
  let sheet = @style.Stylesheet::parse(css)
  assert_eq(color_key(sheet.compute(nodes)[0].color), "0,0,255,1.000")
}

///|
test "cascade: important beats higher specificity" {
  let css = "#x { color: red } .a { color: blue !important }"
  let nodes : Array[@style.ElementInfo] = [node("div", "x", ["a"], [], -1)]
  let sheet = @style.Stylesheet::parse(css)
  assert_eq(color_key(sheet.compute(nodes)[0].color), "0,0,255,1.000")
}

///|
test "cascade: later rule wins at equal specificity" {
  let css = ".a { color: red } .a { color: blue }"
  assert_eq(color_key(only(css).color), "0,0,255,1.000")
  // important 之间同样按源顺序
  let css2 = ".a { color: red !important } .a { color: blue !important }"
  assert_eq(color_key(only(css2).color), "0,0,255,1.000")
}

///|
test "cascade: inline style beats a class rule" {
  let css = ".a { color: red }"
  let nodes : Array[@style.ElementInfo] = [
    node("div", "", ["a"], [("color", "blue")], -1),
  ]
  let sheet = @style.Stylesheet::parse(css)
  assert_eq(color_key(sheet.compute(nodes)[0].color), "0,0,255,1.000")
}

///|
test "cascade: important rule beats a normal inline style" {
  let css = ".a { color: red !important }"
  let nodes : Array[@style.ElementInfo] = [
    node("div", "", ["a"], [("color", "blue")], -1),
  ]
  let sheet = @style.Stylesheet::parse(css)
  assert_eq(color_key(sheet.compute(nodes)[0].color), "255,0,0,1.000")
}

///|
test "cascade: important inline style beats an important rule" {
  let css = ".a { color: red !important }"
  let nodes : Array[@style.ElementInfo] = [
    node("div", "", ["a"], [("color", "blue !important")], -1),
  ]
  let sheet = @style.Stylesheet::parse(css)
  assert_eq(color_key(sheet.compute(nodes)[0].color), "0,0,255,1.000")
}

// ---------------------------------------------------------------- 选择器

///|
test "selector: universal matches every node" {
  let css = "* { padding-top: 4px }"
  let nodes : Array[@style.ElementInfo] = [
    plain("div", [], -1),
    plain("span", [], 0),
    plain("em", [], 1),
  ]
  let sheet = @style.Stylesheet::parse(css)
  let out = sheet.compute(nodes)
  assert_eq(fmt3(out[0].padding.top), "4.000")
  assert_eq(fmt3(out[1].padding.top), "4.000")
  assert_eq(fmt3(out[2].padding.top), "4.000")
}

///|
test "selector: descendant and child combinators differ" {
  // 0 div > 1 span.mid > 2 em.leaf；3 em.leaf 是 div 的直接子节点
  let nodes : Array[@style.ElementInfo] = [
    plain("div", [], -1),
    plain("span", ["mid"], 0),
    plain("em", ["leaf"], 1),
    plain("em", ["leaf"], 0),
  ]
  let css = "div .leaf { padding-top: 2px } div > .leaf { padding-bottom: 3px }"
  let sheet = @style.Stylesheet::parse(css)
  let out = sheet.compute(nodes)
  // 后代选择器命中两层深的节点
  assert_eq(fmt3(out[2].padding.top), "2.000")
  // 子代选择器不命中孙子节点
  assert_eq(fmt3(out[2].padding.bottom), "0.000")
  // 直接子节点两个都命中
  assert_eq(fmt3(out[3].padding.top), "2.000")
  assert_eq(fmt3(out[3].padding.bottom), "3.000")
  // div 自己不命中
  assert_eq(fmt3(out[0].padding.top), "0.000")
}

///|
test "selector: selector list applies to each selector" {
  let css = "div, .a { padding-top: 5px }"
  let nodes : Array[@style.ElementInfo] = [
    plain("div", [], -1),
    plain("span", ["a"], 0),
    plain("span", [], 0),
  ]
  let sheet = @style.Stylesheet::parse(css)
  let out = sheet.compute(nodes)
  assert_eq(fmt3(out[0].padding.top), "5.000")
  assert_eq(fmt3(out[1].padding.top), "5.000")
  assert_eq(fmt3(out[2].padding.top), "0.000")
}

///|
test "selector: unsupported pseudo-class rule is dropped whole" {
  let css = ".a:hover { color: red } .b { color: blue }"
  let nodes : Array[@style.ElementInfo] = [plain("div", ["a", "b"], -1)]
  let sheet = @style.Stylesheet::parse(css)
  assert_eq(sheet.rule_count(), 1)
  assert_true(sheet.warnings().length() > 0)
  assert_eq(color_key(sheet.compute(nodes)[0].color), "0,0,255,1.000")
}

// ---------------------------------------------------------------- 简写

///|
test "shorthand: padding one to four values" {
  let css = ".p1 { padding: 1px } .p2 { padding: 1px 2px } .p3 { padding: 1px 2px 3px } .p4 { padding: 1px 2px 3px 4px }"
  let sheet = @style.Stylesheet::parse(css)
  let nodes : Array[@style.ElementInfo] = [
    plain("div", ["p1"], -1),
    plain("div", ["p2"], -1),
    plain("div", ["p3"], -1),
    plain("div", ["p4"], -1),
  ]
  let out = sheet.compute(nodes)
  assert_eq(edges_key(out[0].padding), "1.000/1.000/1.000/1.000")
  assert_eq(edges_key(out[1].padding), "1.000/2.000/1.000/2.000")
  assert_eq(edges_key(out[2].padding), "1.000/2.000/3.000/2.000")
  assert_eq(edges_key(out[3].padding), "1.000/2.000/3.000/4.000")
}

///|
test "shorthand: margin three values" {
  let css = ".m { margin: 1px 2px 3px }"
  let nodes : Array[@style.ElementInfo] = [plain("div", ["m"], -1)]
  let sheet = @style.Stylesheet::parse(css)
  assert_eq(
    edges_key(sheet.compute(nodes)[0].margin),
    "1.000/2.000/3.000/2.000",
  )
}

///|
test "shorthand: border sets width and color" {
  let css = ".b { border: 2px solid red }"
  let nodes : Array[@style.ElementInfo] = [plain("div", ["b"], -1)]
  let sheet = @style.Stylesheet::parse(css)
  let s = sheet.compute(nodes)[0]
  assert_eq(edges_key(s.border), "2.000/2.000/2.000/2.000")
  assert_eq(color_key(s.border_color), "255,0,0,1.000")
  // 只给宽度时颜色回落到 currentColor（即自身 color）
  let s2 = only(".b { border: 1px; color: green }")
  assert_eq(edges_key(s2.border), "1.000/1.000/1.000/1.000")
  assert_eq(color_key(s2.border_color), "0,128,0,1.000")
  // 默认没有边框
  let s3 = only("div { }")
  assert_eq(edges_key(s3.border), "0.000/0.000/0.000/0.000")
  assert_eq(color_key(s3.border_color), "0,0,0,0.000")
}

///|
test "shorthand: flex single value expands to grow 1" {
  let s = only(".f { flex: 1 }")
  assert_eq(fmt3(s.flex_grow), "1.000")
  assert_eq(fmt3(s.flex_shrink), "1.000")
  assert_eq(len_key(s.flex_basis), "px:0.000")
}

///|
test "shorthand: flex three values" {
  let s = only(".f { flex: 2 3 10px }")
  assert_eq(fmt3(s.flex_grow), "2.000")
  assert_eq(fmt3(s.flex_shrink), "3.000")
  assert_eq(len_key(s.flex_basis), "px:10.000")
  // 单值长度：grow 取 1
  let s2 = only(".f { flex: 20px }")
  assert_eq(fmt3(s2.flex_grow), "1.000")
  assert_eq(len_key(s2.flex_basis), "px:20.000")
}

///|
test "shorthand: gap background and font" {
  let s = only(".g { gap: 8px; background: #00ff00; font: 14px serif }")
  assert_eq(fmt3(s.gap), "8.000")
  assert_eq(color_key(s.background_color), "0,255,0,1.000")
  assert_eq(fmt3(s.font_size), "14.000")
}

// ---------------------------------------------------------------- 继承与计算

///|
test "inheritance: color and font-size inherit down the chain" {
  // 0 .r > 1 .c > 2 .g
  let nodes : Array[@style.ElementInfo] = [
    plain("div", ["r"], -1),
    plain("div", ["c"], 0),
    plain("div", ["g"], 1),
  ]
  let css = ".r { color: blue; font-size: 20px }"
  let sheet = @style.Stylesheet::parse(css)
  let out = sheet.compute(nodes)
  assert_eq(color_key(out[1].color), "0,0,255,1.000")
  assert_eq(fmt3(out[1].font_size), "20.000")
  assert_eq(color_key(out[2].color), "0,0,255,1.000")
  assert_eq(fmt3(out[2].font_size), "20.000")
}

///|
test "inheritance: em is relative to the parent font-size" {
  let nodes : Array[@style.ElementInfo] = [
    plain("div", ["r"], -1),
    plain("div", ["c"], 0),
    plain("div", ["g"], 1),
  ]
  let css = ".r { font-size: 20px } .c { font-size: 1.5em } .g { font-size: 2em }"
  let sheet = @style.Stylesheet::parse(css)
  let out = sheet.compute(nodes)
  assert_eq(fmt3(out[1].font_size), "30.000")
  assert_eq(fmt3(out[2].font_size), "60.000")
}

///|
test "inheritance: rem is relative to 16" {
  let s = only(".c { font-size: 1.5rem }")
  assert_eq(fmt3(s.font_size), "24.000")
  // em 用自身字号解析 padding；在根节点上与 rem 不同的基准
  let s2 = only(".c { font-size: 20px; border-radius: 1em }")
  assert_eq(fmt3(s2.border_radius), "20.000")
}

///|
test "inheritance: non-inherited properties use initial values" {
  let nodes : Array[@style.ElementInfo] = [
    plain("div", ["r"], -1),
    plain("div", ["c"], 0),
  ]
  let css = ".r { padding: 5px; margin: 7px; display: flex; flex-grow: 2 }"
  let sheet = @style.Stylesheet::parse(css)
  let out = sheet.compute(nodes)
  assert_eq(edges_key(out[0].padding), "5.000/5.000/5.000/5.000")
  assert_eq(edges_key(out[1].padding), "0.000/0.000/0.000/0.000")
  assert_eq(edges_key(out[1].margin), "0.000/0.000/0.000/0.000")
  assert_true(out[1].display == @style.Display::Block)
  assert_eq(fmt3(out[1].flex_grow), "0.000")
}

///|
test "value: units px em rem percent and unitless zero" {
  let s = only(
    ".u { width: 50%; height: 2em; min-width: 10px; max-width: 3rem; gap: 0 }",
  )
  assert_eq(len_key(s.width), "%:50.000")
  assert_eq(len_key(s.height), "em:2.000")
  assert_eq(len_key(s.min_width), "px:10.000")
  assert_eq(len_key(s.max_width), "rem:3.000")
  assert_eq(fmt3(s.gap), "0.000")
  // 无单位只允许 0
  let bad = @style.Stylesheet::parse(".u { width: 12 }")
  assert_true(bad.warnings().length() > 0)
  assert_eq(len_key(bad.compute([plain("div", ["u"], -1)])[0].width), "auto")
}

///|
test "value: colors hex rgb named and currentColor" {
  assert_eq(color_key(only(".c { color: #f00 }").color), "255,0,0,1.000")
  assert_eq(color_key(only(".c { color: #00ff00 }").color), "0,255,0,1.000")
  assert_eq(color_key(only(".c { color: rgb(1, 2, 3) }").color), "1,2,3,1.000")
  assert_eq(color_key(only(".c { color: gray }").color), "128,128,128,1.000")
  assert_eq(color_key(only(".c { color: transparent }").color), "0,0,0,0.000")
  // currentColor 取自身 color
  let s = only(".c { color: red; border-color: currentColor }")
  assert_eq(color_key(s.border_color), "255,0,0,1.000")
}

///|
test "value: display flex direction wrap justify align keywords" {
  let s = only(
    ".c { display: flex; flex-direction: column; flex-wrap: wrap; justify-content: space-between; align-items: center }",
  )
  assert_true(s.display == @style.Display::Flex)
  assert_true(s.flex_direction == @style.FlexDirection::Column)
  assert_true(s.flex_wrap == @style.FlexWrap::Wrap)
  assert_true(s.justify_content == @style.Justify::SpaceBetween)
  assert_true(s.align_items == @style.Align::Center)
  // 默认值来自 initial
  let d = only("div { }")
  assert_true(d.display == @style.Display::Block)
  assert_true(d.flex_direction == @style.FlexDirection::Row)
  assert_true(d.align_items == @style.Align::Stretch)
}

// ---------------------------------------------------------------- 畸形输入

///|
test "malformed css does not panic and reports warnings" {
  let cases = [
    "{{{", ".a {", "color: ;", "a { color: #zzz }", "a { color red }", "a { padding: nope }",
    "@media (min-width: 1px) { a { color: red } }", "a[href] { color: red }", ".a:hover { color: red }",
    "/* 未闭合注释", "a > { color: red }", "a { }", "}", ";", "a { color: red",
  ]
  let nodes : Array[@style.ElementInfo] = [plain("a", [], -1)]
  for css in cases {
    let sheet = @style.Stylesheet::parse(css)
    let out = sheet.compute(nodes)
    assert_eq(out.length(), 1)
    assert_true(sheet.warnings().length() > 0)
  }
}

///|
test "invalid value falls back to initial" {
  let sheet = @style.Stylesheet::parse("a { color: #zzz }")
  assert_true(sheet.warnings().length() > 0)
  let out = sheet.compute([plain("a", [], -1)])
  assert_eq(color_key(out[0].color), "0,0,0,1.000")
  // 同一规则里的合法声明仍然生效
  let sheet2 = @style.Stylesheet::parse("a { color: #zzz; padding: 3px }")
  let out2 = sheet2.compute([plain("a", [], -1)])
  assert_eq(edges_key(out2[0].padding), "3.000/3.000/3.000/3.000")
}

///|
test "empty css yields no rules and no warnings" {
  let sheet = @style.Stylesheet::parse("")
  assert_eq(sheet.rule_count(), 0)
  assert_eq(sheet.warnings().length(), 0)
  let out = sheet.compute([plain("div", [], -1)])
  assert_eq(out.length(), 1)
  assert_true(out[0].display == @style.Display::Block)
}

///|
test "rule_count counts only usable rules" {
  let css = "a { color: red } b { color: blue } .bad:hover { color: red } a { }"
  let sheet = @style.Stylesheet::parse(css)
  assert_eq(sheet.rule_count(), 2)
  assert_true(sheet.warnings().length() > 0)
}

///|
test "compute: empty input and repeated calls are stable" {
  let sheet = @style.Stylesheet::parse(".a { padding: 1px }")
  let empty : Array[@style.ElementInfo] = []
  assert_eq(sheet.compute(empty).length(), 0)
  let nodes : Array[@style.ElementInfo] = [plain("div", ["a"], -1)]
  let first = sheet.compute(nodes)
  let second = sheet.compute(nodes)
  assert_eq(edges_key(first[0].padding), edges_key(second[0].padding))
}

// ---------------------------------------------------------------- 随机属性测试

///|
/// 线性同余，参数固定所以失败可复现。
fn next_rand(seed : Int32) -> Int32 {
  let v = seed * 75 + 74
  let m = v % 65537
  if m < 0 {
    -m
  } else {
    m
  }
}

///|
test "fuzz: random css never panics and returns one style per node" {
  let selectors = [
    "*", "div", ".a", "#i", "div.a", "span .a", "div > span", ".a.b", "em", "a:hover",
    "x[y]", "",
  ]
  let props = [
    "color", "font-size", "padding", "margin", "border", "flex", "gap", "display",
    "width", "border-color", "unknown-prop", "flex-basis",
  ]
  let values = [
    "red", "#00ff00", "1px", "2em", "50%", "0", "auto", "", "1px 2px", "1px 2px 3px 4px",
    "1 2 10px", "nope", "#zzz", "solid", "10px solid blue", "!important",
  ]
  let tags = ["div", "span", "em"]
  let mut seed : Int32 = 7
  let mut css = ""
  let mut k = 0
  while k < 200 {
    seed = next_rand(seed)
    let sel = selectors[seed % selectors.length()]
    seed = next_rand(seed)
    let p = props[seed % props.length()]
    seed = next_rand(seed)
    let v = values[seed % values.length()]
    css = css + sel + " { " + p + ": " + v + " } "
    k = k + 1
  }
  let sheet = @style.Stylesheet::parse(css)
  // 随机生成 12 个前序节点，父下标随机落在已生成的节点上
  let nodes : Array[@style.ElementInfo] = []
  let mut i = 0
  while i < 12 {
    seed = next_rand(seed)
    let tag = tags[seed % tags.length()]
    seed = next_rand(seed)
    let parent = if i == 0 { -1 } else { seed % (i + 1) - 1 }
    seed = next_rand(seed)
    let has_class = seed % 2 == 0
    let classes = if has_class { ["a", "b"] } else { [] }
    nodes.push({ tag, id: "i", classes, inline: [], parent, })
    i = i + 1
  }
  let out = sheet.compute(nodes)
  assert_eq(out.length(), nodes.length())
  // 字号必须是有限正数：顺带排除 NaN / 负值
  let mut j = 0
  while j < out.length() {
    assert_true(out[j].font_size > 0.0)
    j = j + 1
  }
  // 再算一遍，确认没有隐藏状态
  let again = sheet.compute(nodes)
  assert_eq(again.length(), nodes.length())
}
