///|
/// Black-box tests for the lifecycle state machine. Pure logic, no DOM, runs on every backend.

///|
test "lifecycle: basic connect and disconnect transitions" {
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
test "lifecycle: repeated connect/disconnect produces no duplicate reactions (per spec)" {
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
test "lifecycle: reconnect after disconnect increments the counts" {
  let lc = @core.Lifecycle::new()
  assert_true(lc.on_connect())
  assert_true(lc.on_disconnect())
  assert_true(lc.on_connect())
  assert_eq(lc.connect_count(), 2)
  assert_eq(lc.disconnect_count(), 1)
  assert_eq(lc.reaction_log(), ["connected", "disconnected", "connected"])
}

///|
test "lifecycle: attribute changes are recorded while unconnected" {
  let lc = @core.Lifecycle::new()
  lc.on_attribute_changed("max-count", None, Some("3"))
  lc.on_attribute_changed("max-count", Some("3"), None)
  assert_eq(lc.reaction_log(), [
    "attribute:max-count:<none>->3", "attribute:max-count:3-><none>",
  ])
}

///|
test "lifecycle: state query and the adopted reaction" {
  let lc = @core.Lifecycle::new()
  assert_eq(lc.state(), @core.Unconnected)
  assert_true(lc.on_connect())
  assert_eq(lc.state(), @core.Connected)
  lc.on_adopted()
  assert_eq(lc.reaction_count(), 2)
  assert_eq(lc.reaction_log(), ["connected", "adopted"])
}
