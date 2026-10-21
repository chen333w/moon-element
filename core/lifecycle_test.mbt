///|
/// 生命周期状态机的黑盒测试。纯逻辑，不碰 DOM，可全后端运行。

///|
test "生命周期：连接与断开的基本转换" {
  let lc = @core.Lifecycle::new()
  assert_false(lc.is_connected())
  assert_eq(lc.reaction_log(), [])
  assert_true(lc.on_connect())
  assert_true(lc.is_connected())
  assert_eq(lc.connect_count(), 1)
  assert_eq(lc.reaction_log(), ["connected"])
  assert_true(lc.on_disconnect())
  assert_false(lc.is_connected())
  assert_eq(lc.disconnect_count(), 1)
  assert_eq(lc.reaction_log(), ["connected", "disconnected"])
}

///|
test "生命周期：重复连接/断开不产生重复反应（与规范一致）" {
  let lc = @core.Lifecycle::new()
  assert_true(lc.on_connect())
  assert_false(lc.on_connect())
  assert_eq(lc.connect_count(), 1)
  assert_true(lc.on_disconnect())
  assert_false(lc.on_disconnect())
  assert_eq(lc.disconnect_count(), 1)
  assert_eq(lc.reaction_log(), ["connected", "disconnected"])
}

///|
test "生命周期：断开后可重连，计数累加" {
  let lc = @core.Lifecycle::new()
  assert_true(lc.on_connect())
  assert_true(lc.on_disconnect())
  assert_true(lc.on_connect())
  assert_eq(lc.connect_count(), 2)
  assert_eq(lc.disconnect_count(), 1)
  assert_eq(lc.reaction_log(), ["connected", "disconnected", "connected"])
}

///|
test "生命周期：属性变更在未连接时也被记录" {
  let lc = @core.Lifecycle::new()
  lc.on_attribute_changed("max-count", None, Some("3"))
  lc.on_attribute_changed("max-count", Some("3"), None)
  assert_eq(lc.reaction_log(), [
    "attribute:max-count:<none>->3", "attribute:max-count:3-><none>",
  ])
}

///|
test "生命周期：state 查询与 adopted 反应" {
  let lc = @core.Lifecycle::new()
  assert_eq(lc.state(), @core.Unconnected)
  assert_true(lc.on_connect())
  assert_eq(lc.state(), @core.Connected)
  lc.on_adopted()
  assert_eq(lc.reaction_count(), 2)
  assert_eq(lc.reaction_log(), ["connected", "adopted"])
}
