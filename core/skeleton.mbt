///|
/// 自定义元素名校验与组件骨架生成。
///
/// 这两件事都是纯字符串逻辑，所以放在 `core` 里：可以在四个后端上测，
/// CLI 只负责把结果打印出来。

///|
/// 按 HTML 规范校验自定义元素名（custom element name）。
///
/// 规则：
/// - 非空，且**必须含连字符**（`mywidget` 不是合法自定义元素名，`my-widget` 才是）
/// - 不能以连字符开头或结尾
/// - 只允许小写 ASCII 字母、数字、连字符、点、下划线（大写字母是无效的）
/// - 不能以 `xml` 开头（大小写不敏感，规范保留）
/// - 不能是保留名（`annotation-xml`、`color-profile`、`font-face` 等）
///
/// 这里刻意**不**允许非 ASCII 字符：规范允许一部分，但把它留给后续迭代，
/// 现在保守地拒绝比默默生成浏览器不认的名字要好。
pub fn validate_tag_name(tag : String) -> Bool {
  let n = tag.char_length()
  if n == 0 {
    return false
  }
  // 必须含连字符
  let mut has_hyphen = false
  let mut i = 0
  while i < n {
    match tag.get_char(i) {
      Some(c) => if c == '-' { has_hyphen = true }
      None => ()
    }
    i = i + 1
  }
  if !has_hyphen {
    return false
  }
  // 不能以连字符开头或结尾
  let first = tag.get_char(0).unwrap_or(' ')
  let last = tag.get_char(n - 1).unwrap_or(' ')
  if first == '-' || last == '-' {
    return false
  }
  // 字符集
  i = 0
  while i < n {
    match tag.get_char(i) {
      Some(c) => if !is_tag_char(c) { return false }
      None => ()
    }
    i = i + 1
  }
  // 保留前缀与保留名
  if has_prefix_ignoring_case(tag, "xml") {
    return false
  }
  for
    reserved in [
      "annotation-xml", "color-profile", "font-face", "font-face-src", "font-face-uri",
      "font-face-format", "font-face-name", "missing-glyph",
    ] {
    if tag == reserved {
      return false
    }
  }
  true
}

///|
fn is_tag_char(c : Char) -> Bool {
  let v = c.to_int()
  let lower_a = 'a'.to_int()
  let lower_z = 'z'.to_int()
  let digit_0 = '0'.to_int()
  let digit_9 = '9'.to_int()
  (v >= lower_a && v <= lower_z) ||
  (v >= digit_0 && v <= digit_9) ||
  v == '-'.to_int() ||
  v == '.'.to_int() ||
  v == '_'.to_int()
}

///|
fn has_prefix_ignoring_case(s : String, prefix : String) -> Bool {
  if s.char_length() < prefix.char_length() {
    return false
  }
  let mut i = 0
  while i < prefix.char_length() {
    let a = ascii_lower(s.get_char(i).unwrap_or(' '))
    let b = ascii_lower(prefix.get_char(i).unwrap_or(' '))
    if a != b {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn ascii_lower(c : Char) -> Char {
  let v = c.to_int()
  if v >= 'A'.to_int() && v <= 'Z'.to_int() {
    match (v + 32).to_char() {
      Some(l) => l
      None => c
    }
  } else {
    c
  }
}

///|
/// `my-widget` → `my_widget`（用于生成标识符）
pub fn tag_to_snake(tag : String) -> String {
  let out : Array[Char] = []
  let n = tag.char_length()
  let mut i = 0
  while i < n {
    let c = tag.get_char(i).unwrap_or(' ')
    if c == '-' || c == '.' {
      out.push('_')
    } else {
      out.push(c)
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
/// 生成一个组件骨架的 MoonBit 源码。
///
/// 标签名非法时返回 `None`（而不是生成一份跑不起来的代码）。
pub fn component_skeleton(tag : String) -> String? {
  if !validate_tag_name(tag) {
    return None
  }
  let snake = tag_to_snake(tag)
  // 用逐行拼接而不是 `#|` 多行字面量：`#|` 块是原始文本，不做 `\{...}` 插值，
  // 写在那里会生成字面量 `\{tag}` 这种坏代码。
  let lines : Array[String] = [
    "// 由 moon-element CLI 生成的自定义元素骨架：\{tag}",
    "//",
    "// 使用方式：",
    "// 1) 在本包的 moon.pkg 里声明依赖（import 属于包配置，不能写进 .mbt）：",
    "//      import {",
    "//        \"chen333w/moon-element/core\" @core,",
    "//        \"chen333w/moon-element/dom\" @dom,",
    "//      }",
    "// 2) 把本文件放进包里，并在入口处调用 register_\{snake}()",
    "// 3) 产物是标准自定义元素：宿主页面里写 <\{tag}> 即可，渲染结果在 shadow root 内",
    "",
    "///|",
    "fn render_\{snake}(props : @core.Props) -> @core.View {",
    "  let label = props.get_string(\"label\").unwrap_or(\"\")",
    "  @core.View::element(\"span\", [], [@core.View::text(label)])",
    "}",
    "",
    "///|",
    "pub fn register_\{snake}() -> Unit {",
    "  @dom.define_component(",
    "    \"\{tag}\",",
    "    [@core.AttrSpec::string(\"label\", \"\")],",
    "    render_\{snake},",
    "    events=[",
    "      // 需要让宿主页面收到的事件，用 crossing（bubbles + composed）",
    "      @core.EventSpec::crossing(\"\{tag}-changed\"),",
    "    ],",
    "  )",
    "}",
  ]
  // 行与行之间用 \n 连接，**结尾不留换行**：调用方用 println 输出到文件后
  // 恰好一个结尾换行，与 moon fmt 规范化后的结果一致。
  let mut out = ""
  let mut li = 0
  while li < lines.length() {
    if li > 0 {
      out = out + "\n"
    }
    out = out + lines[li]
    li = li + 1
  }
  Some(out)
}
