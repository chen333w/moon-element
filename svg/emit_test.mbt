// 导出层的黑盒测试：JSON 精确文本、SVG 结构计数、XML/JSON 转义、空树。

///|
fn rgba(r : Int32, g : Int32, b : Int32) -> @style.Rgba {
  { r, g, b, a: 1.0, }
}

///|
fn style(
  bg : @style.Rgba,
  color : @style.Rgba,
  border : Double,
  radius : Double,
) -> @style.ComputedStyle {
  let base = @style.ComputedStyle::initial()
  {
    ..base,
    background_color: bg,
    color,
    border: @style.Edges::all(border),
    border_color: color,
    border_radius: radius,
    font_size: 16.0,
  }
}

///|
fn elem(
  tag : String,
  parent : Int32,
  style : @style.ComputedStyle,
  children : Array[@layout.StyleNode],
) -> @layout.StyleNode {
  {
    info: { tag, id: "", classes: [], inline: [], parent, },
    style,
    children,
    text: None,
  }
}

///|
fn text_node(
  s : String,
  parent : Int32,
  style : @style.ComputedStyle,
) -> @layout.StyleNode {
  {
    info: { tag: "#text", id: "", classes: [], inline: [], parent, },
    style,
    children: [],
    text: Some(s),
  }
}

///|
fn box(
  node : Int32,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  children : Array[@layout.LayoutBox],
) -> @layout.LayoutBox {
  @layout.LayoutBox::Box({ node, rect: { x, y, w, h, }, children, })
}

///|
fn text_box(
  node : Int32,
  s : String,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  baseline : Double,
) -> @layout.LayoutBox {
  @layout.LayoutBox::Text({ node, text: s, baseline, rect: { x, y, w, h, }, })
}

///|
fn count_of(haystack : String, needle : String) -> Int32 {
  let hl = haystack.char_length()
  let nl = needle.char_length()
  let mut count = 0
  let mut i : Int32 = 0
  while i + nl <= hl {
    let mut k : Int32 = 0
    let mut same = true
    while k < nl {
      if haystack.get_char(i + k) != needle.get_char(k) {
        same = false
        k = nl
      } else {
        k = k + 1
      }
    }
    if same {
      count = count + 1
      i = i + nl
    } else {
      i = i + 1
    }
  }
  count
}

///|
/// 一棵固定的测试树：div 里一个文本加一个 span，span 里再一个文本。
fn sample_root() -> @layout.StyleNode {
  let plain = style(rgba(0, 0, 0), rgba(10, 20, 30), 0.0, 0.0)
  elem("div", -1, style(rgba(200, 220, 240), rgba(10, 20, 30), 1.0, 4.0), [
    text_node("Hi & <you>", 0, plain),
    elem("span", 0, plain, [text_node("ok", 1, plain)]),
  ])
}

///|
fn sample_box() -> @layout.LayoutBox {
  box(0, 0.0, 0.0, 200.0, 60.0, [
    text_box(1, "Hi & <you>", 10.0, 10.0, 80.0, 16.0, 12.0),
    box(2, 10.0, 30.0, 100.0, 20.0, [
      text_box(3, "ok", 12.0, 32.0, 20.0, 16.0, 12.0),
    ]),
  ])
}

///|
test "to_json emits fixed field order and two decimals" {
  let expected =
    #|{
    #|  "node": 0,
    #|  "tag": "div",
    #|  "rect": [0.00, 0.00, 200.00, 60.00],
    #|  "children": [
    #|    {
    #|      "node": 1,
    #|      "tag": "#text",
    #|      "text": "Hi & <you>",
    #|      "rect": [10.00, 10.00, 80.00, 16.00],
    #|      "children": []
    #|    },
    #|    {
    #|      "node": 2,
    #|      "tag": "span",
    #|      "rect": [10.00, 30.00, 100.00, 20.00],
    #|      "children": [
    #|        {
    #|          "node": 3,
    #|          "tag": "#text",
    #|          "text": "ok",
    #|          "rect": [12.00, 32.00, 20.00, 16.00],
    #|          "children": []
    #|        }
    #|      ]
    #|    }
    #|  ]
    #|}
  assert_eq(@svg.to_json(sample_root(), sample_box()), expected + "\n")
}

///|
test "to_svg draws one svg, one rect per element and one text per run" {
  let svg = @svg.to_svg(sample_root(), sample_box())
  assert_eq(count_of(svg, "<svg"), 1)
  assert_eq(count_of(svg, "</svg>"), 1)
  assert_eq(count_of(svg, "<rect"), 2)
  assert_eq(count_of(svg, "<text"), 2)
  assert_eq(count_of(svg, "data-tag=\"div\""), 1)
  assert_eq(count_of(svg, "data-tag=\"span\""), 1)
  // 根盒子 200x60 加 1px 余量
  assert_eq(count_of(svg, "width=\"201.00\" height=\"61.00\""), 1)
}

///|
test "to_svg positions text on the baseline and fills with the text color" {
  let svg = @svg.to_svg(sample_root(), sample_box())
  // y = 盒顶 10 + baseline 12
  assert_eq(count_of(svg, "x=\"10.00\" y=\"22.00\""), 1)
  assert_eq(count_of(svg, "fill=\"rgb(10,20,30)\""), 2)
  assert_eq(count_of(svg, "stroke-width=\"1.00\""), 1)
}

