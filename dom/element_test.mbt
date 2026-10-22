///|
/// 浏览器适配层的黑盒测试。
///
/// 无浏览器环境（node）下用探针模拟浏览器的调用顺序：
/// `new` → `attributeChangedCallback` → `connectedCallback` → 属性变更 → `disconnectedCallback`。
/// 真实浏览器里的顺序与此一致（升级已有元素时，属性回调发生在连接之前）。

///|
fn specs() -> Array[@core.AttrSpec] {
  [
    @core.AttrSpec::string("label", "?"),
    @core.AttrSpec::int("max-count", 3),
    @core.AttrSpec::bool("disabled", false),
  ]
}

///|
/// 测试用的渲染函数：把两个属性值渲染成一个 span 文本。
fn render_badge(props : @core.Props) -> @core.View {
  let label = props.get_string("label").unwrap_or("?")
  let count = props.get_int("max-count").unwrap_or(0)
  @core.View::element("span", [("class", "badge")], [
    @core.View::text("\{label}:\{count}"),
  ])
}

///|
test "adapter: observedAttributes 来自规格，只列被声明的属性" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-1", specs(), render_badge)
  assert_eq(@dom.probe_observed("x-badge-1"), ["label", "max-count", "disabled"])
}

///|
test "adapter: 属性先于连接设置（升级已有元素的情形）" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-2", specs(), render_badge)
  let id = @dom.probe_create("x-badge-2")
  // 浏览器在升级已有元素时，会先回调 observed 属性，再回调 connectedCallback
  @dom.probe_set_attribute(id, "label", "hi")
  assert_eq(@dom.instance_prop_string(id, "label"), Some("hi"))
  assert_eq(@dom.instance_reaction_log(id), ["attribute:label:<none>->hi"])
  // 未连接时不渲染
  assert_eq(@dom.probe_shadow_html(id), "")
}

///|
test "adapter: 连接后渲染进 shadow root，且值来自属性" {
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
test "adapter: 已连接时属性变化触发重渲染" {
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
test "adapter: 非法属性值回退默认值并重渲染" {
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
test "adapter: 布尔属性按存在即真，移除后回到默认值" {
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
test "adapter: 断开与重连，计数与反应日志都对" {
  @dom.install_dom_stub()
  @dom.define_component("x-badge-7", specs(), render_badge)
  let id = @dom.probe_create("x-badge-7")
  @dom.probe_connect(id)
  @dom.probe_disconnect(id)
  @dom.probe_connect(id)
  assert_eq(@dom.instance_reaction_log(id), [
    "connected", "disconnected", "connected",
  ])
  // 断开后属性变化不渲染，但会被记录
  @dom.probe_disconnect(id)
  @dom.probe_set_attribute(id, "label", "later")
  assert_eq(@dom.instance_reaction_log(id), [
    "connected", "disconnected", "connected", "disconnected", "attribute:label:<none>->later",
  ])
}

///|
test "adapter: 两个实例互不干扰" {
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
test "adapter: on_change 在状态更新后触发，可用于派发对外事件" {
  @dom.install_dom_stub()
  let seen : Array[String] = []
  @dom.define_component(
    "x-change-probe",
    specs(),
    render_badge,
    events=[@core.EventSpec::crossing("changed")],
    on_change=fn(id, name) {
      seen.push(name)
      // 这是事件系统预期的用法：组件自己不需要知道实例 id
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
  // 回调在渲染之后：此时读到的 DOM 已经是新值
  assert_eq(@dom.probe_shadow_html(id), "<span class=\"badge\">x:5</span>")
}

///|
test "adapter: 无效实例 id 的诊断查询返回空，不抛错" {
  @dom.install_dom_stub()
  assert_eq(@dom.instance_reaction_log(9999), [])
  assert_eq(@dom.instance_event_log(9999), [])
  assert_eq(@dom.instance_event_names(9999), [])
  assert_true(@dom.instance_prop(9999, "label") is None)
  assert_true(@dom.instance_prop_string(9999, "label") is None)
  assert_true(@dom.instance_prop_int(9999, "label") is None)
}

///|
test "adapter: 未连接就断开（元素已创建但从未触发过回调）不产生反应" {
  @dom.install_dom_stub()
  @dom.define_component("x-never-connected", specs(), render_badge)
  let id = @dom.probe_create("x-never-connected")
  // 这个实例在 MoonBit 侧还不存在，disconnectedCallback 不应抛错
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
test "adapter: light 模式不建 shadow root，并用 scope_css 把样式作用域到标签名" {
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
  // 没有 shadow root
  assert_eq(@dom.probe_shadow_html(id), "")
  // :host 被替换为标签名，普通选择器加上标签名前缀 —— 这就是 core.scope_css 的产出
  inspect(
    @dom.probe_inner_html(id),
    content="<style>x-light-card { display: block } x-light-card p { color: red }</style><p>?</p>",
  )
  // 属性变化重渲染时作用域前缀保持稳定
  @dom.probe_set_attribute(id, "label", "hi")
  inspect(
    @dom.probe_inner_html(id),
    content="<style>x-light-card { display: block } x-light-card p { color: red }</style><p>hi</p>",
  )
}

///|
test "adapter: shadow 模式样式原样注入，:host 保持不动" {
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
  // 内容在 shadow root 里，元素自身是空的
  assert_eq(@dom.probe_inner_html(id), "")
}

///|
test "adapter: 没写 styles 时不注入空 style 标签" {
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
