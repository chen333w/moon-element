///|
/// light 模式生成产物的端到端测试：不建 shadow root、样式被作用域到标签名。

///|
test "generated light component: 内容进元素自身，不建 shadow root" {
  @dom.install_dom_stub()
  register_x_light_panel()
  assert_eq(@dom.probe_observed("x-light-panel"), ["label"])
  let id = @dom.probe_create("x-light-panel")
  @dom.probe_connect(id)
  // light 模式：没有 shadow root，内容写在元素自身
  assert_eq(@dom.probe_shadow_html(id), "")
  let html = @dom.probe_inner_html(id)
  // 样式被 scope_css 作用域到标签名（:host 被替换，普通选择器加前缀）
  assert_true(html.contains("x-light-panel { display: block; }"))
  assert_true(html.contains("x-light-panel .label { color: #3b4453; }"))
  assert_false(html.contains(":host"))
  // 属性变化同样重渲染
  @dom.probe_set_attribute(id, "label", "hi")
  assert_true(@dom.probe_inner_html(id).contains(">hi</span>"))
}
