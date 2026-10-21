///|
/// 事件描述与注册表的黑盒测试（纯逻辑，全后端可跑）。

///|
test "EventSpec: 三种常用形态的默认值" {
  let crossing = @core.EventSpec::crossing("count-changed")
  assert_true(crossing.bubbles())
  assert_true(crossing.composed())
  let contained = @core.EventSpec::contained("internal-step")
  assert_false(contained.bubbles())
  assert_false(contained.composed())
  let custom = @core.EventSpec::new("x", true, false)
  assert_true(custom.bubbles())
  assert_false(custom.composed())
}

///|
test "事件名校验：拒绝空名与含空白的名字" {
  assert_true(@core.is_valid_event_name("count-changed"))
  assert_true(@core.is_valid_event_name("a"))
  assert_false(@core.is_valid_event_name(""))
  assert_false(@core.is_valid_event_name("count changed"))
  assert_false(@core.is_valid_event_name("count\tchanged"))
  assert_false(@core.is_valid_event_name("count\nchanged"))
}

///|
test "EventRegistry: 注册、去重、拒绝非法名" {
  let reg = @core.EventRegistry::new()
  assert_eq(reg.length(), 0)
  assert_true(reg.add(@core.EventSpec::crossing("count-changed")))
  assert_true(reg.add(@core.EventSpec::contained("internal-step")))
  assert_eq(reg.names(), ["count-changed", "internal-step"])
  // 重名被拒
  assert_false(reg.add(@core.EventSpec::contained("count-changed")))
  assert_eq(reg.length(), 2)
  // 非法名被拒
  assert_false(reg.add(@core.EventSpec::contained("bad name")))
  assert_eq(reg.length(), 2)
}

///|
test "EventRegistry: 按名查找" {
  let reg = @core.EventRegistry::new()
  assert_true(reg.add(@core.EventSpec::crossing("count-changed")))
  let spec = reg
    .find("count-changed")
    .unwrap_or(@core.EventSpec::contained("missing"))
  assert_true(spec.composed())
  assert_true(spec.bubbles())
  assert_true(reg.find("nope") is None)
}
