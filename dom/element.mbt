///|
/// Browser adapter: wires the `core` attribute specs and lifecycle state machine
/// onto the real custom element callbacks (`observedAttributes` /
/// `attributeChangedCallback` / `connectedCallback` / `disconnectedCallback`) and
/// writes the render output into the shadow root.
///
/// Attribute parsing, fallback and lifecycle rules live in `core`; this file only
/// does the DOM wiring and instance state management.

///|
/// Static definition of a registered component, shared by all instances of a tag.
priv struct ComponentDef {
  tag : String
  specs : Array[@core.AttrSpec]
  render_fn : (@core.Props) -> @core.View
  events : Array[@core.EventSpec]
  styles : String
  mode : @core.RenderMode
}

///|
/// MoonBit-side state of one element instance.
priv struct Instance {
  props : @core.Props
  lifecycle : @core.Lifecycle
  render_fn : (@core.Props) -> @core.View
  event_registry : @core.EventRegistry
  // Dispatched events (diagnostics and tests): "name:detail:canceled"
  event_log : Array[String]
  // Needed at render time: scopes scope_css in light mode
  tag : String
  styles : String
  mode : @core.RenderMode
}

///|
/// Instance registry: the index is the instance id (slot 0 is a placeholder; JS
/// assigns ids by incrementing). An array instead of a hash map: one less
/// dependency, and id and index correspond one to one.
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
/// Write instance state back.
/// Always writes back and does not rely on struct alias semantics, so a state
/// change reaches the registry even if `instance_get` returned a copy.
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
        // In light mode component CSS leaks into the whole page, so scope it to
        // the tag name first; shadow mode injects it as is (`:host` is only
        // valid inside a shadow root)
        let css = match inst.mode {
          @core.ShadowDom => inst.styles
          @core.LightDom => @core.scope_css(inst.styles, inst.tag)
        }
        "<style>" + css + "</style>" + body
      }
      match inst.mode {
        @core.ShadowDom => js_set_shadow_html(id, html)
        @core.LightDom => js_set_inner_html(id, html)
      }
    }
    None => ()
  }
}

///|
/// Define a custom element (`define` is a reserved word, hence `define_component`).
///
/// - `specs` drives `observedAttributes`: only the listed attributes trigger callbacks
/// - `render_fn` runs when the element connects and when any observed attribute
///   changes while the element is connected; the returned view is rendered to HTML
///   and written into the shadow root
/// - attributes set before connection (what the browser does when upgrading an
///   existing element) are handled too
/// - `events` declares the events this component dispatches (names are validated,
///   duplicates rejected); the declaration decides bubbles / composed at dispatch
///   time. Undeclared events can still be dispatched, with conservative defaults
/// - `on_change` runs after every observed attribute change once state updates
///   (re-render included) are done, with (instance id, attribute name) as
///   arguments; a component dispatches outward events from here via `dispatch`
/// - `styles` is the component CSS, written once: injected as is in shadow mode
///   (`:host` works there), scoped to the tag name with `scope_css` first in light
///   mode
/// - `mode` picks shadow DOM (default) or light DOM; light mode suits SSR output
///   or cases where host styles must reach the component
pub fn define_component(
  tag : String,
  specs : Array[@core.AttrSpec],
  render_fn : (@core.Props) -> @core.View,
  events~ : Array[@core.EventSpec] = [],
  on_change~ : (Int32, String) -> Unit = fn(_id, _name) { () },
  styles~ : String = "",
  mode~ : @core.RenderMode = @core.ShadowDom,
) -> Unit {
  let def : ComponentDef = { tag, specs, render_fn, events, styles, mode, }
  let use_shadow = match mode {
    @core.ShadowDom => true
    @core.LightDom => false
  }
  // FixedArray has a fixed length (no push): allocate first, then assign by index
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
  // Old/new values cross the FFI as (presence Bool + String) rather than String?:
  // the Option representation is not a stable ABI, so an explicit presence flag is
  // more reliable.
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
    // Do not render while disconnected: the browser renders no element outside the document
    if inst.lifecycle.is_connected() {
      paint(id)
    }
    // Notify the caller after state and DOM are updated, so the callback sees consistent state
    on_change(id, name)
  }
  js_define(
    tag, observed, on_connected, on_disconnected, on_attribute, use_shadow,
  )
}

///|
/// Lifecycle reaction log of an instance, for diagnostics and tests.
pub fn instance_reaction_log(id : Int32) -> Array[String] {
  match instance_get(id) {
    Some(inst) => inst.lifecycle.reaction_log()
    None => []
  }
}

///|
/// Current attribute value of an instance (parsed and fallback applied), for diagnostics and tests.
pub fn instance_prop(id : Int32, attr_name : String) -> @core.AttrValue? {
  match instance_get(id) {
    Some(inst) => inst.props.get(attr_name)
    None => None
  }
}

///|
/// Current string attribute of an instance, for diagnostics and tests.
pub fn instance_prop_string(id : Int32, attr_name : String) -> String? {
  match instance_get(id) {
    Some(inst) => inst.props.get_string(attr_name)
    None => None
  }
}

///|
/// Current integer attribute of an instance, for diagnostics and tests.
pub fn instance_prop_int(id : Int32, attr_name : String) -> Int32? {
  match instance_get(id) {
    Some(inst) => inst.props.get_int(attr_name)
    None => None
  }
}

// ---------------------------------------------------------------------------
// JS-side wiring and test probes. In a real browser the browser fires these
// callbacks; headlessly (node) the probes replay the same call order.
// ---------------------------------------------------------------------------

///|
/// Register a custom element class:
/// - the constructor assigns the instance id and records it in the id -> element map
/// - `observedAttributes` comes from the specs
/// - `connectedCallback` creates the shadow root on demand, then enters MoonBit
/// - `attributeChangedCallback` turns null old/new values into (presence + string)
///   before entering MoonBit
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
  #|      // light mode creates no shadow root: content goes into the element itself
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
  #|      // remember the current value so the next probe reports the right oldValue (the browser does the same)
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
/// Light mode: write the render output into the element itself (no shadow root)
extern "js" fn js_set_inner_html(id : Int32, html : String) -> Unit =
  #|(id, html) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el) {
  #|    el.innerHTML = html;
  #|  }
  #|}

///|
/// Probe: innerHTML of the element itself (asserted in light mode; empty in shadow mode)
pub extern "js" fn probe_inner_html(id : Int32) -> String =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  return el ? el.innerHTML || "" : "";
  #|}

///|
/// Probe: `observedAttributes` of a tag.
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
/// Probe: create an instance and return its id (the constructor assigns the id).
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
/// Probe: simulate the browser inserting the element into the document.
pub extern "js" fn probe_connect(id : Int32) -> Unit =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el) {
  #|    el.connectedCallback();
  #|  }
  #|}

///|
/// Probe: simulate the browser removing the element from the document.
pub extern "js" fn probe_disconnect(id : Int32) -> Unit =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el) {
  #|    el.disconnectedCallback();
  #|  }
  #|}

///|
/// Probe: simulate the browser setting an attribute (oldValue comes from the last record).
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
/// Probe: simulate the browser removing an attribute.
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
/// Probe: current HTML of the instance shadow root.
pub extern "js" fn probe_shadow_html(id : Int32) -> String =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  return el && el.shadowRoot ? el.shadowRoot.innerHTML : "";
  #|}
