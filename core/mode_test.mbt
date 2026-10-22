///|
/// Parsing and naming for RenderMode (used by the CLI and config).

///|
test "RenderMode: accepts only shadow / light" {
  assert_eq(@core.RenderMode::parse("shadow"), Some(@core.ShadowDom))
  assert_eq(@core.RenderMode::parse("light"), Some(@core.LightDom))
  assert_eq(@core.RenderMode::parse("Shadow"), None)
  assert_eq(@core.RenderMode::parse("LIGHT"), None)
  assert_eq(@core.RenderMode::parse(""), None)
  assert_eq(@core.RenderMode::parse("shadow "), None)
}

///|
test "RenderMode: names round-trip" {
  assert_eq(@core.ShadowDom.name(), "shadow")
  assert_eq(@core.LightDom.name(), "light")
  assert_eq(
    @core.RenderMode::parse(@core.ShadowDom.name()),
    Some(@core.ShadowDom),
  )
  assert_eq(
    @core.RenderMode::parse(@core.LightDom.name()),
    Some(@core.LightDom),
  )
}
