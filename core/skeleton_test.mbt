///|
/// Blackbox tests for tag-name validation and skeleton generation (pure logic, all backends).

///|
test "validate_tag_name: valid names" {
  assert_true(@core.validate_tag_name("my-widget"))
  assert_true(@core.validate_tag_name("x-badge"))
  assert_true(@core.validate_tag_name("a-1"))
  assert_true(@core.validate_tag_name("my-widget.v2"))
  assert_true(@core.validate_tag_name("my_widget-x"))
}

///|
test "validate_tag_name: rejects names without a hyphen" {
  // ordinary tag names cannot be registered as custom elements
  assert_false(@core.validate_tag_name("mywidget"))
  assert_false(@core.validate_tag_name("div"))
  assert_false(@core.validate_tag_name(""))
}

///|
test "validate_tag_name: rejects uppercase, illegal characters and edge hyphens" {
  assert_false(@core.validate_tag_name("My-Widget"))
  assert_false(@core.validate_tag_name("my-Widget"))
  assert_false(@core.validate_tag_name("-my-widget"))
  assert_false(@core.validate_tag_name("my-widget-"))
  assert_false(@core.validate_tag_name("my widget"))
  assert_false(@core.validate_tag_name("my/wiget"))
  assert_false(@core.validate_tag_name("my—widget"))
}

///|
test "validate_tag_name: rejects reserved names and the xml prefix" {
  assert_false(@core.validate_tag_name("annotation-xml"))
  assert_false(@core.validate_tag_name("color-profile"))
  assert_false(@core.validate_tag_name("font-face"))
  assert_false(@core.validate_tag_name("xml-my-widget"))
  assert_false(@core.validate_tag_name("XML-my-widget"))
  // a name that merely starts with xml is rejected by the spec as well
  assert_false(@core.validate_tag_name("xmlfoo-bar"))
}

///|
test "tag_to_snake: hyphens and dots become underscores" {
  assert_eq(@core.tag_to_snake("my-widget"), "my_widget")
  assert_eq(@core.tag_to_snake("x-badge.v2"), "x_badge_v2")
  assert_eq(@core.tag_to_snake("plain"), "plain")
}

///|
test "component_skeleton: invalid tag names return None instead of broken code" {
  assert_true(@core.component_skeleton("mywidget") is None)
  assert_true(@core.component_skeleton("My-Widget") is None)
}

///|
test "component_skeleton: output carries the tag name, identifiers and event spec" {
  let code = @core.component_skeleton("x-counter").unwrap_or("")
  // the tag name being registered
  assert_true(code.contains("\"x-counter\""))
  // identifiers derived from the tag name
  assert_true(code.contains("render_x_counter"))
  assert_true(code.contains("register_x_counter"))
  // one crossing event declared by default
  assert_true(code.contains("@core.EventSpec::crossing(\"x-counter-changed\")"))
  // both packages referenced
  assert_true(code.contains("\"chen333w/moon-element/core\" @core"))
  assert_true(code.contains("\"chen333w/moon-element/dom\" @dom"))
}

///|
test "component_skeleton: light mode emits the mode and styles declarations" {
  let code = @core.component_skeleton("x-light-panel", mode=@core.LightDom).unwrap_or(
    "",
  )
  assert_true(code.contains("render mode: light"))
  assert_true(code.contains("mode=@core.LightDom,"))
  assert_true(code.contains("styles=X_LIGHT_PANEL_CSS,"))
  // a CSS constant is emitted as well (const requires an uppercase identifier)
  assert_true(code.contains("const X_LIGHT_PANEL_CSS : String ="))
  // light mode states that no shadow root is created
  assert_true(code.contains("no shadow root"))
}

///|
test "component_skeleton: shadow mode omits mode but still emits styles" {
  let code = @core.component_skeleton("x-badge-v2").unwrap_or("")
  assert_true(code.contains("render mode: shadow"))
  assert_true(code.contains("styles=X_BADGE_V2_CSS,"))
  assert_false(code.contains("mode=@core.LightDom,"))
  assert_true(code.contains("`:host` works"))
}
