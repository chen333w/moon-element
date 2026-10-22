///|
/// Black-box tests for event specs and the registry (pure logic, runs on every backend).

///|
test "EventSpec: defaults for the three common shapes" {
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
test "event name validation: rejects empty and whitespace-containing names" {
  assert_true(@core.is_valid_event_name("count-changed"))
  assert_true(@core.is_valid_event_name("a"))
  assert_false(@core.is_valid_event_name(""))
  assert_false(@core.is_valid_event_name("count changed"))
  assert_false(@core.is_valid_event_name("count\tchanged"))
  assert_false(@core.is_valid_event_name("count\nchanged"))
}

///|
test "EventRegistry: register, deduplicate, reject invalid names" {
  let reg = @core.EventRegistry::new()
  assert_eq(reg.length(), 0)
  assert_true(reg.add(@core.EventSpec::crossing("count-changed")))
  assert_true(reg.add(@core.EventSpec::contained("internal-step")))
  assert_eq(reg.names(), ["count-changed", "internal-step"])
  assert_false(reg.add(@core.EventSpec::contained("count-changed")))
  assert_eq(reg.length(), 2)
  assert_false(reg.add(@core.EventSpec::contained("bad name")))
  assert_eq(reg.length(), 2)
}

///|
test "EventRegistry: lookup by name" {
  let reg = @core.EventRegistry::new()
  assert_true(reg.add(@core.EventSpec::crossing("count-changed")))
  let spec = reg
    .find("count-changed")
    .unwrap_or(@core.EventSpec::contained("missing"))
  assert_true(spec.composed())
  assert_true(spec.bubbles())
  assert_true(reg.find("nope") is None)
}
