///|
/// Black-box tests for the browser adapter; headlessly the probes replay the
/// browser call order.

///|
fn specs() -> Array[@core.AttrSpec] {
  [
    @core.AttrSpec::string("label", "?"),
    @core.AttrSpec::int("max-count", 3),
    @core.AttrSpec::bool("disabled", false),
  ]
}

///|
fn render_badge(props : @core.Props) -> @core.View {
  let label = props.get_string("label").unwrap_or("?")
  let count = props.get_int("max-count").unwrap_or(0)
  @core.View::element("span", [("class", "badge")], [
    @core.View::text("\{label}:\{count}"),
  ])
}

///|
test "adapter: observedAttributes comes from the specs and lists only declared attributes" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-1", specs(), render_badge)
  assert_eq(@dom.probe_observed("x-badge-1"), ["label", "max-count", "disabled"])
}

///|
test "adapter: attribute set before connection (upgrading an existing element)" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-2", specs(), render_badge)
  let id = @dom.probe_create("x-badge-2")
  // Upgrading fires attribute callbacks before connectedCallback
  @dom.probe_set_attribute(id, "label", "hi")
  assert_eq(@dom.instance_prop_string(id, "label"), Some("hi"))
  assert_eq(@dom.instance_reaction_log(id), ["attribute:label:<none>->hi"])
  assert_eq(@dom.probe_shadow_html(id), "")
}

///|
test "adapter: renders into the shadow root after connect, with values from attributes" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-3", specs(), render_badge)
  let id = @dom.probe_create("x-badge-3")
  @dom.probe_set_attribute(id, "label", "hi")
  @dom.probe_connect(id)
  assert_eq(@dom.probe_shadow_html(id), "<span class=\"badge\">hi:3</span>")
  assert_eq(@dom.instance_reaction_log(id), [
    "attribute:label:<none>->hi", "connected",
  ])
}

///|
test "adapter: attribute change on a connected element re-renders" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-4", specs(), render_badge)
  let id = @dom.probe_create("x-badge-4")
  @dom.probe_connect(id)
  assert_eq(@dom.probe_shadow_html(id), "<span class=\"badge\">?:3</span>")
  @dom.probe_set_attribute(id, "max-count", "12")
  assert_eq(@dom.instance_prop_int(id, "max-count"), Some(12))
  assert_eq(@dom.probe_shadow_html(id), "<span class=\"badge\">?:12</span>")
}

///|
test "adapter: invalid attribute value falls back to the default and re-renders" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-5", specs(), render_badge)
  let id = @dom.probe_create("x-badge-5")
  @dom.probe_connect(id)
  @dom.probe_set_attribute(id, "max-count", "12")
  @dom.probe_set_attribute(id, "max-count", "abc")
  assert_eq(@dom.instance_prop_int(id, "max-count"), Some(3))
  assert_eq(@dom.probe_shadow_html(id), "<span class=\"badge\">?:3</span>")
}

///|
test "adapter: boolean attribute is true by presence and returns to the default when removed" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-6", specs(), render_badge)
  let id = @dom.probe_create("x-badge-6")
  @dom.probe_set_attribute(id, "disabled", "")
  assert_eq(@dom.instance_prop(id, "disabled"), Some(@core.VBool(true)))
  @dom.probe_set_attribute(id, "disabled", "false")
  assert_eq(@dom.instance_prop(id, "disabled"), Some(@core.VBool(true)))
  @dom.probe_remove_attribute(id, "disabled")
  assert_eq(@dom.instance_prop(id, "disabled"), Some(@core.VBool(false)))
}

///|
test "adapter: disconnect and reconnect keep the count and the reaction log correct" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-7", specs(), render_badge)
  let id = @dom.probe_create("x-badge-7")
  @dom.probe_connect(id)
  @dom.probe_disconnect(id)
  @dom.probe_connect(id)
  assert_eq(@dom.instance_reaction_log(id), [
    "connected", "disconnected", "connected",
  ])
  // Attribute changes while disconnected do not render but are still logged
  @dom.probe_disconnect(id)
  @dom.probe_set_attribute(id, "label", "later")
  assert_eq(@dom.instance_reaction_log(id), [
    "connected", "disconnected", "connected", "disconnected", "attribute:label:<none>->later",
  ])
}

///|
test "adapter: two instances do not interfere" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-8", specs(), render_badge)
  let a = @dom.probe_create("x-badge-8")
  let b = @dom.probe_create("x-badge-8")
  @dom.probe_set_attribute(a, "label", "A")
  @dom.probe_set_attribute(b, "label", "B")
  @dom.probe_connect(a)
  @dom.probe_connect(b)
  assert_eq(@dom.probe_shadow_html(a), "<span class=\"badge\">A:3</span>")
  assert_eq(@dom.probe_shadow_html(b), "<span class=\"badge\">B:3</span>")
  assert_eq(@dom.instance_prop_string(a, "label"), Some("A"))
  assert_eq(@dom.instance_prop_string(b, "label"), Some("B"))
}

