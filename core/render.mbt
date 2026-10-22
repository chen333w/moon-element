///|
/// A view tree.
///
/// Expresses only elements, attributes, children, text, and fragments. Rendering is a
/// pure function, testable with plain unit tests on all four backends; mounting into the
/// DOM is the adapter's job.
///
/// - `VText` is HTML-escaped; `VRaw` is not, and the caller owns safety
/// - `VElement` is (tag name, attribute list, children)
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
/// Emit verbatim, **without escaping**; use only where the content is fully controlled.
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
/// Void elements: no closing tag per the HTML spec, and no children are rendered.
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
/// HTML text escaping. Works on code points, so it does not depend on escape sequences
/// in character literals: `&`(38) `<`(60) `>`(62) `"`(34) `'`(39).
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
      // void elements render no children
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
/// Render a view tree to an HTML string.
///
/// The output is deterministic: attributes are emitted in the given order, with no
/// reordering or deduplication (the caller guarantees unique attributes).
///
/// String concatenation here is the naive O(n²) `out = out + piece`. That is fine at the
/// current scale; switch to a buffered writer when real performance needs appear.
pub fn render(view : View) -> String {
  let pieces : Array[String] = []
  render_into(view, pieces)
  let mut out = ""
  for piece in pieces {
    out = out + piece
  }
  out
}
