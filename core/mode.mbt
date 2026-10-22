///|
/// How a component renders. `ShadowDom` renders into a shadow root, where `:host` works as
/// is; `LightDom` renders into the element itself and first scopes the component CSS to
/// the tag name with `scope_css`.
pub(all) enum RenderMode {
  ShadowDom
  LightDom
} derive(Eq, @debug.Debug)

///|
pub extend RenderMode with Eq::{equal, not_equal}

///|
pub extend RenderMode with @debug.Debug::{to_repr}

///|
/// Parse a mode name. Only `"shadow"` and `"light"` are accepted; anything else returns
/// `None`, so a misspelled value is never silently taken as the default.
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
