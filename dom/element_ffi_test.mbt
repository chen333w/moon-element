///|
test "d0: js 后端可注册真正继承 HTMLElement 的自定义元素" {
  @dom.install_dom_stub()
  assert_false(@dom.is_registered_element("moon-spike"))
  @dom.define_element("moon-spike", @dom.js_mark)
  assert_true(@dom.is_registered_element("moon-spike"))
}

///|
test "d0: 自定义元素回调能进 MoonBit" {
  @dom.install_dom_stub()
  let before = @dom.js_mark_count()
  @dom.define_element("moon-spike-2", @dom.js_mark)
  @dom.fire_connected("moon-spike-2")
  @dom.fire_connected("moon-spike-2")
  assert_eq(@dom.js_mark_count() - before, 2)
}
