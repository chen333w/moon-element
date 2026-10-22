///|
/// 视图树。
///
/// 只表达「元素 + 属性 + 子节点 + 文本 + 片段」。渲染是纯函数，
/// 可以在四个后端上用普通单元测试验证；DOM 挂载由适配层负责。
///
/// - `VText` 会被 HTML 转义；`VRaw` 不会，调用方自己负责安全
/// - `VElement` 是 (标签名, 属性列表, 子节点)
pub(all) enum View {
  VText(String)
  VRaw(String)
  VElement(String, Array[(String, String)], Array[View])
  VFragment(Array[View])
  VNothing
}

///|
pub fn View::text(s : String) -> View {
  VText(s)
}

///|
/// 原样输出，**不转义**，仅在内容完全可控时使用。
pub fn View::raw(s : String) -> View {
  VRaw(s)
}

///|
pub fn View::element(
  tag : String,
  attrs : Array[(String, String)],
  children : Array[View],
) -> View {
  VElement(tag, attrs, children)
}

///|
pub fn View::fragment(children : Array[View]) -> View {
  VFragment(children)
}

///|
pub fn View::nothing() -> View {
  VNothing
}

///|
/// 空元素（void elements）：按 HTML 规范没有闭合标签，也不会渲染子节点。
fn is_void_tag(tag : String) -> Bool {
  for
    name in [
      "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
      "param", "source", "track", "wbr",
    ] {
    if tag == name {
      return true
    }
  }
  false
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
/// HTML 文本转义。按码点处理以免依赖字符字面量的转义写法：
/// `&`(38) `<`(60) `>`(62) `"`(34) `'`(39)。
pub fn escape_text(s : String) -> String {
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
          push_string(out, "&#39;")
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
fn render_into(view : View, pieces : Array[String]) -> Unit {
  match view {
    VNothing => ()
    VText(s) => pieces.push(escape_text(s))
    VRaw(s) => pieces.push(s)
    VFragment(children) =>
      for child in children {
        render_into(child, pieces)
      }
    VElement(tag, attrs, children) => {
      pieces.push("<")
      pieces.push(tag)
      for attr in attrs {
        pieces.push(" ")
        pieces.push(attr.0)
        pieces.push("=\"")
        pieces.push(escape_text(attr.1))
        pieces.push("\"")
      }
      pieces.push(">")
      // void 元素不渲染子节点
      if !is_void_tag(tag) {
        for child in children {
          render_into(child, pieces)
        }
        pieces.push("</")
        pieces.push(tag)
        pieces.push(">")
      }
    }
  }
}

///|
/// 把视图树渲染成 HTML 字符串。
///
/// 输出是确定性的：属性按给定顺序输出，不做重排或去重（属性唯一由调用方保证）。
///
/// 拼接字符串是 O(n²) 的朴素做法（`out = out + piece`），当前规模下无问题，
/// 有真实性能需求时再换成缓冲写入。
pub fn render(view : View) -> String {
  let pieces : Array[String] = []
  render_into(view, pieces)
  let mut out = ""
  for piece in pieces {
    out = out + piece
  }
  out
}