///|
test "adapter: on_change fires after the state update and can dispatch outward events" {
  @dom.install_dom_stub()
  let seen : Array[String] = []
  @dom.define_component(
    "x-change-probe",
    specs(),
    render_badge,
    events=[@core.EventSpec::crossing("changed")],
    on_change=fn(id, name) {
      seen.push(name)
      let _ = @dom.dispatch(id, "changed", name, false)
    },
  )
  let id = @dom.probe_create("x-change-probe")
  @dom.probe_connect(id)
  @dom.probe_set_attribute(id, "label", "x")
  @dom.probe_set_attribute(id, "max-count", "5")
  assert_eq(seen, ["label", "max-count"])
  assert_eq(@dom.instance_event_log(id), [
    "changed|label|canceled=false", "changed|max-count|canceled=false",
  ])
  assert_eq(@dom.probe_shadow_html(id), "<span class=\"badge\">x:5</span>")
}

///|
test "adapter: diagnostic queries on an invalid instance id return empty and do not throw" {
  @dom.install_dom_stub()
  assert_eq(@dom.instance_reaction_log(9999), [])
  assert_eq(@dom.instance_event_log(9999), [])
  assert_eq(@dom.instance_event_names(9999), [])
  assert_true(@dom.instance_prop(9999, "label") is None)
  assert_true(@dom.instance_prop_string(9999, "label") is None)
  assert_true(@dom.instance_prop_int(9999, "label") is None)
}

///|
test "adapter: disconnect before connect (element created but no callback ever fired) produces no reaction" {
  @dom.install_dom_stub()
  @dom.define_component("x-never-connected", specs(), render_badge)
  let id = @dom.probe_create("x-never-connected")
  @dom.probe_disconnect(id)
  assert_eq(@dom.instance_reaction_log(id), [])
}

///|
fn render_light(props : @core.Props) -> @core.View {
  @core.View::element("p", [], [
    @core.View::text(props.get_string("label").unwrap_or("?")),
  ])
}

///|
test "adapter: light mode builds no shadow root and scopes styles to the tag name with scope_css" {
  @dom.install_dom_stub()
  @dom.define_component(
    "x-light-card",
    [@core.AttrSpec::string("label", "?")],
    render_light,
    styles=":host { display: block } p { color: red }",
    mode=@core.LightDom,
  )
  let id = @dom.probe_create("x-light-card")
  @dom.probe_connect(id)
  assert_eq(@dom.probe_shadow_html(id), "")
  // :host is replaced by the tag name; plain selectors get the tag name prefix
  inspect(
    @dom.probe_inner_html(id),
    content="<style>x-light-card { display: block } x-light-card p { color: red }</style><p>?</p>",
  )
  // The scope prefix stays stable across re-renders
  @dom.probe_set_attribute(id, "label", "hi")
  inspect(
    @dom.probe_inner_html(id),
    content="<style>x-light-card { display: block } x-light-card p { color: red }</style><p>hi</p>",
  )
}

///|
test "adapter: shadow mode injects styles as is and leaves :host untouched" {
  @dom.install_dom_stub()
  @dom.define_component(
    "x-shadow-card",
    [@core.AttrSpec::string("label", "?")],
    render_light,
    styles=":host { display: block } p { color: red }",
  )
  let id = @dom.probe_create("x-shadow-card")
  @dom.probe_connect(id)
  inspect(
    @dom.probe_shadow_html(id),
    content="<style>:host { display: block } p { color: red }</style><p>?</p>",
  )
  assert_eq(@dom.probe_inner_html(id), "")
}

///|
test "adapter: no styles means no empty style tag" {
  @dom.install_dom_stub()
  @dom.define_component(
    "x-no-style",
    [@core.AttrSpec::string("label", "?")],
    render_light,
  )
  let id = @dom.probe_create("x-no-style")
  @dom.probe_connect(id)
  inspect(@dom.probe_shadow_html(id), content="<p>?</p>")
}

///|
let action_seen : Array[String] = []

///|
fn record_action(_id : Int32, action : String) -> Unit {
  action_seen.push(action)
}

///|
fn counter_view_for_actions(props : @core.Props) -> @core.View {
  @core.View::element("div", [], [
    @core.View::element("button", [("data-act", "dec")], [@core.View::text("-")]),
    @core.View::text(props.get_int("count").unwrap_or(0).to_string()),
    @core.View::element("button", [("data-act", "inc")], [@core.View::text("+")]),
  ])
}

