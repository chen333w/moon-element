// 声明值解析与简写展开。解析失败一律返回 RInvalid，由调用方回退 initial 并记 warning。

///|
/// 属性名 + 值文本的解析结果。
priv enum PropResult {
  /// 不认识属性名
  RUnknown
  /// 值无法解析：这些长属性回退 initial
  RInvalid(Array[Prop])
  /// 成功展开成长属性
  ROk(Array[(Prop, Value)])
}

///|
fn parse_length(raw : String) -> Length? {
  let t = trim_ws(raw)
  if t == "" {
    return None
  }
  let lower = t.to_lower()
  if lower == "auto" {
    return Some(Length::Auto)
  }
  if lower == "none" {
    return None
  }
  match scan_number_at(t, 0) {
    None => None
    Some(pair) => {
      let v = pair.0
      let unit = trim_ws(slice_text(t, pair.1, t.char_length())).to_lower()
      if unit == "" {
        // 无单位只在 0 上合法
        if v == 0.0 {
          Some(Length::Px(0.0))
        } else {
          None
        }
      } else if unit == "px" {
        Some(Length::Px(v))
      } else if unit == "em" {
        Some(Length::Em(v))
      } else if unit == "rem" {
        Some(Length::Rem(v))
      } else if unit == "%" {
        Some(Length::Percent(v))
      } else {
        None
      }
    }
  }
}

///|
fn parse_number(raw : String) -> Double? {
  let t = trim_ws(raw)
  if t == "" {
    return None
  }
  match scan_number_at(t, 0) {
    None => None
    Some(pair) => if pair.1 == t.char_length() { Some(pair.0) } else { None }
  }
}

///|
fn named_color(low : String) -> Rgba? {
  if low == "black" {
    Some({ r: 0, g: 0, b: 0, a: 1.0, })
  } else if low == "white" {
    Some({ r: 255, g: 255, b: 255, a: 1.0, })
  } else if low == "red" {
    Some({ r: 255, g: 0, b: 0, a: 1.0, })
  } else if low == "blue" {
    Some({ r: 0, g: 0, b: 255, a: 1.0, })
  } else if low == "green" {
    Some({ r: 0, g: 128, b: 0, a: 1.0, })
  } else if low == "gray" || low == "grey" {
    Some({ r: 128, g: 128, b: 128, a: 1.0, })
  } else {
    None
  }
}

///|
fn clamp_channel(v : Double) -> Int32 {
  let n = v.to_int()
  if n < 0 {
    0
  } else if n > 255 {
    255
  } else {
    n
  }
}

///|
fn clamp_alpha(v : Double) -> Double {
  if v < 0.0 {
    0.0
  } else if v > 1.0 {
    1.0
  } else {
    v
  }
}

///|
/// 按逗号或空白切出数字，用于 rgb() 参数。
fn split_numbers(s : String) -> Array[Double]? {
  let out : Array[Double] = []
  let n = s.char_length()
  let mut i = 0
  while i < n {
    if is_ws_at(s, i) || char_at(s, i) == ',' {
      i = i + 1
    } else {
      match scan_number_at(s, i) {
        Some(pair) => {
          out.push(pair.0)
          i = pair.1
        }
        None => return None
      }
    }
  }
  Some(out)
}

///|
fn hex_pair(digits : String, at : Int32) -> Int32? {
  match (hex_of(char_at(digits, at)), hex_of(char_at(digits, at + 1))) {
    (Some(hi), Some(lo)) => Some(hi * 16 + lo)
    _ => None
  }
}

///|
fn parse_hex(digits : String) -> Rgba? {
  let n = digits.char_length()
  if n == 3 {
    let r = hex_of(char_at(digits, 0))
    let g = hex_of(char_at(digits, 1))
    let b = hex_of(char_at(digits, 2))
    match (r, g, b) {
      (Some(rv), Some(gv), Some(bv)) =>
        Some({ r: rv * 16 + rv, g: gv * 16 + gv, b: bv * 16 + bv, a: 1.0, })
      _ => None
    }
  } else if n == 6 {
    match (hex_pair(digits, 0), hex_pair(digits, 2), hex_pair(digits, 4)) {
      (Some(rv), Some(gv), Some(bv)) => Some({ r: rv, g: gv, b: bv, a: 1.0, })
      _ => None
    }
  } else {
    None
  }
}

