// 层叠只处理长属性：简写在解析期就展开，计算期不再区分写法。

///|
/// 会被层叠的单值属性。简写（padding、border、flex 等）在解析期展开成这些。
pub enum Prop {
  PDisplay
  PWidth
  PHeight
  PMinWidth
  PMaxWidth
  PPaddingTop
  PPaddingRight
  PPaddingBottom
  PPaddingLeft
  PBorderTop
  PBorderRight
  PBorderBottom
  PBorderLeft
  PMarginTop
  PMarginRight
  PMarginBottom
  PMarginLeft
  PGap
  PFlexDirection
  PFlexWrap
  PJustifyContent
  PAlignItems
  PFlexGrow
  PFlexShrink
  PFlexBasis
  PFontSize
  PColor
  PBackgroundColor
  PBorderColor
  PBorderRadius
}

///|
fn prop_count() -> Int32 {
  30
}

///|
/// 长属性在层叠槽位里的下标，用于按属性保存当前最优声明。
fn prop_index(p : Prop) -> Int32 {
  match p {
    PDisplay => 0
    PWidth => 1
    PHeight => 2
    PMinWidth => 3
    PMaxWidth => 4
    PPaddingTop => 5
    PPaddingRight => 6
    PPaddingBottom => 7
    PPaddingLeft => 8
    PBorderTop => 9
    PBorderRight => 10
    PBorderBottom => 11
    PBorderLeft => 12
    PMarginTop => 13
    PMarginRight => 14
    PMarginBottom => 15
    PMarginLeft => 16
    PGap => 17
    PFlexDirection => 18
    PFlexWrap => 19
    PJustifyContent => 20
    PAlignItems => 21
    PFlexGrow => 22
    PFlexShrink => 23
    PFlexBasis => 24
    PFontSize => 25
    PColor => 26
    PBackgroundColor => 27
    PBorderColor => 28
    PBorderRadius => 29
  }
}

///|
/// 解析结果里的值。长度保留未解析形态，颜色区分 currentColor。
pub enum Value {
  VLength(Length)
  VColor(Rgba, Bool)
  VDisplay(Display)
  VDirection(FlexDirection)
  VWrap(FlexWrap)
  VJustify(Justify)
  VAlign(Align)
  VNumber(Double)
}

///|
/// 一条已展开的声明。
pub struct Decl {
  prop : Prop
  value : Value
  important : Bool
}

///|
/// 属性无效时回退到的初始值。
fn initial_value(p : Prop) -> Value {
  match p {
    PDisplay => VDisplay(Display::Block)
    PWidth | PHeight | PMinWidth | PMaxWidth | PFlexBasis =>
      VLength(Length::Auto)
    PPaddingTop
    | PPaddingRight
    | PPaddingBottom
    | PPaddingLeft
    | PBorderTop
    | PBorderRight
    | PBorderBottom
    | PBorderLeft
    | PMarginTop
    | PMarginRight
    | PMarginBottom
    | PMarginLeft
    | PGap
    | PBorderRadius => VLength(Length::Px(0.0))
    PFlexDirection => VDirection(FlexDirection::Row)
    PFlexWrap => VWrap(FlexWrap::NoWrap)
    PJustifyContent => VJustify(Justify::Start)
    PAlignItems => VAlign(Align::Stretch)
    PFlexGrow => VNumber(0.0)
    PFlexShrink => VNumber(1.0)
    PFontSize => VLength(Length::Px(16.0))
    PColor => VColor(Rgba::black(), false)
    PBackgroundColor => VColor(Rgba::transparent(), false)
    // border-color 的初始值是 currentColor
    PBorderColor => VColor(Rgba::black(), true)
  }
}
