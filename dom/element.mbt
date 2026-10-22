///|
/// 浏览器适配层：把 `core` 的属性规格与生命周期状态机接到真实的
/// custom element 回调上（`observedAttributes` / `attributeChangedCallback` /
/// `connectedCallback` / `disconnectedCallback`），并把渲染结果写进 shadow root。
///
/// 分层原则：**所有规则都在 `core` 里**（属性解析、回退、生命周期），本文件只负责
/// 与 DOM 的接线和实例状态管理。因此 core 的规则能在四个后端上测，
/// 这里只需要测「接线是否接对了」。

///|
/// 渲染模式。
///
/// - `ShadowDom`（默认）：渲染进 shadow root，样式天然隔离，`:host` 直接可用
/// - `LightDom`：渲染进元素自身（不建 shadow root）。此时组件 CSS 会先用
///   `core.scope_css` 作用域到标签名，避免污染整页 —— 用于 SSR 输出，
///   或需要宿主页面样式透入的场合
pub(all) enum RenderMode {
  ShadowDom
  LightDom
} derive(Eq)

///|
/// `derive(Eq)` 生成的方法默认会被隐式提升为普通方法（已废弃行为），显式声明以消除警告。
pub extend RenderMode with Eq::{equal, not_equal}

///|
/// 一个已注册组件的静态定义（同 tag 的所有实例共享）。
priv struct ComponentDef {
  tag : String
  specs : Array[@core.AttrSpec]
  render_fn : (@core.Props) -> @core.View
  events : Array[@core.EventSpec]
  styles : String
  mode : RenderMode
}

///|
/// 一个元素实例在 MoonBit 侧的状态。
priv struct Instance {
  props : @core.Props
  lifecycle : @core.Lifecycle
  render_fn : (@core.Props) -> @core.View
  event_registry : @core.EventRegistry
  // 派发过的事件记录（诊断与测试用）："name:detail:canceled"
  event_log : Array[String]
  // 渲染时需要：light 模式下作为 scope_css 的作用域
  tag : String
  styles : String
  mode : RenderMode
}

///|
/// 实例注册表：下标即实例 id（0 号占位，id 由 JS 侧自增分配，天然连续）。
/// 用数组而不是哈希表，是为了少一个依赖、并且让 id 与下标一一对应。
let instances : Array[Instance?] = [None]

///|
fn instance_get(id : Int32) -> Instance? {
  if id > 0 && id < instances.length() {
    instances[id]
  } else {
    None
  }
}

///|
/// 写回实例状态。
///
/// 每次都写回，是为了**不依赖结构体的别名语义**：即使 `instance_get` 取出的是一份
/// 拷贝，写回也能保证状态变更落到注册表里。
fn instance_put(id : Int32, inst : Instance) -> Unit {
  while instances.length() <= id {
    instances.push(None)
  }
  instances[id] = Some(inst)
}

///|
fn ensure_instance(id : Int32, def : ComponentDef) -> Instance {
  match instance_get(id) {
    Some(inst) => inst
    None => {
      let event_registry = @core.EventRegistry::new()
      for spec in def.events {
        let _ = event_registry.add(spec)
      }
      let inst : Instance = {
        props: @core.Props::new(def.specs),
        lifecycle: @core.Lifecycle::new(),
        render_fn: def.render_fn,
        event_registry,
        event_log: [],
        tag: def.tag,
        styles: def.styles,
        mode: def.mode,
      }
      instance_put(id, inst)
      inst
    }
  }
}

///|
fn paint(id : Int32) -> Unit {
  match instance_get(id) {
    Some(inst) => {
      let render_fn = inst.render_fn
      let body = @core.render(render_fn(inst.props))
      let html = if inst.styles == "" {
        body
      } else {
        // light 模式下组件的 CSS 会泄漏到整页，先用 scope_css 作用域到标签名；
        // shadow 模式保持原样（`:host` 在 shadow root 里才是有效的）
        let css = match inst.mode {
          ShadowDom => inst.styles
          LightDom => @core.scope_css(inst.styles, inst.tag)
        }
        "<style>" + css + "</style>" + body
      }
      match inst.mode {
        ShadowDom => js_set_shadow_html(id, html)
        LightDom => js_set_inner_html(id, html)
      }
    }
    None => ()
  }
}

