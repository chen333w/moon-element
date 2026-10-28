// 层叠与计算值。每个节点只遍历一遍规则，O(nodes × rules)。

///|
/// 命中选择器的特异度（id 数, class 数, tag 数）。
priv struct Spec {
  id : Int32
  class_count : Int32
  tag : Int32
}

///|
/// 某个长属性当前最优声明，用来做层叠比较。
priv struct Best {
  important : Bool
  inline : Bool
  id : Int32
  class_count : Int32
  tag : Int32
  order : Int32
  value : Value
}

///|
fn spec_better(a : Spec, b : Spec) -> Bool {
  if a.id != b.id {
    return a.id > b.id
  }
  if a.class_count != b.class_count {
    return a.class_count > b.class_count
  }
  a.tag > b.tag
}

///|
/// 一条规则对某个节点是否命中；命中时返回特异度最高的那个选择器的特异度。
fn match_rule(rule : Rule, nodes : Array[ElementInfo], idx : Int32) -> Spec? {
  let mut best : Spec? = None
  for sel in rule.selectors {
    if selector_matches(sel, nodes, idx) {
      let sp : Spec = {
        id: sel.spec_id,
        class_count: sel.spec_class,
        tag: sel.spec_tag,
      }
      let take = match best {
        None => true
        Some(cur) => spec_better(sp, cur)
      }
      if take {
        best = Some(sp)
      }
    }
  }
  best
}

///|
/// 层叠比较：important > 行内 > 特异度 > 源顺序。
fn cand_better(a : Best, b : Best) -> Bool {
  if a.important != b.important {
    return a.important
  }
  if a.inline != b.inline {
    return a.inline
  }
  if a.id != b.id {
    return a.id > b.id
  }
  if a.class_count != b.class_count {
    return a.class_count > b.class_count
  }
  if a.tag != b.tag {
    return a.tag > b.tag
  }
  a.order > b.order
}

///|
fn consider(
  best : Array[Best?],
  decl : Decl,
  is_inline : Bool,
  spec : Spec,
  order : Int32,
) -> Unit {
  let idx = prop_index(decl.prop)
  let cand : Best = {
    important: decl.important,
    inline: is_inline,
    id: spec.id,
    class_count: spec.class_count,
    tag: spec.tag,
    order,
    value: decl.value,
  }
  let take = match best[idx] {
    None => true
    Some(cur) => cand_better(cand, cur)
  }
  if take {
    best[idx] = Some(cand)
  }
}

///|
fn value_of(best : Array[Best?], p : Prop) -> Value? {
  match best[prop_index(p)] {
    Some(b) => Some(b.value)
    None => None
  }
}

///|
/// 字号：em 相对父字号，rem 相对 16px，百分比也相对父字号。
fn resolve_font_size(v : Value?, parent_font : Double) -> Double {
  match v {
    Some(VLength(l)) =>
      match l {
        Px(x) => x
        Em(x) => parent_font * x
        Rem(x) => 16.0 * x
        Percent(x) => parent_font * x / 100.0
        Auto => parent_font
      }
    _ => parent_font
  }
}

///|
/// 解析成 px。百分比依赖包含块宽度，本阶段不可解，按 0 处理，留给 layout。
fn resolve_px(v : Value?, font_size : Double) -> Double {
  match v {
    Some(VLength(l)) =>
      match l {
        Px(x) => x
        Em(x) => font_size * x
        Rem(x) => 16.0 * x
        Percent(_) => 0.0
        Auto => 0.0
      }
    _ => 0.0
  }
}

///|
fn length_of(v : Value?, fallback : Length) -> Length {
  match v {
    Some(VLength(l)) => l
    _ => fallback
  }
}

///|
/// currentColor 用自身 color 解析。
fn color_of(v : Value?, current : Rgba, fallback : Rgba) -> Rgba {
  match v {
    Some(VColor(c, is_current)) => if is_current { current } else { c }
    _ => fallback
  }
}

///|
fn edges_of(
  top : Value?,
  right : Value?,
  bottom : Value?,
  left : Value?,
  font_size : Double,
) -> Edges {
  {
    top: resolve_px(top, font_size),
    right: resolve_px(right, font_size),
    bottom: resolve_px(bottom, font_size),
    left: resolve_px(left, font_size),
  }
}

