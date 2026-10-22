///|
/// End-to-end test of the generated shadow-mode component.

///|
test "generated component: registration, attributes and rendering work end to end" {
  @dom.install_dom_stub()
  register_x_counter()
  assert_eq(@dom.probe_observed("x-counter"), ["label"])
  let id = @dom.probe_create("x-counter")
  @dom.probe_connect(id)
  let html = @dom.probe_shadow_html(id)
  // shadow mode: CSS is injected verbatim, `:host` is not rewritten
  assert_true(html.contains("<style>:host { display: block; }"))
  assert_true(html.contains(".label { color: #3b4453; }"))
  assert_true(html.has_suffix("<span class=\"label\"></span>"))
  @dom.probe_set_attribute(id, "label", "hello")
  assert_true(
    @dom.probe_shadow_html(id).has_suffix("<span class=\"label\">hello</span>"),
  )
}

///|
test "generated component: the declared crossing event works" {
  @dom.install_dom_stub()
  register_x_counter()
  let id = @dom.probe_create("x-counter")
  @dom.probe_connect(id)
  @dom.probe_add_listener(id, "x-counter-changed")
  let canceled = @dom.dispatch(id, "x-counter-changed", "payload", false)
  assert_false(canceled)
  assert_eq(@dom.probe_listener_log(id), [
    "x-counter-changed|payload|bubbles=true|composed=true",
  ])
}