///|
fn parse_color_syntax(t : String) -> Rgba? {
  let n = t.char_length()
  if n > 0 && char_at(t, 0) == '#' {
    return parse_hex(slice_text(t, 1, n))
  }
  let lower = t.to_lower()
  if starts_with(lower, "rgb(") && ends_with(lower, ")") {
    let inner = slice_text(t, 4, n - 1)
    match split_numbers(inner) {
      None => None
      Some(channels) => {
        let m = channels.length()
        if m == 3 {
          Some({
            r: clamp_channel(channels[0]),
            g: clamp_channel(channels[1]),
            b: clamp_channel(channels[2]),
            a: 1.0,
          })
        } else if m == 4 {
          Some({
            r: clamp_channel(channels[0]),
            g: clamp_channel(channels[1]),
            b: clamp_channel(channels[2]),
            a: clamp_alpha(channels[3]),
          })
        } else {
          None
        }
      }
    }
  } else {
    None
  }
}

///|
fn parse_color(raw : String) -> Value? {
  let t = trim_ws(raw)
  if t == "" {
    return None
  }
  let lower = t.to_lower()
  if lower == "transparent" {
    return Some(VColor(Rgba::transparent(), false))
  }
  if lower == "currentcolor" {
    // 具体颜色在计算期才知道，这里只打标记
    return Some(VColor(Rgba::black(), true))
  }
  match named_color(lower) {
    Some(c) => Some(VColor(c, false))
    None =>
      match parse_color_syntax(t) {
        Some(c) => Some(VColor(c, false))
        None => None
      }
  }
}

///|
fn single_length(value : String, props : Array[Prop]) -> PropResult {
  match parse_length(value) {
    Some(l) => ROk([(props[0], VLength(l))])
    None => RInvalid(props)
  }
}

///|
fn single_color(value : String, props : Array[Prop]) -> PropResult {
  match parse_color(value) {
    Some(c) => ROk([(props[0], c)])
    None => RInvalid(props)
  }
}

///|
fn single_number(value : String, props : Array[Prop]) -> PropResult {
  match parse_number(value) {
    Some(n) => ROk([(props[0], VNumber(n))])
    None => RInvalid(props)
  }
}

///|
/// padding / margin / border-width：1~4 个长度，按 CSS 的四值规则展开。
fn expand_box(props : Array[Prop], value : String) -> PropResult {
  let toks = split_ws(value)
  let m = toks.length()
  if m < 1 || m > 4 {
    return RInvalid(props)
  }
  let lens : Array[Length] = []
  for t in toks {
    match parse_length(t) {
      Some(l) => lens.push(l)
      None => return RInvalid(props)
    }
  }
  let top = lens[0]
  let right = if m >= 2 { lens[1] } else { top }
  let bottom = if m >= 3 { lens[2] } else { top }
  let left = if m >= 4 { lens[3] } else { right }
  ROk([
    (props[0], VLength(top)),
    (props[1], VLength(right)),
    (props[2], VLength(bottom)),
    (props[3], VLength(left)),
  ])
}

///|
fn is_border_style_kw(low : String) -> Bool {
  low == "solid" ||
  low == "dashed" ||
  low == "dotted" ||
  low == "double" ||
  low == "groove" ||
  low == "ridge" ||
  low == "inset" ||
  low == "outset"
}

///|
/// border 简写：只取宽度与颜色，样式关键字仅用于识别。
fn parse_border(value : String) -> PropResult {
  let props = [
    PBorderTop,
    PBorderRight,
    PBorderBottom,
    PBorderLeft,
    PBorderColor,
  ]
  let toks = split_ws(value)
  if toks.length() == 0 {
    return RInvalid(props)
  }
  let mut width : Length? = None
  let mut color : Value? = None
  for t in toks {
    let low = t.to_lower()
    if low == "none" {
      width = Some(Length::Px(0.0))
    } else if !is_border_style_kw(low) {
      match parse_color(t) {
        Some(c) => color = Some(c)
        None =>
          match parse_length(t) {
            Some(l) => width = Some(l)
            None => return RInvalid(props)
          }
      }
    }
  }
  let w = match width {
    Some(l) => l
    None => Length::Px(0.0)
  }
  // 未写颜色时简写会把它设为 currentColor
  let c = match color {
    Some(v) => v
    None => VColor(Rgba::black(), true)
  }
  ROk([
    (PBorderTop, VLength(w)),
    (PBorderRight, VLength(w)),
    (PBorderBottom, VLength(w)),
    (PBorderLeft, VLength(w)),
    (PBorderColor, c),
  ])
}