///|
test "adapter: actions are handled through a listener on the shadow root" {
  @dom.install_dom_stub()
  action_seen.clear()
  @dom.define_component(
    "x-action-counter",
    [@core.AttrSpec::int("count", 0)],
    counter_view_for_actions,
    on_action=[
      (@core.ActionSpec::new("click", "inc"), record_action),
      (@core.ActionSpec::new("click", "dec"), record_action),
    ],
  )
  let id = @dom.probe_create("x-action-counter")
  @dom.probe_connect(id)
  // the rendered content marks the buttons
  assert_true(@dom.probe_shadow_html(id).contains("data-act=\"inc\""))
  @dom.probe_fire_action(id, "click", "inc")
  @dom.probe_fire_action(id, "click", "dec")
  assert_eq(@dom.instance_action_log(id), ["click:inc", "click:dec"])
  assert_eq(action_seen, ["inc", "dec"])
  // an event with no data-act in the tree runs nothing
  @dom.probe_fire_action(id, "click", "")
  assert_eq(@dom.instance_action_log(id).length(), 2)
  // an event type with no binding is not listened for
  @dom.probe_fire_action(id, "input", "inc")
  assert_eq(@dom.instance_action_log(id).length(), 2)
}

///|
test "adapter: light mode binds actions to the host element" {
  @dom.install_dom_stub()
  action_seen.clear()
  @dom.define_component(
    "x-action-light",
    [],
    fn(_props) {
      @core.View::element("button", [("data-act", "go")], [
        @core.View::text("go"),
      ])
    },
    styles=":host { display: block }",
    mode=@core.LightDom,
    on_action=[(@core.ActionSpec::new("click", "go"), record_action)],
  )
  let id = @dom.probe_create("x-action-light")
  @dom.probe_connect(id)
  assert_eq(@dom.probe_shadow_html(id), "")
  @dom.probe_fire_action(id, "click", "go")
  assert_eq(@dom.instance_action_log(id), ["click:go"])
  assert_eq(action_seen, ["go"])
}

///|
test "adapter: invalid or duplicate action specs are dropped" {
  @dom.install_dom_stub()
  action_seen.clear()
  @dom.define_component(
    "x-action-invalid",
    [],
    fn(_props) { @core.View::text("x") },
    on_action=[
      (@core.ActionSpec::new("click", "ok"), record_action),
      // the same pair twice
      (@core.ActionSpec::new("click", "ok"), record_action),
      // action containing a space
      (@core.ActionSpec::new("click", "not ok"), record_action),
      // event type containing a space
      (@core.ActionSpec::new("cli ck", "x"), record_action),
    ],
  )
  let id = @dom.probe_create("x-action-invalid")
  @dom.probe_connect(id)
  @dom.probe_fire_action(id, "click", "ok")
  assert_eq(@dom.instance_action_log(id), ["click:ok"])
  assert_eq(action_seen, ["ok"])
  @dom.probe_fire_action(id, "click", "not ok")
  assert_eq(@dom.instance_action_log(id).length(), 1)
}

///|
fn count_view(props : @core.Props) -> @core.View {
  @core.View::element("span", [], [
    @core.View::text(props.get_int("count").unwrap_or(0).to_string()),
  ])
}

///|
test "adapter: set_attribute and remove_attribute drive the attribute pipeline" {
  @dom.install_dom_stub()
  @dom.define_component(
    "x-self-update",
    [@core.AttrSpec::int("count", 0)],
    count_view,
  )
  let id = @dom.probe_create("x-self-update")
  @dom.probe_connect(id)
  assert_true(@dom.probe_shadow_html(id).contains(">0<"))
  @dom.set_attribute(id, "count", "7")
  assert_true(@dom.probe_shadow_html(id).contains(">7<"))
  assert_eq(@dom.instance_prop_int(id, "count"), Some(7))
  // removing falls back to the spec default
  @dom.remove_attribute(id, "count")
  assert_eq(@dom.instance_prop_int(id, "count"), Some(0))
  // an unknown instance is a no-op, not a crash
  @dom.set_attribute(99999, "count", "1")
  @dom.remove_attribute(99999, "count")
}

///|
/// Increments the component's own attribute; this is what makes in-component buttons work.
fn increment_own_count(id : Int32, _action : String) -> Unit {
  let next = @dom.instance_prop_int(id, "count").unwrap_or(0) + 1
  @dom.set_attribute(id, "count", next.to_string())
}

///|
test "adapter: an action handler can update the component's own attribute" {
  @dom.install_dom_stub()
  @dom.define_component(
    "x-self-counter",
    [@core.AttrSpec::int("count", 0)],
    fn(_props) {
      @core.View::element("button", [("data-act", "inc")], [
        @core.View::text("+"),
      ])
    },
    on_action=[(@core.ActionSpec::new("click", "inc"), increment_own_count)],
  )
  let id = @dom.probe_create("x-self-counter")
  @dom.probe_connect(id)
  assert_eq(@dom.instance_prop_int(id, "count"), Some(0))
  @dom.probe_fire_action(id, "click", "inc")
  assert_eq(@dom.instance_prop_int(id, "count"), Some(1))
  @dom.probe_fire_action(id, "click", "inc")
  assert_eq(@dom.instance_prop_int(id, "count"), Some(2))
}
