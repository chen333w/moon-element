///|
/// Black-box tests for event dispatch.

///|
fn counter_specs() -> Array[@core.AttrSpec] {
  [@core.AttrSpec::int("count", 0)]
}

///|
fn render_counter(props : @core.Props) -> @core.View {
  @core.View::element("span", [], [
    @core.View::text(props.get_int("count").unwrap_or(0).to_string()),
  ])
}

///|
fn define_counter(tag : String) -> Unit {
  @dom.define_component(tag, counter_specs(), render_counter, events=[
    @core.EventSpec::crossing("count-changed"),
    @core.EventSpec::contained("internal-step"),
  ])
}

///|
test "dispatch: declared event dispatches across the shadow boundary" {
  @dom.install_dom_stub()
  define_counter("x-counter-1")
  let id = @dom.probe_create("x-counter-1")
  @dom.probe_connect(id)
  @dom.probe_add_listener(id, "count-changed")
  let canceled = @dom.dispatch(id, "count-changed", "1", false)
  assert_false(canceled)
  assert_eq(@dom.probe_listener_log(id), [
    "count-changed|1|bubbles=true|composed=true",
  ])
  assert_eq(@dom.instance_event_names(id), ["count-changed", "internal-step"])
}

///|
test "dispatch: event declared local does not bubble or cross the boundary" {
  @dom.install_dom_stub()
  define_counter("x-counter-2")
  let id = @dom.probe_create("x-counter-2")
  @dom.probe_connect(id)
  @dom.probe_add_listener(id, "internal-step")
  let _ = @dom.dispatch(id, "internal-step", "", false)
  assert_eq(@dom.probe_listener_log(id), [
    "internal-step||bubbles=false|composed=false",
  ])
}

///|
test "dispatch: undeclared event uses conservative defaults" {
  @dom.install_dom_stub()
  define_counter("x-counter-3")
  let id = @dom.probe_create("x-counter-3")
  @dom.probe_connect(id)
  @dom.probe_add_listener(id, "not-declared")
  let _ = @dom.dispatch(id, "not-declared", "x", false)
  assert_eq(@dom.probe_listener_log(id), [
    "not-declared|x|bubbles=false|composed=false",
  ])
}

///|
test "dispatch: cancelable event returns true when preventDefault is called" {
  @dom.install_dom_stub()
  define_counter("x-counter-4")
  let id = @dom.probe_create("x-counter-4")
  @dom.probe_connect(id)
  @dom.probe_add_canceling_listener(id, "count-changed")
  assert_true(@dom.dispatch(id, "count-changed", "1", true))
  // When not cancelable, preventDefault has no effect and dispatch returns false
  assert_false(@dom.dispatch(id, "count-changed", "2", false))
  assert_eq(@dom.instance_event_log(id), [
    "count-changed|1|canceled=true", "count-changed|2|canceled=false",
  ])
}

///|
test "dispatch: invalid instance id returns false and does not throw" {
  @dom.install_dom_stub()
  define_counter("x-counter-5")
  assert_false(@dom.dispatch(9999, "count-changed", "", false))
  assert_eq(@dom.instance_event_log(9999), [])
}

///|
test "dispatch: dispatching affects neither render output nor attribute state" {
  @dom.install_dom_stub()
  define_counter("x-counter-6")
  let id = @dom.probe_create("x-counter-6")
  @dom.probe_set_attribute(id, "count", "7")
  @dom.probe_connect(id)
  let _ = @dom.dispatch(id, "count-changed", "7", false)
  assert_eq(@dom.probe_shadow_html(id), "<span>7</span>")
  assert_eq(@dom.instance_prop_int(id, "count"), Some(7))
}