///|
fn build_style(
  best : Array[Best?],
  parent_font : Double,
  parent_color : Rgba,
) -> ComputedStyle {
  // 字号先算，em 依赖它
  let font_size = resolve_font_size(value_of(best, PFontSize), parent_font)
  let color = match value_of(best, PColor) {
    Some(VColor(c, is_current)) => if is_current { parent_color } else { c }
    _ => parent_color
  }
  let background_color = color_of(
    value_of(best, PBackgroundColor),
    color,
    Rgba::transparent(),
  )
  let border_color = color_of(
    value_of(best, PBorderColor),
    color,
    Rgba::transparent(),
  )
  let display = match value_of(best, PDisplay) {
    Some(VDisplay(d)) => d
    _ => Display::Block
  }
  let flex_direction = match value_of(best, PFlexDirection) {
    Some(VDirection(d)) => d
    _ => FlexDirection::Row
  }
  let flex_wrap = match value_of(best, PFlexWrap) {
    Some(VWrap(w)) => w
    _ => FlexWrap::NoWrap
  }
  let justify_content = match value_of(best, PJustifyContent) {
    Some(VJustify(j)) => j
    _ => Justify::Start
  }
  let align_items = match value_of(best, PAlignItems) {
    Some(VAlign(a)) => a
    _ => Align::Stretch
  }
  let flex_grow = match value_of(best, PFlexGrow) {
    Some(VNumber(n)) => n
    _ => 0.0
  }
  let flex_shrink = match value_of(best, PFlexShrink) {
    Some(VNumber(n)) => n
    _ => 1.0
  }
  let style : ComputedStyle = {
    display,
    width: length_of(value_of(best, PWidth), Length::Auto),
    height: length_of(value_of(best, PHeight), Length::Auto),
    min_width: length_of(value_of(best, PMinWidth), Length::Auto),
    max_width: length_of(value_of(best, PMaxWidth), Length::Auto),
    padding: edges_of(
      value_of(best, PPaddingTop),
      value_of(best, PPaddingRight),
      value_of(best, PPaddingBottom),
      value_of(best, PPaddingLeft),
      font_size,
    ),
    border: edges_of(
      value_of(best, PBorderTop),
      value_of(best, PBorderRight),
      value_of(best, PBorderBottom),
      value_of(best, PBorderLeft),
      font_size,
    ),
    margin: edges_of(
      value_of(best, PMarginTop),
      value_of(best, PMarginRight),
      value_of(best, PMarginBottom),
      value_of(best, PMarginLeft),
      font_size,
    ),
    gap: resolve_px(value_of(best, PGap), font_size),
    flex_direction,
    flex_wrap,
    justify_content,
    align_items,
    flex_grow,
    flex_shrink,
    flex_basis: length_of(value_of(best, PFlexBasis), Length::Auto),
    font_size,
    color,
    background_color,
    border_color,
    border_radius: resolve_px(value_of(best, PBorderRadius), font_size),
  }
  style
}

///|
/// 计算每个节点的值。输入按前序遍历，父节点下标一定小于子节点，
/// 所以父样式已经在结果数组里，可以直接取。
pub fn Stylesheet::compute(
  self : Stylesheet,
  nodes : Array[ElementInfo],
) -> Array[ComputedStyle] {
  let out : Array[ComputedStyle] = []
  let total = nodes.length()
  let inline_spec : Spec = { id: 0, class_count: 0, tag: 0, }
  let mut i = 0
  while i < total {
    let best : Array[Best?] = Array::make(prop_count(), None)
    // 1) 规则层叠
    for rule in self.rules {
      match match_rule(rule, nodes, i) {
        None => ()
        Some(sp) =>
          for decl in rule.decls {
            consider(best, decl, false, sp, rule.order)
          }
      }
    }
    // 2) 行内 style：优先级高于所有选择器
    let node = nodes[i]
    let mut inline_order : Int32 = 0
    for pair in node.inline {
      let name = trim_ws(pair.0).to_lower()
      let stripped = strip_important(pair.1)
      match parse_property(name, stripped.0) {
        RUnknown => ()
        RInvalid(props) =>
          for p in props {
            consider(
              best,
              { prop: p, value: initial_value(p), important: stripped.1, },
              true,
              inline_spec,
              inline_order,
            )
            inline_order = inline_order + 1
          }
        ROk(decls) =>
          for d in decls {
            consider(
              best,
              { prop: d.0, value: d.1, important: stripped.1, },
              true,
              inline_spec,
              inline_order,
            )
            inline_order = inline_order + 1
          }
      }
    }
    // 3) 继承：color 与 font-size 取父节点，其余用 initial
    let mut parent_font = 16.0
    let mut parent_color = Rgba::black()
    if node.parent >= 0 {
      match out.get(node.parent) {
        Some(parent_style) => {
          parent_font = parent_style.font_size
          parent_color = parent_style.color
        }
        None => ()
      }
    }
    out.push(build_style(best, parent_font, parent_color))
    i = i + 1
  }
  out
}
