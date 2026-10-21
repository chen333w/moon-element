///|
/// 把一个 `:host` 风格的样式表改写为「以 `scope` 为根」的普通样式表。
///
/// **用途**：在不能使用 shadow DOM 的场合（SSR 输出、light DOM 组件、老环境），
/// 用一层选择器前缀达到同样的样式隔离效果。
///
/// 规则：
/// - 普通规则：每个选择器加 `scope ` 前缀（后代选择器）
/// - `:host` → 替换为 scope；`:host(.active)` → `scope.active`；`:host .child` → `scope .child`
/// - 逗号分隔的选择器逐个处理，并且**括号内的逗号不算分隔符**（`:is(a, b)` 不会被拆开）
/// - `@media` / `@supports` / `@container` / `@layer`：递归处理内部的规则
/// - 其它 at-rule（如 `@keyframes`）：原样保留——keyframes 的选择器是 `from`/`0%`，不能加前缀
/// - 注释原样保留
/// - `scope` 为空串时是恒等操作（不做任何改写）
///
/// **已知限制**（刻意不做的部分，避免写一个完整的 CSS 解析器）：
/// - 声明块内部原样输出，不做压缩或重排
/// - 字符串字面量或注释里出现的 `{` / `}` 会干扰块匹配
/// - `::slotted()` / `:host-context()` 属于 shadow DOM 语义，未做等价转换
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
/// 扫描 `[start, end)` 的 CSS 片段并把作用域化的结果写入 `out`。
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
      // 注释：原样拷贝到 "*/"
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
      // 收集 prelude，直到 '{' 或 ';'
      let prelude : Array[Char] = []
      let mut j = i
      while j < end && chars[j] != '{' && chars[j] != ';' {
        prelude.push(chars[j])
        j = j + 1
      }
      if j >= end || chars[j] == ';' {
        // at-statement（如 @import）或残缺输入：原样输出
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
        // 找到匹配的 '}'
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
/// 把一条规则的 prelude + 块内容写出去（块内容按规则不同或改写或原样）。
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
      // 递归处理组内规则
      copy_trimmed(prelude, out)
      out.push(' ')
      out.push('{')
      scope_range(chars, inner_start, inner_end, scope, out)
      out.push('}')
    } else {
      // @keyframes 等：整条原样保留
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
/// prelude 是否以 `@media` / `@supports` / `@container` / `@layer` 开头（大小写不敏感）。
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
/// 处理逗号分隔的选择器列表：逐个加 scope 前缀，用 `, ` 连接。
/// 括号深度 > 0 时的逗号不当作分隔符。
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
/// 写单个选择器：先归一化空白，再按 `:host` 规则改写。
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
    // :host → scope，并保留其后内容
    push_string(out, scope)
    if n > 5 && norm[5] == '(' {
      // :host(.active) → scope.active
      // 括号内是**复合选择器**，要直接接在 scope 后面（去掉括号本身），
      // 而不是把括号原样搬过去——否则会输出 scope(.active)，在 CSS 里是无效选择器。
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
/// 归一化选择器空白：连续空白压成一个空格，去掉首尾空白。
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
