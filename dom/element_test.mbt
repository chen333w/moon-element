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
