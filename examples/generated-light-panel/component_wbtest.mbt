///|
/// End-to-end test of the light-mode generated output: no shadow root, styles scoped to
/// the tag name.

///|
test "generated light component: content goes into the element itself, no shadow root" {
  @dom.install_dom_stub()
  register_x_light_panel()
  assert_eq(@dom.probe_observed("x-light-panel"), ["label"])
  let id = @dom.probe_create("x-light-panel")
  @dom.probe_connect(id)
  // light mode: no shadow root, content written into the element itself
  assert_eq(@dom.probe_shadow_html(id), "")
  let html = @dom.probe_inner_html(id)
  // styles scoped to the tag name by scope_css (:host replaced, plain selectors prefixed)
  assert_true(html.contains("x-light-panel { display: block; }"))
  assert_true(html.contains("x-light-panel .label { color: #3b4453; }"))
  assert_false(html.contains(":host"))
  // an attribute change re-renders here too
  @dom.probe_set_attribute(id, "label", "hi")
  assert_true(@dom.probe_inner_html(id).contains(">hi</span>"))
}