///|
test "to_svg escapes tags and text as XML" {
  let plain = style(rgba(0, 0, 0), rgba(0, 0, 0), 1.0, 0.0)
  let root = elem("a<b", -1, plain, [text_node("x & \"y\" <z>", 0, plain)])
  let tree = box(0, 0.0, 0.0, 40.0, 20.0, [
    text_box(1, "x & \"y\" <z>", 2.0, 2.0, 30.0, 16.0, 12.0),
  ])
  let svg = @svg.to_svg(root, tree)
  assert_eq(count_of(svg, "data-tag=\"a&lt;b\""), 1)
  assert_eq(count_of(svg, "&amp;"), 1)
  assert_eq(count_of(svg, "&quot;"), 2)
  assert_eq(count_of(svg, "&lt;z&gt;"), 1)
  // 未转义的原始字符不应出现
  assert_eq(count_of(svg, "<z>"), 0)
}

///|
test "to_json escapes quotes and keeps markup characters literal" {
  let plain = style(rgba(0, 0, 0), rgba(0, 0, 0), 0.0, 0.0)
  let root = elem("a<b", -1, plain, [text_node("q\"b\\s", 0, plain)])
  let tree = box(0, 0.0, 0.0, 10.0, 10.0, [
    text_box(1, "q\"b\\s", 0.0, 0.0, 10.0, 10.0, 8.0),
  ])
  let json = @svg.to_json(root, tree)
  assert_eq(count_of(json, "\"tag\": \"a<b\""), 1)
  assert_eq(count_of(json, "\"text\": \"q\\\"b\\\\s\""), 1)
}

///|
test "an empty tree still emits a well-formed document" {
  let plain = style(rgba(0, 0, 0), rgba(0, 0, 0), 0.0, 0.0)
  let root = elem("div", -1, plain, [])
  let tree = box(0, 0.0, 0.0, 10.0, 10.0, [])
  let json = @svg.to_json(root, tree)
  assert_eq(count_of(json, "{\n"), 1)
  assert_eq(count_of(json, "\"children\": []"), 1)
  let svg = @svg.to_svg(root, tree)
  assert_eq(count_of(svg, "<rect"), 1)
  assert_eq(count_of(svg, "<text"), 0)
}

///|
test "a mismatched box tree is truncated instead of panicking" {
  let plain = style(rgba(0, 0, 0), rgba(0, 0, 0), 0.0, 0.0)
  let root = elem("div", -1, plain, [
    text_node("a", 0, plain),
    text_node("b", 0, plain),
  ])
  // 盒子只给了一个孩子
  let tree = box(0, 0.0, 0.0, 10.0, 20.0, [
    text_box(1, "a", 0.0, 0.0, 10.0, 16.0, 12.0),
  ])
  assert_eq(count_of(@svg.to_json(root, tree), "\"text\""), 1)
  assert_eq(count_of(@svg.to_svg(root, tree), "<text"), 1)
}

///|
test "to_json and to_svg are deterministic across repeated calls" {
  let first_json = @svg.to_json(sample_root(), sample_box())
  let second_json = @svg.to_json(sample_root(), sample_box())
  assert_eq(first_json, second_json)
  assert_eq(
    @svg.to_svg(sample_root(), sample_box()),
    @svg.to_svg(sample_root(), sample_box()),
  )
}

///|
test "coordinates keep two decimals and never print negative zero" {
  let plain = style(rgba(0, 0, 0), rgba(0, 0, 0), 0.0, 0.0)
  let root = elem("div", -1, plain, [])
  let tree = box(0, -3.456, 0.004, 12.345, 7.0, [])
  let json = @svg.to_json(root, tree)
  assert_eq(count_of(json, "\"rect\": [-3.46, 0.00, 12.35, 7.00]"), 1)
}

///|
test "an empty text run still emits a text element and an empty string" {
  let plain = style(rgba(0, 0, 0), rgba(0, 0, 0), 0.0, 0.0)
  let root = elem("div", -1, plain, [text_node("", 0, plain)])
  let tree = box(0, 0.0, 0.0, 10.0, 16.0, [
    text_box(1, "", 0.0, 0.0, 0.0, 16.0, 12.0),
  ])
  assert_eq(count_of(@svg.to_svg(root, tree), "<text"), 1)
  assert_eq(count_of(@svg.to_json(root, tree), "\"text\": \"\""), 1)
}

///|
test "a 400 character text run stays intact and is escaped once" {
  let mut long = ""
  for _ in 0..<400 {
    long = long + "a"
  }
  let long = long + " & <tail>"
  let plain = style(rgba(0, 0, 0), rgba(0, 0, 0), 0.0, 0.0)
  let root = elem("div", -1, plain, [text_node(long, 0, plain)])
  let tree = box(0, 0.0, 0.0, 200.0, 16.0, [
    text_box(1, long, 0.0, 0.0, 200.0, 16.0, 12.0),
  ])
  let svg = @svg.to_svg(root, tree)
  assert_eq(count_of(svg, "<text"), 1)
  assert_eq(count_of(svg, "&amp; &lt;tail&gt;"), 1)
  let json = @svg.to_json(root, tree)
  assert_eq(count_of(json, " & <tail>"), 1)
}

///|
test "a text node paired with an element box is skipped" {
  let plain = style(rgba(0, 0, 0), rgba(0, 0, 0), 1.0, 0.0)
  let root = text_node("ghost", -1, plain)
  let tree = box(0, 0.0, 0.0, 10.0, 10.0, [])
  let svg = @svg.to_svg(root, tree)
  assert_eq(count_of(svg, "<text"), 0)
  assert_eq(count_of(svg, "<rect"), 0)
  assert_eq(count_of(svg, "<svg"), 1)
}

///|
test "an element node paired with a text box draws no rect" {
  let plain = style(rgba(0, 0, 0), rgba(0, 0, 0), 1.0, 0.0)
  let root = elem("div", -1, plain, [])
  let tree = text_box(0, "x", 0.0, 0.0, 10.0, 10.0, 8.0)
  assert_eq(count_of(@svg.to_svg(root, tree), "<rect"), 0)
}
