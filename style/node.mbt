// A style input node. Keeping it independent of `core` lets the cascade be tested
// on hand-built inputs and keeps the layout stage free of the view layer.

///|
/// What a selector can match against.
pub(all) struct ElementInfo {
  tag : String
  id : String
  classes : Array[String]
  /// Declarations from the `style` attribute, already split into pairs.
  inline : Array[(String, String)]
  /// Parent index in the flat node list, or -1 at the root.
  parent : Int32
} derive(Eq)
