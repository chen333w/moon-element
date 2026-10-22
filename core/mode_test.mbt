///|
/// RenderMode 的解析与命名：CLI 与配置用它，所以拼错必须被发现，而不是静默取默认值。

///|
test "RenderMode: 只接受 shadow / light" {
  assert_eq(@core.RenderMode::parse("shadow"), Some(@core.ShadowDom))
  assert_eq(@core.RenderMode::parse("light"), Some(@core.LightDom))
  assert_eq(@core.RenderMode::parse("Shadow"), None)
  assert_eq(@core.RenderMode::parse("LIGHT"), None)
  assert_eq(@core.RenderMode::parse(""), None)
  assert_eq(@core.RenderMode::parse("shadow "), None)
}

///|
test "RenderMode: 名字可往返" {
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
