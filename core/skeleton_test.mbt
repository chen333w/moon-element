///|
/// 元素名校验与骨架生成的黑盒测试（纯逻辑，全后端可跑）。

///|
test "validate_tag_name: 合法名字" {
  assert_true(@core.validate_tag_name("my-widget"))
  assert_true(@core.validate_tag_name("x-badge"))
  assert_true(@core.validate_tag_name("a-1"))
  assert_true(@core.validate_tag_name("my-widget.v2"))
  assert_true(@core.validate_tag_name("my_widget-x"))
}

///|
test "validate_tag_name: 拒绝不带连字符的名字" {
  // 普通标签名不能注册成自定义元素
  assert_false(@core.validate_tag_name("mywidget"))
  assert_false(@core.validate_tag_name("div"))
  assert_false(@core.validate_tag_name(""))
}

///|
test "validate_tag_name: 拒绝大写、非法字符与首尾连字符" {
  assert_false(@core.validate_tag_name("My-Widget"))
  assert_false(@core.validate_tag_name("my-Widget"))
  assert_false(@core.validate_tag_name("-my-widget"))
  assert_false(@core.validate_tag_name("my-widget-"))
  assert_false(@core.validate_tag_name("my widget"))
  assert_false(@core.validate_tag_name("my/wiget"))
  assert_false(@core.validate_tag_name("my—widget"))
}

///|
test "validate_tag_name: 拒绝保留名与 xml 前缀" {
  assert_false(@core.validate_tag_name("annotation-xml"))
  assert_false(@core.validate_tag_name("color-profile"))
  assert_false(@core.validate_tag_name("font-face"))
  assert_false(@core.validate_tag_name("xml-my-widget"))
  assert_false(@core.validate_tag_name("XML-my-widget"))
  // 只是以 xml 开头但不是前缀保留形式的名字，规范也是拒绝的
  assert_false(@core.validate_tag_name("xmlfoo-bar"))
}

///|
test "tag_to_snake: 连字符与点转下划线" {
  assert_eq(@core.tag_to_snake("my-widget"), "my_widget")
  assert_eq(@core.tag_to_snake("x-badge.v2"), "x_badge_v2")
  assert_eq(@core.tag_to_snake("plain"), "plain")
}

///|
test "component_skeleton: 非法标签名返回 None，不生成跑不起来的代码" {
  assert_true(@core.component_skeleton("mywidget") is None)
  assert_true(@core.component_skeleton("My-Widget") is None)
}

///|
test "component_skeleton: 生成内容包含标签名、标识符与事件声明" {
  let code = @core.component_skeleton("x-counter").unwrap_or("")
  // 注册的目标标签名
  assert_true(code.contains("\"x-counter\""))
  // 标识符按标签名生成
  assert_true(code.contains("render_x_counter"))
  assert_true(code.contains("register_x_counter"))
  // 默认声明一个跨 shadow 边界的事件
  assert_true(code.contains("@core.EventSpec::crossing(\"x-counter-changed\")"))
  // 引用了两个包
  assert_true(code.contains("\"chen333w/moon-element/core\" @core"))
  assert_true(code.contains("\"chen333w/moon-element/dom\" @dom"))
}

///|
test "component_skeleton: light 模式生成 mode 与 styles 声明" {
  let code = @core.component_skeleton("x-light-panel", mode=@core.LightDom).unwrap_or(
    "",
  )
  assert_true(code.contains("渲染模式：light"))
  assert_true(code.contains("mode=@core.LightDom,"))
  assert_true(code.contains("styles=X_LIGHT_PANEL_CSS,"))
  // 生成器同时给出 CSS 常量（const 要求大写标识符）
  assert_true(code.contains("const X_LIGHT_PANEL_CSS : String ="))
  // light 模式要提示不建 shadow root
  assert_true(code.contains("不建 shadow root"))
}

///|
test "component_skeleton: shadow 模式不写 mode，但同样给 styles" {
  let code = @core.component_skeleton("x-badge-v2").unwrap_or("")
  assert_true(code.contains("渲染模式：shadow"))
  assert_true(code.contains("styles=X_BADGE_V2_CSS,"))
  assert_false(code.contains("mode=@core.LightDom,"))
  assert_true(code.contains("`:host` 可用"))
}