///|
/// 定义一个自定义元素（`define` 是保留字，所以叫 `define_component`）。
///
/// - `specs` 决定 `observedAttributes`：只有列出的属性会触发回调
/// - `render_fn` 在元素连接时、以及任何被观察属性变化且元素处于连接状态时被调用；
///   返回的视图渲染成 HTML 写入 shadow root
/// - 属性在连接**之前**就被设置（浏览器在升级已有元素时就是这么做的）也能正确处理
/// - `events` 声明本组件会派发的事件（名字会被校验、重名会被拒），
///   派发时按声明决定 bubbles / composed；未声明的事件仍可派发，但用保守默认值
/// - `on_change` 在每次被观察属性变化、且状态更新完毕（含重渲染）之后被调用，
///   参数是 (实例 id, 属性名)。这是组件对外派发事件的入口：在回调里调用 `dispatch`，
///   避免让用户自己去猜实例 id
/// - `styles` 是组件的 CSS，只写一次：shadow 模式下原样注入（`:host` 可用），
///   light 模式下先用 `scope_css` 作用域到标签名再注入
/// - `mode` 选 shadow DOM（默认）还是 light DOM；light 模式适合 SSR 输出或
///   需要宿主样式透入的场合
pub fn define_component(
  tag : String,
  specs : Array[@core.AttrSpec],
  render_fn : (@core.Props) -> @core.View,
  events~ : Array[@core.EventSpec] = [],
  on_change~ : (Int32, String) -> Unit = fn(_id, _name) { () },
  styles~ : String = "",
  mode~ : RenderMode = ShadowDom,
) -> Unit {
  let def : ComponentDef = { tag, specs, render_fn, events, styles, mode, }
  let use_shadow = match mode {
    ShadowDom => true
    LightDom => false
  }
  // FixedArray 是定长数组（没有 push），先分配再按下标写入
  let observed : FixedArray[String] = FixedArray::make(specs.length(), "")
  let mut oi = 0
  while oi < specs.length() {
    observed[oi] = specs[oi].attr_name()
    oi = oi + 1
  }
  let on_connected : (Int32) -> Unit = fn(id) {
    let inst = ensure_instance(id, def)
    if inst.lifecycle.on_connect() {
      instance_put(id, inst)
      paint(id)
    }
  }
  let on_disconnected : (Int32) -> Unit = fn(id) {
    match instance_get(id) {
      Some(inst) => if inst.lifecycle.on_disconnect() { instance_put(id, inst) }
      None => ()
    }
  }
  // 老/新值用「是否存在 + 字符串」两个参数传，而不是 String?：
  // Option 的跨 FFI 表示不是稳定 ABI，显式传存在性更可靠。
  let on_attribute : (Int32, String, Bool, String, Bool, String) -> Unit = fn(
    id,
    name,
    had_old,
    old_value,
    has_new,
    new_value,
  ) {
    let inst = ensure_instance(id, def)
    let old_opt : String? = if had_old { Some(old_value) } else { None }
    let new_opt : String? = if has_new { Some(new_value) } else { None }
    inst.lifecycle.on_attribute_changed(name, old_opt, new_opt)
    let _ = inst.props.apply(name, new_opt)
    instance_put(id, inst)
    // 未连接时不渲染：浏览器也不会渲染一个不在文档里的元素
    if inst.lifecycle.is_connected() {
      paint(id)
    }
    // 状态与 DOM 都更新完了再通知调用方，这样回调里读到的是一致的状态
    on_change(id, name)
  }
  js_define(
    tag, observed, on_connected, on_disconnected, on_attribute, use_shadow,
  )
}

///|
/// 实例的生命周期反应日志，用于诊断与测试。
pub fn instance_reaction_log(id : Int32) -> Array[String] {
  match instance_get(id) {
    Some(inst) => inst.lifecycle.reaction_log()
    None => []
  }
}

///|
/// 读取实例当前的某个属性取值（已解析、已回退），用于诊断与测试。
pub fn instance_prop(id : Int32, attr_name : String) -> @core.AttrValue? {
  match instance_get(id) {
    Some(inst) => inst.props.get(attr_name)
    None => None
  }
}

///|
/// 读取实例当前的某个字符串属性，用于诊断与测试。
pub fn instance_prop_string(id : Int32, attr_name : String) -> String? {
  match instance_get(id) {
    Some(inst) => inst.props.get_string(attr_name)
    None => None
  }
}

///|
/// 读取实例当前的某个整数属性，用于诊断与测试。
pub fn instance_prop_int(id : Int32, attr_name : String) -> Int32? {
  match instance_get(id) {
    Some(inst) => inst.props.get_int(attr_name)
    None => None
  }
}

// ---------------------------------------------------------------------------
// 下面是 JS 侧接线与测试探针。真实浏览器里由浏览器触发回调；
// 无浏览器环境（node）下用探针模拟同样的调用顺序。
// ---------------------------------------------------------------------------

