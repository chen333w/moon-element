///|
/// Rewrite a `:host`-style stylesheet into a plain one rooted at `scope`. Commas inside
/// parentheses do not split a selector list; `:host(.active)` becomes `scope.active`, not
/// `scope(.active)`; `@keyframes` stays verbatim. Not a full CSS parser.
pub fn scope_css(css : String, scope : String) -> String {
  let chars : Array[Char] = []
  push_string(chars, css)
  let out : Array[Char] = []
  if scope == "" {
    return css
  }
  scope_range(chars, 0, chars.length(), scope, out)
  String::from_iter(out.iter())
}

///|
fn is_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn copy_range(
  chars : Array[Char],
  start : Int32,
  end : Int32,
  out : Array[Char],
) -> Unit {
  let mut i = start
  while i < end {
    out.push(chars[i])
    i = i + 1
  }
}

///|
fn scope_range(
  chars : Array[Char],
  start : Int32,
  end : Int32,
  scope : String,
  out : Array[Char],
) -> Unit {
  let mut i = start
  while i < end {
    let c = chars[i]
    if c == '/' && i + 1 < end && chars[i + 1] == '*' {
      out.push(c)
      out.push(chars[i + 1])
      i = i + 2
      let mut closed = false
      while i < end && !closed {
        if chars[i] == '*' && i + 1 < end && chars[i + 1] == '/' {
          out.push('*')
          out.push('/')
          i = i + 2
          closed = true
        } else {
          out.push(chars[i])
          i = i + 1
        }
      }
    } else if c == '}' || c == ';' || is_ws(c) {
      out.push(c)
      i = i + 1
    } else {
      let prelude : Array[Char] = []
      let mut j = i
      while j < end && chars[j] != '{' && chars[j] != ';' {
        prelude.push(chars[j])
        j = j + 1
      }
      if j >= end || chars[j] == ';' {
        // @import or truncated input: emit verbatim
        for prelude_char in prelude {
          out.push(prelude_char)
        }
        if j < end {
          out.push(';')
          i = j + 1
        } else {
          i = j
        }
      } else {
        let inner_start = j + 1
        let mut depth = 1
        let mut k = inner_start
        while k < end {
          if chars[k] == '{' {
            depth = depth + 1
          } else if chars[k] == '}' {
            depth = depth - 1
            if depth == 0 {
              break
            }
          }
          k = k + 1
        }
        let inner_end = k
        emit_rule(chars, prelude, inner_start, inner_end, scope, out)
        i = if k < end { k + 1 } else { end }
      }
    }
  }
}

///|
fn emit_rule(
  chars : Array[Char],
  prelude : Array[Char],
  inner_start : Int32,
  inner_end : Int32,
  scope : String,
  out : Array[Char],
) -> Unit {
  let lead = first_non_ws(prelude)
  if lead < prelude.length() && prelude[lead] == '@' {
    if is_conditional_group(prelude, lead) {
      copy_trimmed(prelude, out)
      out.push(' ')
      out.push('{')
      scope_range(chars, inner_start, inner_end, scope, out)
      out.push('}')
    } else {
      // @keyframes and similar: kept verbatim
      copy_trimmed(prelude, out)
      out.push(' ')
      out.push('{')
      copy_range(chars, inner_start, inner_end, out)
      out.push('}')
    }
  } else {
    scope_selector_list(prelude, lead, scope, out)
    out.push(' ')
    out.push('{')
    copy_range(chars, inner_start, inner_end, out)
    out.push('}')
  }
}

///|
fn first_non_ws(chars : Array[Char]) -> Int32 {
  let mut i = 0
  while i < chars.length() && is_ws(chars[i]) {
    i = i + 1
  }
  i
}

///|
fn copy_trimmed(chars : Array[Char], out : Array[Char]) -> Unit {
  let start = first_non_ws(chars)
  let mut end = chars.length()
  while end > start && is_ws(chars[end - 1]) {
    end = end - 1
  }
  copy_range(chars, start, end, out)
}

///|
fn is_conditional_group(prelude : Array[Char], lead : Int32) -> Bool {
  let name : Array[Char] = []
  let mut i = lead + 1
  while i < prelude.length() {
    let c = prelude[i]
    if is_ws(c) || c == '(' {
      break
    }
    name.push(ascii_lower_char(c))
    i = i + 1
  }
  let n = String::from_iter(name.iter())
  n == "media" || n == "supports" || n == "container" || n == "layer"
}

///|
fn ascii_lower_char(c : Char) -> Char {
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
fn scope_selector_list(
  prelude : Array[Char],
  lead : Int32,
  scope : String,
  out : Array[Char],
) -> Unit {
  let mut depth = 0
  let mut seg_start = lead
  let mut i = lead
  let n = prelude.length()
  while i <= n {
    let at_end = i == n
    if !at_end {
      let c = prelude[i]
      if c == '(' {
        depth = depth + 1
      } else if c == ')' {
        if depth > 0 {
          depth = depth - 1
        }
      }
    }
    if at_end || (depth == 0 && prelude[i] == ',') {
      if seg_start > lead {
        out.push(',')
        out.push(' ')
      }
      emit_selector(prelude, seg_start, i, scope, out)
      seg_start = i + 1
    }
    i = i + 1
  }
}

///|
fn emit_selector(
  prelude : Array[Char],
  start : Int32,
  end : Int32,
  scope : String,
  out : Array[Char],
) -> Unit {
  let norm = normalize_ws(prelude, start, end)
  let n = norm.length()
  if n == 0 {
    return
  }
  if n >= 5 &&
    norm[0] == ':' &&
    norm[1] == 'h' &&
    norm[2] == 'o' &&
    norm[3] == 's' &&
    norm[4] == 't' {
    push_string(out, scope)
    if n > 5 && norm[5] == '(' {
      // :host(.active) → scope.active; scope(.active) would be invalid
      let inner : Array[Char] = []
      let mut depth = 0
      let mut k = 6
      while k < n {
        let c = norm[k]
        if c == ')' {
          if depth == 0 {
            k = k + 1
            break
          }
          depth = depth - 1
          inner.push(c)
        } else if c == '(' {
          depth = depth + 1
          inner.push(c)
        } else {
          inner.push(c)
        }
        k = k + 1
      }
      for inner_char in inner {
        out.push(inner_char)
      }
      copy_range(norm, k, n, out)
    } else {
      copy_range(norm, 5, n, out)
    }
  } else {
    push_string(out, scope)
    out.push(' ')
    copy_range(norm, 0, n, out)
  }
}

///|
fn normalize_ws(chars : Array[Char], start : Int32, end : Int32) -> Array[Char] {
  let out : Array[Char] = []
  let mut i = start
  let mut pending_space = false
  while i < end {
    if is_ws(chars[i]) {
      pending_space = out.length() > 0
    } else {
      if pending_space {
        out.push(' ')
        pending_space = false
      }
      out.push(chars[i])
    }
    i = i + 1
  }
  out
}
