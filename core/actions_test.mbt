///|
test "ActionSpec: event and action accessors" {
  let spec = @core.ActionSpec::new("click", "inc")
  assert_eq(spec.event(), "click")
  assert_eq(spec.action(), "inc")
}

///|
test "is_valid_action: rejects empty, whitespace and quotes" {
  assert_true(@core.is_valid_action("inc"))
  assert_true(@core.is_valid_action("add-item.2"))
  assert_false(@core.is_valid_action(""))
  assert_false(@core.is_valid_action("add item"))
  assert_false(@core.is_valid_action("add\titem"))
  assert_false(@core.is_valid_action("a\"b"))
  assert_false(@core.is_valid_action("a'b"))
}

///|
test "ActionRegistry: rejects invalid and duplicate specs" {
  let registry = @core.ActionRegistry::new()
  assert_true(registry.add(@core.ActionSpec::new("click", "inc")))
  // same pair again
  assert_false(registry.add(@core.ActionSpec::new("click", "inc")))
  // invalid event type
  assert_false(registry.add(@core.ActionSpec::new("cli ck", "inc")))
  // invalid action
  assert_false(registry.add(@core.ActionSpec::new("click", "")))
  assert_eq(registry.length(), 1)
}

///|
test "ActionRegistry: event_types lists distinct types once" {
  let registry = @core.ActionRegistry::new()
  let _ = registry.add(@core.ActionSpec::new("click", "inc"))
  let _ = registry.add(@core.ActionSpec::new("click", "dec"))
  let _ = registry.add(@core.ActionSpec::new("input", "edit"))
  assert_eq(registry.event_types(), ["click", "input"])
}

///|
test "ActionRegistry: find only matches the full pair" {
  let registry = @core.ActionRegistry::new()
  let _ = registry.add(@core.ActionSpec::new("click", "inc"))
  assert_true(registry.find("click", "inc") is Some(_))
  assert_true(registry.find("click", "dec") is None)
  assert_true(registry.find("input", "inc") is None)
}
