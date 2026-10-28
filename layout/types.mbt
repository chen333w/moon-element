// Geometry output of the layout stage, plus the text measurement hook that keeps
// the engine independent of any font stack.

///|
pub(all) struct Rect {
  x : Double
  y : Double
  w : Double
  h : Double
} derive(Eq)

///|
pub extend Rect with Eq::{equal, not_equal}

///|
/// A styled node: the input of the layout stage.
pub(all) struct StyleNode {
  info : @style.ElementInfo
  style : @style.ComputedStyle
  children : Array[StyleNode]
  /// 文本节点为 Some，元素节点为 None；文本节点的 info.tag 固定为 "#text"
  text : String?
}

///|
/// Measures one run of text at a font size and returns (width, line height).
/// Injected so the engine does not depend on a font stack.
pub type TextMeasure = (String, Double) -> (Double, Double)

///|
/// Payload of an element box.
pub(all) struct BoxData {
  /// Index of the input node in a preorder walk, so callers can map a box back to
  /// its content without carrying paths around.
  node : Int32
  rect : Rect
  children : Array[LayoutBox]
}

///|
/// Payload of a text box.
pub(all) struct TextData {
  node : Int32
  text : String
  rect : Rect
  /// Distance from the top of the line box to the text baseline.
  baseline : Double
}

///|
pub(all) enum LayoutBox {
  Box(BoxData)
  Text(TextData)
}
