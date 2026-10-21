///|
/// 端到端集成测试（白盒）：把生成器产出的组件真正注册、设属性、连接、断言渲染结果。
///
/// 这样「生成的骨架能用」这件事就不只是"能编译"，而是运行时也验证过：
/// 生成器 → 包配置 → 注册 → 属性反射 → shadow DOM 渲染，整条链子都跑了一遍。

///|
test "generated component: 注册、属性、渲染端到端可用" {
  @dom.install_dom_stub()
  register_x_counter()
  assert_eq(@dom.probe_observed("x-counter"), ["label"])
  let id = @dom.probe_create("x-counter")
  @dom.probe_connect(id)
  // 默认值
  assert_eq(@dom.probe_shadow_html(id), "<span></span>")
  // 属性变化触发重渲染
  @dom.probe_set_attribute(id, "label", "hello")
  assert_eq(@dom.probe_shadow_html(id), "<span>hello</span>")
}

///|
test "generated component: 声明的跨边界事件可用" {
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
