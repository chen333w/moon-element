// 样式表解析。坏规则跳过并记 warning，任何输入都不 panic。

///|
pub struct Rule {
  selectors : Array[Selector]
  decls : Array[Decl]
  order : Int32
}

///|
/// 解析后的样式表。内部表示不对外暴露。
pub struct Stylesheet {
  rules : Array[Rule]
  warns : Array[String]
}

///|
/// 去掉 /* */ 注释；未闭合时记 warning 并丢到结尾。
fn strip_comments(s : String, warns : Array[String]) -> String {
  let out : Array[Char] = []
  let n = s.char_length()
  let mut i = 0
  let mut unterminated = false
  while i < n {
    if char_at(s, i) == '/' && i + 1 < n && char_at(s, i + 1) == '*' {
      i = i + 2
      let mut closed = false
      while i < n && !closed {
        if char_at(s, i) == '*' && i + 1 < n && char_at(s, i + 1) == '/' {
          i = i + 2
          closed = true
        } else {
          i = i + 1
        }
      }
      if !closed {
        unterminated = true
      }
    } else {
      out.push(char_at(s, i))
      i = i + 1
    }
  }
  if unterminated {
    warns.push("unterminated comment")
  }
  String::from_iter(out.iter())
}

///|
/// 从 start 开始找配对的 '}'，返回 (结束下标, 是否闭合)。
fn find_block_end(s : String, start : Int32) -> (Int32, Bool) {
  let n = s.char_length()
  let mut depth = 1
  let mut i = start
  while i < n {
    let c = char_at(s, i)
    if c == '{' {
      depth = depth + 1
    } else if c == '}' {
      depth = depth - 1
      if depth == 0 {
        return (i, true)
      }
    }
    i = i + 1
  }
  (n, false)
}

///|
/// 跳过一条 at-rule（含块），返回下一条规则的下标。
fn skip_at_rule(s : String, start : Int32) -> Int32 {
  let n = s.char_length()
  let mut i = start + 1
  while i < n {
    let c = char_at(s, i)
    if c == ';' {
      return i + 1
    }
    if c == '{' {
      let end = find_block_end(s, i + 1)
      return if end.1 { end.0 + 1 } else { n }
    }
    i = i + 1
  }
  n
}

///|
fn parse_declarations(block : String, warns : Array[String]) -> Array[Decl] {
  let out : Array[Decl] = []
  let nested = match find_char(block, '{') {
    Some(_) => true
    None => false
  }
  if nested {
    warns.push("nested block inside declarations skipped")
  } else {
    for seg in split_on(block, ';') {
      let t = trim_ws(seg)
      if t != "" {
        match find_char(t, ':') {
          None => warns.push("malformed declaration skipped")
          Some(colon) => {
            let name = trim_ws(slice_text(t, 0, colon)).to_lower()
            let raw = slice_text(t, colon + 1, t.char_length())
            let stripped = strip_important(raw)
            match parse_property(name, stripped.0) {
              RUnknown => warns.push("unknown property skipped: " + name)
              RInvalid(props) => {
                warns.push(
                  "invalid value for " + name + ", fallback to initial",
                )
                for p in props {
                  out.push({
                    prop: p,
                    value: initial_value(p),
                    important: stripped.1,
                  })
                }
              }
              ROk(decls) =>
                for d in decls {
                  out.push({ prop: d.0, value: d.1, important: stripped.1, })
                }
            }
          }
        }
      }
    }
  }
  out
}

///|
pub fn Stylesheet::parse(css : String) -> Stylesheet {
  let rules : Array[Rule] = []
  let warns : Array[String] = []
  let text = strip_comments(css, warns)
  let n = text.char_length()
  let mut i = 0
  let mut order : Int32 = 0
  while i < n {
    let c = char_at(text, i)
    if is_ascii_ws(c) {
      i = i + 1
    } else if c == '@' {
      warns.push("at-rule not supported, skipped")
      i = skip_at_rule(text, i)
    } else if c == '}' || c == ';' {
      warns.push("unexpected token skipped: " + slice_text(text, i, i + 1))
      i = i + 1
    } else {
      // 读到 '{' 前是选择器
      let mut j = i
      let mut stop = false
      while j < n && !stop {
        let ch = char_at(text, j)
        if ch == '{' || ch == ';' || ch == '}' {
          stop = true
        } else {
          j = j + 1
        }
      }
      if j >= n {
        warns.push("truncated rule: missing '{'")
        i = n
      } else if char_at(text, j) != '{' {
        warns.push("declaration outside a rule skipped")
        i = j + 1
      } else {
        let prelude = trim_ws(slice_text(text, i, j))
        let block_end = find_block_end(text, j + 1)
        let block = slice_text(text, j + 1, block_end.0)
        if !block_end.1 {
          warns.push("unterminated rule block")
        }
        match parse_selector_list(prelude) {
          None => warns.push("unsupported selector skipped: " + prelude)
          Some(sels) => {
            let decls = parse_declarations(block, warns)
            if decls.length() > 0 {
              rules.push({ selectors: sels, decls, order, })
              order = order + 1
            } else {
              warns.push("rule has no usable declarations")
            }
          }
        }
        i = if block_end.1 { block_end.0 + 1 } else { n }
      }
    }
  }
  { rules, warns, }
}

///|
/// 解析期的 warning，按产生顺序返回。
pub fn Stylesheet::warnings(self : Stylesheet) -> Array[String] {
  let out : Array[String] = []
  for w in self.warns {
    out.push(w)
  }
  out
}

///|
/// 成功解析的规则条数（选择器不合法或没有可用声明的规则不计）。
pub fn Stylesheet::rule_count(self : Stylesheet) -> Int32 {
  self.rules.length()
}
