// 选择器解析与匹配。只支持 CSS 的一个可用子集，其余写法整条规则跳过。

///|
pub enum Combinator {
  Descendant
  Child
}

///|
/// 一个复合选择器，例如 `div.a#x`；空字段表示不限制。
pub struct Compound {
  tag : String
  id : String
  classes : Array[String]
}

///|
pub struct Selector {
  /// 从左到右的复合选择器
  compounds : Array[Compound]
  /// 相邻复合选择器之间的关系，长度比 compounds 少一
  combinators : Array[Combinator]
  spec_id : Int32
  spec_class : Int32
  spec_tag : Int32
}

///|
priv enum SelTok {
  TSpace
  TChild
  TCompound(Compound)
}

///|
fn tokenize_selector(s : String) -> Array[SelTok]? {
  let out : Array[SelTok] = []
  let n = s.char_length()
  let mut i = 0
  while i < n {
    let c = char_at(s, i)
    if is_ascii_ws(c) {
      out.push(TSpace)
      i = i + 1
    } else if c == '>' {
      out.push(TChild)
      i = i + 1
    } else {
      let mut tag = ""
      let mut id = ""
      let classes : Array[String] = []
      let mut universal = false
      let mut progress = false
      let mut stop = false
      while !stop {
        if i >= n {
          stop = true
        } else {
          let ch = char_at(s, i)
          if is_ascii_ws(ch) || ch == '>' {
            stop = true
          } else if ch == '*' {
            // 通配符只能单独构成一个复合选择器
            if universal || tag != "" || id != "" || classes.length() > 0 {
              return None
            }
            universal = true
            progress = true
            i = i + 1
          } else if ch == '.' {
            let pair = read_ident(s, i + 1)
            if pair.0 == "" {
              return None
            }
            classes.push(pair.0)
            progress = true
            i = pair.1
          } else if ch == '#' {
            let pair = read_ident(s, i + 1)
            if pair.0 == "" || id != "" {
              return None
            }
            id = pair.0
            progress = true
            i = pair.1
          } else if is_ident_char(ch) {
            if tag != "" || universal {
              return None
            }
            let pair = read_ident(s, i)
            tag = pair.0
            progress = true
            i = pair.1
          } else {
            // 伪类、属性选择器、兄弟组合子都不支持
            return None
          }
        }
      }
      if !progress {
        return None
      }
      out.push(TCompound({ tag, id, classes, }))
    }
  }
  Some(out)
}

///|
fn skip_spaces(toks : Array[SelTok], pos : Int32) -> Int32 {
  let n = toks.length()
  let mut i = pos
  while i < n {
    let is_space = match toks[i] {
      TSpace => true
      _ => false
    }
    if !is_space {
      break
    }
    i = i + 1
  }
  i
}

///|
fn build_selector(toks : Array[SelTok]) -> Selector? {
  let n = toks.length()
  let mut pos = skip_spaces(toks, 0)
  if pos >= n {
    return None
  }
  let first = match toks[pos] {
    TCompound(c) => c
    _ => return None
  }
  let compounds : Array[Compound] = [first]
  let combinators : Array[Combinator] = []
  pos = pos + 1
  let mut done = false
  while !done {
    let after_space = skip_spaces(toks, pos)
    if after_space >= n {
      done = true
    } else {
      let mut comb = Descendant
      let mut next = after_space
      match toks[after_space] {
        TChild => {
          comb = Child
          next = skip_spaces(toks, after_space + 1)
        }
        _ => ()
      }
      if next >= n {
        // 组合子后面没有选择器，例如 "a >"
        return None
      }
      match toks[next] {
        TCompound(c) => {
          combinators.push(comb)
          compounds.push(c)
          pos = next + 1
        }
        _ => return None
      }
    }
  }
  let mut spec_id = 0
  let mut spec_class = 0
  let mut spec_tag = 0
  for c in compounds {
    if c.id != "" {
      spec_id = spec_id + 1
    }
    spec_class = spec_class + c.classes.length()
    if c.tag != "" {
      spec_tag = spec_tag + 1
    }
  }
  Some({ compounds, combinators, spec_id, spec_class, spec_tag, })
}

///|
fn parse_selector(s : String) -> Selector? {
  match tokenize_selector(s) {
    None => None
    Some(toks) => build_selector(toks)
  }
}

///|
/// 逗号分隔的选择器列表；任意一项不合法则整条规则作废。
fn parse_selector_list(s : String) -> Array[Selector]? {
  let out : Array[Selector] = []
  for part in split_on(s, ',') {
    let t = trim_ws(part)
    if t == "" {
      return None
    }
    match parse_selector(t) {
      None => return None
      Some(sel) => out.push(sel)
    }
  }
  if out.length() == 0 {
    None
  } else {
    Some(out)
  }
}

///|
fn has_class(classes : Array[String], want : String) -> Bool {
  for c in classes {
    if c == want {
      return true
    }
  }
  false
}

///|
fn compound_matches(c : Compound, node : ElementInfo) -> Bool {
  if c.tag != "" && c.tag != node.tag {
    return false
  }
  if c.id != "" && c.id != node.id {
    return false
  }
  for want in c.classes {
    if !has_class(node.classes, want) {
      return false
    }
  }
  true
}

///|
fn parent_of(nodes : Array[ElementInfo], idx : Int32) -> Int32 {
  match nodes.get(idx) {
    Some(node) => node.parent
    None => -1
  }
}

///|
/// 从右往左匹配：先匹配最右边的复合选择器，再沿 parent 链满足组合子。
fn selector_matches(
  sel : Selector,
  nodes : Array[ElementInfo],
  idx : Int32,
) -> Bool {
  let total = sel.compounds.length()
  if total == 0 {
    return false
  }
  if sel.combinators.length() != total - 1 {
    return false
  }
  let first_ok = match nodes.get(idx) {
    None => false
    Some(node) => compound_matches(sel.compounds[total - 1], node)
  }
  if !first_ok {
    return false
  }
  let mut node_idx = idx
  let mut k = total - 1
  while k > 0 {
    let comb = sel.combinators[k - 1]
    let prev = k - 1
    let mut matched = false
    match comb {
      Child => {
        let parent = parent_of(nodes, node_idx)
        if parent >= 0 {
          match nodes.get(parent) {
            Some(pnode) =>
              if compound_matches(sel.compounds[prev], pnode) {
                matched = true
                node_idx = parent
              }
            None => ()
          }
        }
      }
      Descendant => {
        let mut cur = parent_of(nodes, node_idx)
        while cur >= 0 && !matched {
          match nodes.get(cur) {
            Some(pnode) =>
              if compound_matches(sel.compounds[prev], pnode) {
                matched = true
                node_idx = cur
              } else {
                cur = pnode.parent
              }
            None => cur = -1
          }
        }
      }
    }
    if !matched {
      return false
    }
    k = k - 1
  }
  true
}
