// 导出层：SVG 给人看，确定性 JSON 给 CI 做 golden 比对。

///|
/// 固定两位小数。Double::to_string 的最短表示不保证跨后端一致，不能进断言。
fn fixed2(v : Double) -> String {
  let scaled = (v * 100.0).round().to_int()
  let neg = scaled < 0
  let mag = if neg { -scaled } else { scaled }
  let frac = mag % 100
  let frac_text = if frac < 10 { "0\{frac}" } else { "\{frac}" }
  let body = "\{mag / 100}.\{frac_text}"
  if neg && mag != 0 {
    "-" + body
  } else {
    body
  }
}

///|
fn indent(n : Int32) -> String {
  let out : Array[Char] = []
  let mut i = 0
  while i < n {
    out.push(' ')
    out.push(' ')
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
fn push_string(out : Array[Char], s : String) -> Unit {
  let n = s.char_length()
  let mut i : Int32 = 0
  while i < n {
    match s.get_char(i) {
      Some(c) => out.push(c)
      None => ()
    }
    i = i + 1
  }
}

///|
/// XML 的文本与属性值都要转义，否则文档失去良构性。
fn escape_xml(s : String) -> String {
  let out : Array[Char] = []
  let n = s.char_length()
  let mut i : Int32 = 0
  while i < n {
    match s.get_char(i) {
      Some(c) => {
        let v = c.to_int()
        if v == 38 {
          push_string(out, "&amp;")
        } else if v == 60 {
          push_string(out, "&lt;")
        } else if v == 62 {
          push_string(out, "&gt;")
        } else if v == 34 {
          push_string(out, "&quot;")
        } else if v == 39 {
          push_string(out, "&apos;")
        } else {
          out.push(c)
        }
      }
      None => ()
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
/// JSON 只需要处理本层字符串转义，`&`、`<`、`>` 保持原样。
fn escape_json(s : String) -> String {
  let hex : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out : Array[Char] = []
  let n = s.char_length()
  let mut i : Int32 = 0
  while i < n {
    match s.get_char(i) {
      Some(c) => {
        let v = c.to_int()
        if v == 34 {
          push_string(out, "\\\"")
        } else if v == 92 {
          push_string(out, "\\\\")
        } else if v == 10 {
          push_string(out, "\\n")
        } else if v == 13 {
          push_string(out, "\\r")
        } else if v == 9 {
          push_string(out, "\\t")
        } else if v < 32 {
          push_string(out, "\\u00")
          out.push(hex[v / 16])
          out.push(hex[v % 16])
        } else {
          out.push(c)
        }
      }
      None => ()
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
fn color_of(c : @style.Rgba) -> String {
  "rgb(\{c.r},\{c.g},\{c.b})"
}

///|
fn opacity_attr(c : @style.Rgba) -> String {
  if c.a < 1.0 {
    " fill-opacity=\"" + fixed2(c.a) + "\""
  } else {
    ""
  }
}

///|
/// 四边取最大值：SVG 的 stroke 是居中描边，这里只求视觉一致。
fn border_width(e : @style.Edges) -> Double {
  let m = if e.top > e.right { e.top } else { e.right }
  let m = if m > e.bottom { m } else { e.bottom }
  if m > e.left {
    m
  } else {
    e.left
  }
}

///|
fn box_rect(box : @layout.LayoutBox) -> @layout.Rect {
  match box {
    @layout.LayoutBox::Box(b) => b.rect
    @layout.LayoutBox::Text(t) => t.rect
  }
}

///|
fn node_index(box : @layout.LayoutBox) -> Int32 {
  match box {
    @layout.LayoutBox::Box(b) => b.node
    @layout.LayoutBox::Text(t) => t.node
  }
}

///|
fn rect_json(box : @layout.LayoutBox) -> String {
  let r = box_rect(box)
  "[" +
  fixed2(r.x) +
  ", " +
  fixed2(r.y) +
  ", " +
  fixed2(r.w) +
  ", " +
  fixed2(r.h) +
  "]"
}

///|
/// 结构不一致时按较短的一侧配对，导出层不 panic。
fn paired_count(node : @layout.StyleNode, box : @layout.LayoutBox) -> Int32 {
  let kids : Array[@layout.LayoutBox] = match box {
    @layout.LayoutBox::Box(b) => b.children
    @layout.LayoutBox::Text(_) => []
  }
  let a = node.children.length()
  let b = kids.length()
  if a < b {
    a
  } else {
    b
  }
}

///|
/// 完整 SVG 文档。根盒子加 1px 余量，避免最外层的描边被裁掉。
pub fn to_svg(root : @layout.StyleNode, box : @layout.LayoutBox) -> String {
  let r = box_rect(box)
  let w = r.w + 1.0
  let h = r.h + 1.0
  let pieces : Array[Char] = []
  push_string(
    pieces,
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" +
    fixed2(w) +
    "\" height=\"" +
    fixed2(h) +
    "\" viewBox=\"0 0 " +
    fixed2(w) +
    " " +
    fixed2(h) +
    "\">\n",
  )
  emit_svg_node(pieces, root, box, 1)
  push_string(pieces, "</svg>\n")
  String::from_iter(pieces.iter())
}

///|
fn emit_svg_node(
  pieces : Array[Char],
  node : @layout.StyleNode,
  box : @layout.LayoutBox,
  depth : Int32,
) -> Unit {
  let pad = indent(depth)
  match node.text {
    Some(text) =>
      match box {
        @layout.LayoutBox::Text(t) =>
          push_string(
            pieces,
            pad +
            "<text x=\"" +
            fixed2(t.rect.x) +
            "\" y=\"" +
            fixed2(t.rect.y + t.baseline) +
            "\" font-size=\"" +
            fixed2(node.style.font_size) +
            "\" font-family=\"monospace\" fill=\"" +
            color_of(node.style.color) +
            opacity_attr(node.style.color) +
            "\" data-node=\"" +
            "\{t.node}" +
            "\">" +
            escape_xml(text) +
            "</text>\n",
          )
        @layout.LayoutBox::Box(_) => ()
      }
    None =>
      match box {
        @layout.LayoutBox::Box(b) => {
          let bw = border_width(node.style.border)
          let fill = if node.style.background_color.a > 0.0 {
            " fill=\"" +
            color_of(node.style.background_color) +
            opacity_attr(node.style.background_color) +
            "\""
          } else {
            " fill=\"none\""
          }
          let stroke = if bw > 0.0 {
            " stroke=\"" +
            color_of(node.style.border_color) +
            "\" stroke-width=\"" +
            fixed2(bw) +
            "\""
          } else {
            ""
          }
          let rx = if node.style.border_radius > 0.0 {
            " rx=\"" + fixed2(node.style.border_radius) + "\""
          } else {
            ""
          }
          push_string(
            pieces,
            pad +
            "<rect x=\"" +
            fixed2(b.rect.x) +
            "\" y=\"" +
            fixed2(b.rect.y) +
            "\" width=\"" +
            fixed2(b.rect.w) +
            "\" height=\"" +
            fixed2(b.rect.h) +
            "\"" +
            rx +
            fill +
            stroke +
            " data-node=\"" +
            "\{b.node}" +
            "\" data-tag=\"" +
            escape_xml(node.info.tag) +
            "\"/>\n",
          )
          let n = paired_count(node, box)
          for i in 0..<n {
            emit_svg_node(pieces, node.children[i], b.children[i], depth + 1)
          }
        }
        @layout.LayoutBox::Text(_) => ()
      }
  }
}

///|
/// 确定性布局 JSON：字段顺序固定，坐标一律两位小数。
pub fn to_json(root : @layout.StyleNode, box : @layout.LayoutBox) -> String {
  let pieces : Array[Char] = []
  emit_json_node(pieces, root, box, 0)
  push_string(pieces, "\n")
  String::from_iter(pieces.iter())
}

///|
fn emit_json_node(
  pieces : Array[Char],
  node : @layout.StyleNode,
  box : @layout.LayoutBox,
  depth : Int32,
) -> Unit {
  let pad = indent(depth)
  let inner = indent(depth + 1)
  push_string(pieces, pad + "{\n")
  push_string(pieces, inner + "\"node\": " + "\{node_index(box)}" + ",\n")
  match node.text {
    Some(text) => {
      push_string(pieces, inner + "\"tag\": \"#text\",\n")
      push_string(pieces, inner + "\"text\": \"" + escape_json(text) + "\",\n")
    }
    None =>
      push_string(
        pieces,
        inner + "\"tag\": \"" + escape_json(node.info.tag) + "\",\n",
      )
  }
  push_string(pieces, inner + "\"rect\": " + rect_json(box) + ",\n")
  push_string(
    pieces,
    inner + "\"children\": " + children_json(node, box, depth) + "\n",
  )
  push_string(pieces, pad + "}")
}

///|
fn children_json(
  node : @layout.StyleNode,
  box : @layout.LayoutBox,
  depth : Int32,
) -> String {
  let n = paired_count(node, box)
  if n == 0 {
    return "[]"
  }
  let kids : Array[@layout.LayoutBox] = match box {
    @layout.LayoutBox::Box(b) => b.children
    @layout.LayoutBox::Text(_) => []
  }
  let pieces : Array[Char] = []
  push_string(pieces, "[\n")
  for i in 0..<n {
    emit_json_node(pieces, node.children[i], kids[i], depth + 2)
    if i + 1 < n {
      push_string(pieces, ",\n")
    } else {
      push_string(pieces, "\n")
    }
  }
  push_string(pieces, indent(depth + 1) + "]")
  String::from_iter(pieces.iter())
}