///|
fn parse_basis(raw : String) -> Length? {
  let t = trim_ws(raw)
  if t.to_lower() == "auto" {
    return Some(Length::Auto)
  }
  parse_length(t)
}

///|
/// flex 简写：单值/双值/三值与 none、auto 关键字。
fn parse_flex(value : String) -> PropResult {
  let props = [PFlexGrow, PFlexShrink, PFlexBasis]
  let toks = split_ws(value)
  let m = toks.length()
  if m == 0 {
    return RInvalid(props)
  }
  if m == 1 {
    let low = toks[0].to_lower()
    if low == "none" {
      return ROk([
        (PFlexGrow, VNumber(0.0)),
        (PFlexShrink, VNumber(0.0)),
        (PFlexBasis, VLength(Length::Auto)),
      ])
    }
    if low == "auto" {
      return ROk([
        (PFlexGrow, VNumber(1.0)),
        (PFlexShrink, VNumber(1.0)),
        (PFlexBasis, VLength(Length::Auto)),
      ])
    }
    match parse_number(toks[0]) {
      Some(n) =>
        return ROk([
          (PFlexGrow, VNumber(n)),
          (PFlexShrink, VNumber(1.0)),
          (PFlexBasis, VLength(Length::Px(0.0))),
        ])
      None => ()
    }
    match parse_basis(toks[0]) {
      Some(l) =>
        return ROk([
          (PFlexGrow, VNumber(1.0)),
          (PFlexShrink, VNumber(1.0)),
          (PFlexBasis, VLength(l)),
        ])
      None => return RInvalid(props)
    }
  }
  if m == 2 {
    match parse_number(toks[0]) {
      None => RInvalid(props)
      Some(g) =>
        match parse_number(toks[1]) {
          Some(sh) =>
            ROk([
              (PFlexGrow, VNumber(g)),
              (PFlexShrink, VNumber(sh)),
              (PFlexBasis, VLength(Length::Px(0.0))),
            ])
          None =>
            match parse_basis(toks[1]) {
              Some(l) =>
                ROk([
                  (PFlexGrow, VNumber(g)),
                  (PFlexShrink, VNumber(1.0)),
                  (PFlexBasis, VLength(l)),
                ])
              None => RInvalid(props)
            }
        }
    }
  } else if m == 3 {
    match (parse_number(toks[0]), parse_number(toks[1])) {
      (Some(g), Some(sh)) =>
        match parse_basis(toks[2]) {
          Some(l) =>
            ROk([
              (PFlexGrow, VNumber(g)),
              (PFlexShrink, VNumber(sh)),
              (PFlexBasis, VLength(l)),
            ])
          None => RInvalid(props)
        }
      _ => RInvalid(props)
    }
  } else {
    RInvalid(props)
  }
}

///|
/// font 简写：只取字号，忽略字重、字族与 “/行高”。
fn parse_font(value : String) -> PropResult {
  let props = [PFontSize]
  for t in split_ws(value) {
    let head = match find_char(t, '/') {
      Some(i) => slice_text(t, 0, i)
      None => t
    }
    match parse_basis(head) {
      Some(l) => return ROk([(PFontSize, VLength(l))])
      None => ()
    }
  }
  RInvalid(props)
}

///|
fn parse_display(value : String) -> PropResult {
  let low = trim_ws(value).to_lower()
  if low == "block" {
    ROk([(PDisplay, VDisplay(Display::Block))])
  } else if low == "flex" {
    ROk([(PDisplay, VDisplay(Display::Flex))])
  } else if low == "none" {
    ROk([(PDisplay, VDisplay(Display::None))])
  } else {
    RInvalid([PDisplay])
  }
}

