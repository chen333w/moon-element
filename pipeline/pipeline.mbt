// 视图层到布局层的胶水：View → 扁平节点表 → 样式树 → 几何。

///|
/// 待组装的节点：文本内容先存着，样式等切分完之后按前序下标贴上。
priv struct Draft {
  info : @style.ElementInfo
  text : String?
  children : Array[Draft]
}

///|
fn is_space_at(s : String, i : Int32) -> Bool {
  match s.get_char(i) {
    Some(c) => c == ' ' || c == '\t' || c == '\n' || c == '\r'
    None => false
  }
}

///|
fn slice_of(s : String, from : Int32, to : Int32) -> String {
  let n = s.char_length()
  let start = if from < 0 { 0 } else if from > n { n } else { from }
  let stop = if to > n { n } else if to < start { start } else { to }
  let out : Array[Char] = []
  let mut i = start
  while i < stop {
    match s.get_char(i) {
      Some(c) => out.push(c)
      None => ()
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
fn trim_of(s : String) -> String {
  let n = s.char_length()
  let mut start : Int32 = 0
  while start < n && is_space_at(s, start) {
    start = start + 1
  }
  let mut stop = n
  while stop > start && is_space_at(s, stop - 1) {
    stop = stop - 1
  }
  slice_of(s, start, stop)
}

///|
fn split_on(s : String, sep : Char) -> Array[String] {
  let out : Array[String] = []
  let n = s.char_length()
  let mut start : Int32 = 0
  let mut i : Int32 = 0
  while i < n {
    match s.get_char(i) {
      Some(c) =>
        if c == sep {
          out.push(slice_of(s, start, i))
          start = i + 1
        }
      None => ()
    }
    i = i + 1
  }
  out.push(slice_of(s, start, n))
  out
}

///|
fn split_ws(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.char_length()
  let mut i : Int32 = 0
  while i < n {
    while i < n && is_space_at(s, i) {
      i = i + 1
    }
    let start = i
    while i < n && !is_space_at(s, i) {
      i = i + 1
    }
    if i > start {
      out.push(slice_of(s, start, i))
    }
  }
  out
}

///|
/// `style="color: red; padding: 4px"` 拆成属性对，值里的冒号不再拆。
fn inline_of(s : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for decl in split_on(s, ';') {
    let decl = trim_of(decl)
    if decl != "" {
      match split_decl(decl) {
        Some(pair) => out.push(pair)
        None => ()
      }
    }
  }
  out
}

///|
fn split_decl(decl : String) -> (String, String)? {
  let n = decl.char_length()
  let mut i : Int32 = 0
  while i < n {
    match decl.get_char(i) {
      Some(c) =>
        if c == ':' {
          return Some(
            (trim_of(slice_of(decl, 0, i)), trim_of(slice_of(decl, i + 1, n))),
          )
        }
      None => ()
    }
    i = i + 1
  }
  None
}

///|
fn attr_of(attrs : Array[(String, String)], name : String) -> String? {
  for pair in attrs {
    if pair.0.to_lower() == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn text_draft(parent : Int32, s : String) -> Draft {
  {
    info: { tag: "#text", id: "", classes: [], inline: [], parent, },
    text: Some(s),
    children: [],
  }
}

///|
/// 前序展开；片段与空节点不占下标，所以两个遍历（建树与贴样式）顺序一致。
fn draft_of(
  view : @core.View,
  parent : Int32,
  cursor : Array[Int32],
) -> Array[Draft] {
  let out : Array[Draft] = []
  match view {
    @core.View::VNothing => ()
    @core.View::VText(s) => {
      cursor[0] = cursor[0] + 1
      out.push(text_draft(parent, s))
    }
    @core.View::VRaw(s) => {
      cursor[0] = cursor[0] + 1
      out.push(text_draft(parent, s))
    }
    @core.View::VFragment(children) =>
      for child in children {
        for draft in draft_of(child, parent, cursor) {
          out.push(draft)
        }
      }
    @core.View::VElement(tag, attrs, children) => {
      let index = cursor[0]
      cursor[0] = index + 1
      let id = match attr_of(attrs, "id") {
        Some(v) => v
        None => ""
      }
      let classes = match attr_of(attrs, "class") {
        Some(v) => split_ws(v)
        None => []
      }
      let inline = match attr_of(attrs, "style") {
        Some(v) => inline_of(v)
        None => []
      }
      let kids : Array[Draft] = []
      for child in children {
        for draft in draft_of(child, index, cursor) {
          kids.push(draft)
        }
      }
      out.push({
        info: { tag, id, classes, inline, parent, },
        text: None,
        children: kids,
      })
    }
  }
  out
}

///|
fn collect_infos(
  drafts : Array[Draft],
  out : Array[@style.ElementInfo],
) -> Unit {
  for draft in drafts {
    out.push(draft.info)
    collect_infos(draft.children, out)
  }
}

///|
/// 前序扁平节点表；文本节点也占一个下标，父下标一定小于子下标。
pub fn nodes_of(view : @core.View) -> Array[@style.ElementInfo] {
  let cursor : Array[Int32] = [0]
  let drafts = draft_of(view, -1, cursor)
  let out : Array[@style.ElementInfo] = []
  collect_infos(drafts, out)
  out
}

///|
fn assemble(
  drafts : Array[Draft],
  styles : Array[@style.ComputedStyle],
  cursor : Array[Int32],
) -> Array[@layout.StyleNode] {
  let out : Array[@layout.StyleNode] = []
  for draft in drafts {
    let at = cursor[0]
    cursor[0] = cursor[0] + 1
    let style = if at < styles.length() {
      styles[at]
    } else {
      @style.ComputedStyle::initial()
    }
    out.push({
      info: draft.info,
      style,
      children: assemble(draft.children, styles, cursor),
      text: draft.text,
    })
  }
  out
}

///|
/// 计算样式并拼回树。顶层若有多个节点，用初始样式的根包一层。
pub fn build(view : @core.View, sheet : @style.Stylesheet) -> @layout.StyleNode {
  let cursor : Array[Int32] = [0]
  let drafts = draft_of(view, -1, cursor)
  let styles = sheet.compute(nodes_of(view))
  let cursor2 : Array[Int32] = [0]
  let kids = assemble(drafts, styles, cursor2)
  if kids.length() == 1 {
    kids[0]
  } else {
    {
      info: { tag: "html", id: "", classes: [], inline: [], parent: -1, },
      style: @style.ComputedStyle::initial(),
      children: kids,
      text: None,
    }
  }
}

///|
/// 整条流水线：CSS 解析 + 层叠 + 布局。
pub fn run(
  view : @core.View,
  css : String,
  width : Double,
  measure : @layout.TextMeasure,
) -> (@layout.StyleNode, @layout.LayoutBox) {
  let sheet = @style.Stylesheet::parse(css)
  let root = build(view, sheet)
  let box = @layout.layout(root, width, measure)
  (root, box)
}

///|
/// 无浏览器环境下的等宽文本测量：每字符 0.6em，行高 1.2em。
pub fn measure_monospace(text : String, size : Double) -> (Double, Double) {
  (text.char_length().to_double() * 0.6 * size, 1.2 * size)
}
