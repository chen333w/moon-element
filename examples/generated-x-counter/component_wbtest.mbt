///|
/// 端到端集成测试（白盒）：把生成器产出的组件真正注册、设属性、连接、断言渲染结果。
///
/// 这样「生成的骨架能用」就不只是「能编译」，而是运行时也验证过：
/// 生成器 → 包配置 → 注册 → 属性反射 → shadow DOM 渲染，整条链子都跑了一遍。
///
/// 对照 [`../generated-light-panel`](../generated-light-panel)：那边是 light 模式
/// （不建 shadow root、`:host` 被替换），这里断言 `:host` 保持不动。

///|
test "generated component: 注册、属性、渲染端到端可用" {
  @dom.install_dom_stub()
  register_x_counter()
  assert_eq(@dom.probe_observed("x-counter"), ["label"])
  let id = @dom.probe_create("x-counter")
  @dom.probe_connect(id)
  let html = @dom.probe_shadow_html(id)
  // shadow 模式：CSS 原样注入，`:host` 不被改写
  assert_true(html.contains("<style>:host { display: block; }"))
  assert_true(html.contains(".label { color: #3b4453; }"))
  // 默认值：label 为空
  assert_true(html.has_suffix("<span class=\"label\"></span>"))
  // 属性变化触发重渲染
  @dom.probe_set_attribute(id, "label", "hello")
  assert_true(
    @dom.probe_shadow_html(id).has_suffix("<span class=\"label\">hello</span>"),
  )
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