///|
fn parse_direction(value : String) -> PropResult {
  let low = trim_ws(value).to_lower()
  if low == "row" {
    ROk([(PFlexDirection, VDirection(FlexDirection::Row))])
  } else if low == "column" {
    ROk([(PFlexDirection, VDirection(FlexDirection::Column))])
  } else {
    RInvalid([PFlexDirection])
  }
}

///|
fn parse_wrap(value : String) -> PropResult {
  let low = trim_ws(value).to_lower()
  if low == "nowrap" {
    ROk([(PFlexWrap, VWrap(FlexWrap::NoWrap))])
  } else if low == "wrap" {
    ROk([(PFlexWrap, VWrap(FlexWrap::Wrap))])
  } else {
    RInvalid([PFlexWrap])
  }
}

///|
fn parse_justify(value : String) -> PropResult {
  let low = trim_ws(value).to_lower()
  if low == "start" || low == "flex-start" {
    ROk([(PJustifyContent, VJustify(Justify::Start))])
  } else if low == "center" {
    ROk([(PJustifyContent, VJustify(Justify::Center))])
  } else if low == "end" || low == "flex-end" {
    ROk([(PJustifyContent, VJustify(Justify::End))])
  } else if low == "space-between" {
    ROk([(PJustifyContent, VJustify(Justify::SpaceBetween))])
  } else if low == "space-around" {
    ROk([(PJustifyContent, VJustify(Justify::SpaceAround))])
  } else if low == "space-evenly" {
    ROk([(PJustifyContent, VJustify(Justify::SpaceEvenly))])
  } else {
    RInvalid([PJustifyContent])
  }
}

///|
fn parse_align(value : String) -> PropResult {
  let low = trim_ws(value).to_lower()
  if low == "stretch" {
    ROk([(PAlignItems, VAlign(Align::Stretch))])
  } else if low == "start" || low == "flex-start" {
    ROk([(PAlignItems, VAlign(Align::Start))])
  } else if low == "center" {
    ROk([(PAlignItems, VAlign(Align::Center))])
  } else if low == "end" || low == "flex-end" {
    ROk([(PAlignItems, VAlign(Align::End))])
  } else {
    RInvalid([PAlignItems])
  }
}

///|
/// 属性名（已小写）加值文本 → 展开后的长属性声明。
fn parse_property(name : String, value : String) -> PropResult {
  match name {
    "display" => parse_display(value)
    "width" => single_length(value, [PWidth])
    "height" => single_length(value, [PHeight])
    "min-width" => single_length(value, [PMinWidth])
    "max-width" => single_length(value, [PMaxWidth])
    "padding" =>
      expand_box(
        [PPaddingTop, PPaddingRight, PPaddingBottom, PPaddingLeft],
        value,
      )
    "padding-top" => single_length(value, [PPaddingTop])
    "padding-right" => single_length(value, [PPaddingRight])
    "padding-bottom" => single_length(value, [PPaddingBottom])
    "padding-left" => single_length(value, [PPaddingLeft])
    "margin" =>
      expand_box([PMarginTop, PMarginRight, PMarginBottom, PMarginLeft], value)
    "margin-top" => single_length(value, [PMarginTop])
    "margin-right" => single_length(value, [PMarginRight])
    "margin-bottom" => single_length(value, [PMarginBottom])
    "margin-left" => single_length(value, [PMarginLeft])
    "border" => parse_border(value)
    "border-width" =>
      expand_box([PBorderTop, PBorderRight, PBorderBottom, PBorderLeft], value)
    "border-color" => single_color(value, [PBorderColor])
    "border-radius" => single_length(value, [PBorderRadius])
    "gap" => single_length(value, [PGap])
    "flex" => parse_flex(value)
    "flex-basis" => single_length(value, [PFlexBasis])
    "flex-grow" => single_number(value, [PFlexGrow])
    "flex-shrink" => single_number(value, [PFlexShrink])
    "flex-direction" => parse_direction(value)
    "flex-wrap" => parse_wrap(value)
    "justify-content" => parse_justify(value)
    "align-items" => parse_align(value)
    "font" => parse_font(value)
    "font-size" => single_length(value, [PFontSize])
    "color" => single_color(value, [PColor])
    "background" => single_color(value, [PBackgroundColor])
    "background-color" => single_color(value, [PBackgroundColor])
    _ => RUnknown
  }
}
