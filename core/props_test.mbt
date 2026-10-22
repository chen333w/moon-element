///|
/// Black-box tests for Props: pure logic, runs on every backend.

///|
fn badge_specs() -> Array[@core.AttrSpec] {
  [
    @core.AttrSpec::string("label", "?"),
    @core.AttrSpec::int("max-count", 3),
    @core.AttrSpec::double("ratio", 1.5),
    @core.AttrSpec::bool("disabled", false),
  ]
}

///|
test "Props: initial values come from the defaults" {
  let props = @core.Props::new(badge_specs())
  assert_eq(props.keys(), ["label", "max-count", "ratio", "disabled"])
  assert_eq(props.get_string("label"), Some("?"))
  assert_eq(props.get_int("max-count"), Some(3))
  assert_eq(props.get_double("ratio"), Some(1.5))
  assert_eq(props.get_bool("disabled"), Some(false))
}

///|
test "Props: applies valid values" {
  let props = @core.Props::new(badge_specs())
  assert_true(props.apply("label", Some("hi")))
  assert_true(props.apply("max-count", Some("12")))
  assert_eq(props.get_string("label"), Some("hi"))
  assert_eq(props.get_int("max-count"), Some(12))
}

///|
test "Props: invalid values fall back to the default instead of raising" {
  let props = @core.Props::new(badge_specs())
  assert_true(props.apply("max-count", Some("abc")))
  assert_eq(props.get_int("max-count"), Some(3))
  // set a valid value, then an invalid one: it must fall back to the default, not keep the old value
  assert_true(props.apply("max-count", Some("9")))
  assert_eq(props.get_int("max-count"), Some(9))
  assert_true(props.apply("max-count", Some("9.5")))
  assert_eq(props.get_int("max-count"), Some(3))
}

///|
test "Props: removing an attribute falls back to the default" {
  let props = @core.Props::new(badge_specs())
  assert_true(props.apply("label", Some("hi")))
  assert_true(props.apply("label", None))
  assert_eq(props.get_string("label"), Some("?"))
}

///|
test "Props: an undeclared attribute name is rejected and changes no value" {
  let props = @core.Props::new(badge_specs())
  assert_false(props.apply("unknown", Some("x")))
  assert_eq(props.get("unknown"), None)
  assert_eq(props.get_string("label"), Some("?"))
}

///|
test "Props: a mismatched read returns None (no implicit conversion)" {
  let props = @core.Props::new(badge_specs())
  assert_eq(props.get_int("label"), None)
  assert_eq(props.get_string("max-count"), None)
  assert_eq(props.get_bool("label"), None)
  assert_eq(props.get_double("max-count"), None)
  // the untyped read still sees the real value
  assert_eq(props.get("label"), Some(@core.VString("?")))
}

///|
test "Props: booleans follow presence means true" {
  let props = @core.Props::new(badge_specs())
  assert_true(props.apply("disabled", Some("")))
  assert_eq(props.get_bool("disabled"), Some(true))
  assert_true(props.apply("disabled", Some("false")))
  assert_eq(props.get_bool("disabled"), Some(true))
  assert_true(props.apply("disabled", None))
  assert_eq(props.get_bool("disabled"), Some(false))
}

///|
test "Props: instances do not pollute each other (shared specs, independent values)" {
  let shared = badge_specs()
  let a = @core.Props::new(shared)
  let b = @core.Props::new(shared)
  assert_true(a.apply("label", Some("A")))
  assert_true(b.apply("label", Some("B")))
  assert_eq(a.get_string("label"), Some("A"))
  assert_eq(b.get_string("label"), Some("B"))
}