///|
/// 注册一个自定义元素类：
/// - 构造函数分配实例 id，并登记到 id → 元素 的映射
/// - `observedAttributes` 取自规格
/// - `connectedCallback` 里按需创建 shadow root，然后再进 MoonBit
/// - `attributeChangedCallback` 把 null 的老/新值转成「存在性 + 字符串」再进 MoonBit
extern "js" fn js_define(
  tag : String,
  observed : FixedArray[String],
  on_connected : (Int32) -> Unit,
  on_disconnected : (Int32) -> Unit,
  on_attribute : (Int32, String, Bool, String, Bool, String) -> Unit,
  use_shadow : Bool,
) -> Unit =
  #|(tag, observed, onConnected, onDisconnected, onAttribute, useShadow) => {
  #|  const reg =
  #|    globalThis.__moon_element_instances ||
  #|    (globalThis.__moon_element_instances = {
  #|      nextId: 1,
  #|      byId: Object.create(null),
  #|      byTag: Object.create(null),
  #|    });
  #|  class MoonElement extends globalThis.HTMLElement {
  #|    constructor() {
  #|      super();
  #|      this.__moonId = reg.nextId++;
  #|      this.__moonAttrs = Object.create(null);
  #|      reg.byId[this.__moonId] = this;
  #|    }
  #|    static get observedAttributes() {
  #|      return observed;
  #|    }
  #|    connectedCallback() {
  #|      // light 模式下不建 shadow root：内容直接写进元素自身
  #|      if (useShadow && !this.shadowRoot) {
  #|        this.attachShadow({ mode: "open" });
  #|      }
  #|      onConnected(this.__moonId);
  #|    }
  #|    disconnectedCallback() {
  #|      onDisconnected(this.__moonId);
  #|    }
  #|    attributeChangedCallback(name, oldValue, newValue) {
  #|      const hadOld = oldValue !== null && oldValue !== undefined;
  #|      const hasNew = newValue !== null && newValue !== undefined;
  #|      // 记住当前值，这样探针下次能给出正确的 oldValue（浏览器也会这么传）
  #|      if (hasNew) {
  #|        this.__moonAttrs[name] = String(newValue);
  #|      } else {
  #|        delete this.__moonAttrs[name];
  #|      }
  #|      onAttribute(
  #|        this.__moonId,
  #|        name,
  #|        hadOld,
  #|        hadOld ? String(oldValue) : "",
  #|        hasNew,
  #|        hasNew ? String(newValue) : "",
  #|      );
  #|    }
  #|  }
  #|  reg.byTag[tag] = MoonElement;
  #|  globalThis.customElements.define(tag, MoonElement);
  #|}

///|
extern "js" fn js_set_shadow_html(id : Int32, html : String) -> Unit =
  #|(id, html) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el && el.shadowRoot) {
  #|    el.shadowRoot.innerHTML = html;
  #|  }
  #|}

///|
/// light 模式：把渲染结果写进元素自身（没有 shadow root）
extern "js" fn js_set_inner_html(id : Int32, html : String) -> Unit =
  #|(id, html) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el) {
  #|    el.innerHTML = html;
  #|  }
  #|}

///|
/// 探针：元素自身的 innerHTML（light 模式下用它断言；shadow 模式下为空）
pub extern "js" fn probe_inner_html(id : Int32) -> String =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  return el ? el.innerHTML || "" : "";
  #|}

///|
/// 探针：某个 tag 的 `observedAttributes`。
pub fn probe_observed(tag : String) -> Array[String] {
  let out : Array[String] = []
  for name in js_probe_observed(tag) {
    out.push(name)
  }
  out
}

///|
extern "js" fn js_probe_observed(tag : String) -> FixedArray[String] =
  #|(tag) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const ctor = reg && reg.byTag[tag];
  #|  const list = ctor && ctor.observedAttributes;
  #|  return list ? Array.from(list) : [];
  #|}

///|
/// 探针：创建一个实例并返回它的 id（构造函数会分配 id）。
pub extern "js" fn probe_create(tag : String) -> Int32 =
  #|(tag) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const ctor = reg && reg.byTag[tag];
  #|  if (!ctor) {
  #|    throw new Error("custom element not defined: " + tag);
  #|  }
  #|  const el = new ctor();
  #|  return el.__moonId;
  #|}

///|
/// 探针：模拟浏览器把元素插入文档。
pub extern "js" fn probe_connect(id : Int32) -> Unit =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el) {
  #|    el.connectedCallback();
  #|  }
  #|}

///|
/// 探针：模拟浏览器把元素移出文档。
pub extern "js" fn probe_disconnect(id : Int32) -> Unit =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el) {
  #|    el.disconnectedCallback();
  #|  }
  #|}

///|
/// 探针：模拟浏览器设置属性（oldValue 取上次记录的值）。
pub extern "js" fn probe_set_attribute(
  id : Int32,
  name : String,
  value : String,
) -> Unit =
  #|(id, name, value) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (!el) {
  #|    return;
  #|  }
  #|  const old = el.__moonAttrs[name];
  #|  el.attributeChangedCallback(
  #|    name,
  #|    old === undefined ? null : old,
  #|    value,
  #|  );
  #|}

///|
/// 探针：模拟浏览器移除属性。
pub extern "js" fn probe_remove_attribute(id : Int32, name : String) -> Unit =
  #|(id, name) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (!el) {
  #|    return;
  #|  }
  #|  const old = el.__moonAttrs[name];
  #|  el.attributeChangedCallback(
  #|    name,
  #|    old === undefined ? null : old,
  #|    null,
  #|  );
  #|}

///|
/// 探针：实例 shadow root 的当前 HTML。
pub extern "js" fn probe_shadow_html(id : Int32) -> String =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  return el && el.shadowRoot ? el.shadowRoot.innerHTML : "";
  #|}
