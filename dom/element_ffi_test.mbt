///|
/// D0 assumption 1 + 2: on the JavaScript backend, a MoonBit-built class can
/// extend `HTMLElement`, be registered via `customElements.define`, and call
/// back into MoonBit code.
test "d0: js 后端可注册真正继承 HTMLElement 的自定义元素" {
  @dom.install_dom_stub()
  assert_false(@dom.is_registered_element("moon-spike"))
  @dom.define_element("moon-spike", @dom.js_mark)
  assert_true(@dom.is_registered_element("moon-spike"))
}

///|
/// D0 assumption 2: the DOM callback path reaches MoonBit code (the closure
/// passed to the class is callable from JavaScript).
test "d0: 自定义元素回调能进 MoonBit" {
  @dom.install_dom_stub()
  let before = @dom.js_mark_count()
  @dom.define_element("moon-spike-2", @dom.js_mark)
  @dom.fire_connected("moon-spike-2")
  @dom.fire_connected("moon-spike-2")
  assert_eq(@dom.js_mark_count() - before, 2)
}
