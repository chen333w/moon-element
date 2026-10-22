///|
/// How a component renders.
///
/// Lives in `core` rather than `dom` because it belongs to the **component model**:
/// core decides what is rendered and how styles are handled, dom only decides where the
/// output goes. That also lets the CLI and config use it directly as a parameter type.
///
/// - `ShadowDom` (default): renders into a shadow root, styles are isolated by
///   construction, and `:host` works as is
/// - `LightDom`: renders into the element itself (no shadow root). The component CSS is
///   first scoped to the tag name with `scope_css`, so it cannot leak into the page
pub(all) enum RenderMode {
  ShadowDom
  LightDom
} derive(Eq, @debug.Debug)

///|
/// `derive` produces these as implicitly promoted methods (deprecated); declare them
/// explicitly to silence the warning.
pub extend RenderMode with Eq::{equal, not_equal}

///|
pub extend RenderMode with @debug.Debug::{to_repr}

///|
/// Parse a mode name (used by the CLI and config).
///
/// Only `"shadow"` and `"light"` are accepted; anything else returns `None`. No fuzzy
/// matching, so a misspelled value is never silently taken as the default.
pub fn RenderMode::parse(s : String) -> RenderMode? {
  if s == "shadow" {
    Some(ShadowDom)
  } else if s == "light" {
    Some(LightDom)
  } else {
    None
  }
}

///|
pub fn RenderMode::name(self : RenderMode) -> String {
  match self {
    ShadowDom => "shadow"
    LightDom => "light"
  }
}
