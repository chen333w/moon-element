// Shared vocabulary for the style and layout stages. The types live here so the
// layout engine can be written against a frozen interface.

///|
/// A length as it appears in a declaration, before it is resolved against a box.
pub(all) enum Length {
  Px(Double)
  Percent(Double)
  Em(Double)
  Rem(Double)
  Auto
} derive(Eq)

///|
pub(all) enum Display {
  Block
  Flex
  None
} derive(Eq)

///|
pub(all) enum FlexDirection {
  Row
  Column
} derive(Eq)

///|
pub(all) enum FlexWrap {
  NoWrap
  Wrap
} derive(Eq)

///|
pub(all) enum Justify {
  Start
  Center
  End
  SpaceBetween
  SpaceAround
  SpaceEvenly
} derive(Eq)

///|
pub(all) enum Align {
  Stretch
  Start
  Center
  End
} derive(Eq)

///|
/// Per-side values in the order top, right, bottom, left.
pub(all) struct Edges {
  top : Double
  right : Double
  bottom : Double
  left : Double
} derive(Eq)

///|
pub fn Edges::none() -> Edges {
  { top: 0.0, right: 0.0, bottom: 0.0, left: 0.0, }
}

///|
pub fn Edges::all(v : Double) -> Edges {
  { top: v, right: v, bottom: v, left: v, }
}

///|
/// Horizontal sum, used for content-box sizing.
pub fn Edges::horizontal(self : Edges) -> Double {
  self.left + self.right
}

///|
/// Vertical sum.
pub fn Edges::vertical(self : Edges) -> Double {
  self.top + self.bottom
}

///|
/// Resolved style for one box. Lengths stay unresolved where the box geometry is
/// needed (percentages and auto), because resolution depends on the containing box.
pub(all) struct ComputedStyle {
  display : Display
  width : Length
  height : Length
  min_width : Length
  max_width : Length
  padding : Edges
  border : Edges
  margin : Edges
  gap : Double
  flex_direction : FlexDirection
  flex_wrap : FlexWrap
  justify_content : Justify
  align_items : Align
  flex_grow : Double
  flex_shrink : Double
  flex_basis : Length
  font_size : Double
  color : Rgba
  background_color : Rgba
  border_color : Rgba
  border_radius : Double
} derive(Eq)

///|
pub(all) struct Rgba {
  r : Int32
  g : Int32
  b : Int32
  a : Double
} derive(Eq)

///|
pub fn Rgba::black() -> Rgba {
  { r: 0, g: 0, b: 0, a: 1.0, }
}

///|
pub fn Rgba::transparent() -> Rgba {
  { r: 0, g: 0, b: 0, a: 0.0, }
}

///|
/// The initial value of every property, as CSS defines it.
pub fn ComputedStyle::initial() -> ComputedStyle {
  {
    display: Display::Block,
    width: Length::Auto,
    height: Length::Auto,
    min_width: Length::Auto,
    max_width: Length::Auto,
    padding: Edges::none(),
    border: Edges::none(),
    margin: Edges::none(),
    gap: 0.0,
    flex_direction: FlexDirection::Row,
    flex_wrap: FlexWrap::NoWrap,
    justify_content: Justify::Start,
    align_items: Align::Stretch,
    flex_grow: 0.0,
    flex_shrink: 1.0,
    flex_basis: Length::Auto,
    font_size: 16.0,
    color: Rgba::black(),
    background_color: Rgba::transparent(),
    border_color: Rgba::transparent(),
    border_radius: 0.0,
  }
}

///|
pub extend Length with Eq::{equal, not_equal}

///|
pub extend Display with Eq::{equal, not_equal}

///|
pub extend FlexDirection with Eq::{equal, not_equal}

///|
pub extend FlexWrap with Eq::{equal, not_equal}

///|
pub extend Justify with Eq::{equal, not_equal}

///|
pub extend Align with Eq::{equal, not_equal}

///|
pub extend Edges with Eq::{equal, not_equal}

///|
pub extend ComputedStyle with Eq::{equal, not_equal}

///|
pub extend Rgba with Eq::{equal, not_equal}

///|
pub extend ElementInfo with Eq::{equal, not_equal}
