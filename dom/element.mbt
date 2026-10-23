///|
/// Browser adapter for `core`: DOM wiring and instance state.

///|
priv struct ActionBinding {
  spec : @core.ActionSpec
  run : (Int32, String) -> Unit
}

///|
priv struct ComponentDef {
  tag : String
  specs : Array[@core.AttrSpec]
  render_fn : (@core.Props) -> @core.View
  events : Array[@core.EventSpec]
  styles : String
  mode : @core.RenderMode
  actions : Array[ActionBinding]
  // Event types with a listener, joined by "\n" so the value crosses the FFI as a string
  // (event names cannot contain whitespace, so the separator is unambiguous).
  action_events : String
}

///|
priv struct Instance {
  props : @core.Props
  lifecycle : @core.Lifecycle
  render_fn : (@core.Props) -> @core.View
  event_registry : @core.EventRegistry
  event_log : Array[String]
  tag : String
  styles : String
  mode : @core.RenderMode
  actions : Array[ActionBinding]
  action_log : Array[String]
}

///|
/// Instance registry keyed by instance id; slot 0 is unused.
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
/// Always writes back and does not rely on struct alias semantics: the change
/// lands in the registry even if `instance_get` returned a copy.
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
        actions: def.actions,
        action_log: [],
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
        // Light mode: component CSS leaks into the page, so scope it to the tag.
        // Shadow mode: inject as is (`:host` is valid only inside a shadow root).
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
/// Define a custom element (`define` is a reserved word). Attributes set before
/// connection (element upgrade) are handled.
pub fn define_component(
  tag : String,
  specs : Array[@core.AttrSpec],
  render_fn : (@core.Props) -> @core.View,
  events~ : Array[@core.EventSpec] = [],
  on_change~ : (Int32, String) -> Unit = fn(_id, _name) { () },
  styles~ : String = "",
  mode~ : @core.RenderMode = @core.ShadowDom,
  on_action~ : Array[(@core.ActionSpec, (Int32, String) -> Unit)] = [],
) -> Unit {
  // Invalid or duplicate pairs are dropped instead of failing the whole definition.
  let action_registry = @core.ActionRegistry::new()
  let actions : Array[ActionBinding] = []
  for binding in on_action {
    if action_registry.add(binding.0) {
      actions.push({ spec: binding.0, run: binding.1, })
    }
  }
  let mut action_events = ""
  for event_type in action_registry.event_types() {
    if action_events != "" {
      action_events = action_events + "\n"
    }
    action_events = action_events + event_type
  }
  let def : ComponentDef = {
    tag,
    specs,
    render_fn,
    events,
    styles,
    mode,
    actions,
    action_events,
  }
  let use_shadow = match mode {
    @core.ShadowDom => true
    @core.LightDom => false
  }
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
  // Old/new values cross the FFI as (Bool + String) rather than String?: the Option
  // representation is not a stable ABI.
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
    // Notify after state and DOM are updated.
    on_change(id, name)
  }
  let on_action : (Int32, String, String) -> Unit = fn(id, event_type, action) {
    let inst = ensure_instance(id, def)
    for binding in inst.actions {
      if binding.spec.event() == event_type && binding.spec.action() == action {
        inst.action_log.push("\{event_type}:\{action}")
        instance_put(id, inst)
        let run = binding.run
        run(id, action)
      }
    }
  }
  js_define(
    tag,
    observed,
    on_connected,
    on_disconnected,
    on_attribute,
    use_shadow,
    def.action_events,
    on_action,
  )
}

///|
/// Actions handled so far, in order, as "event:action" (diagnostics and tests).
pub fn instance_action_log(id : Int32) -> Array[String] {
  match instance_get(id) {
    Some(inst) => inst.action_log
    None => []
  }
}

///|
pub fn instance_reaction_log(id : Int32) -> Array[String] {
  match instance_get(id) {
    Some(inst) => inst.lifecycle.reaction_log()
    None => []
  }
}

///|
/// Parsed value; fallback already applied.
pub fn instance_prop(id : Int32, attr_name : String) -> @core.AttrValue? {
  match instance_get(id) {
    Some(inst) => inst.props.get(attr_name)
    None => None
  }
}

///|
pub fn instance_prop_string(id : Int32, attr_name : String) -> String? {
  match instance_get(id) {
    Some(inst) => inst.props.get_string(attr_name)
    None => None
  }
}

///|
pub fn instance_prop_int(id : Int32, attr_name : String) -> Int32? {
  match instance_get(id) {
    Some(inst) => inst.props.get_int(attr_name)
    None => None
  }
}

// JS-side wiring and test probes; headlessly the probes replay the browser call order.

///|
extern "js" fn js_define(
  tag : String,
  observed : FixedArray[String],
  on_connected : (Int32) -> Unit,
  on_disconnected : (Int32) -> Unit,
  on_attribute : (Int32, String, Bool, String, Bool, String) -> Unit,
  use_shadow : Bool,
  action_events : String,
  on_action : (Int32, String, String) -> Unit,
) -> Unit =
  #|(tag, observed, onConnected, onDisconnected, onAttribute, useShadow, actionEvents, onAction) => {
  #|  const actionTypes = actionEvents ? String(actionEvents).split("\n").filter(Boolean) : [];
  #|  // Walk up from the event target to the listener's container looking for data-act.
  #|  const findAction = (container, ev) => {
  #|    let node = ev.target;
  #|    while (node && node !== container) {
  #|      if (typeof node.getAttribute === "function") {
  #|        const act = node.getAttribute("data-act");
  #|        if (act) return act;
  #|      }
  #|      node = node.parentNode;
  #|    }
  #|    return null;
  #|  };
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
  #|      if (useShadow && !this.shadowRoot) {
  #|        this.attachShadow({ mode: "open" });
  #|      }
  #|      // One listener per event type on the shadow root (or the host in light mode): both
  #|      // survive re-rendering, unlike listeners on the replaced content.
  #|      if (!this.__moonActionsBound && actionTypes.length > 0) {
  #|        this.__moonActionsBound = true;
  #|        const container = useShadow ? this.shadowRoot : this;
  #|        for (const type of actionTypes) {
  #|          container.addEventListener(type, (ev) => {
  #|            const action = findAction(container, ev);
  #|            if (action) {
  #|              onAction(this.__moonId, type, action);
  #|            }
  #|          });
  #|        }
  #|      }
  #|      onConnected(this.__moonId);
  #|    }
  #|    disconnectedCallback() {
  #|      onDisconnected(this.__moonId);
  #|    }
  #|    attributeChangedCallback(name, oldValue, newValue) {
  #|      const hadOld = oldValue !== null && oldValue !== undefined;
  #|      const hasNew = newValue !== null && newValue !== undefined;
  #|      // Keep the current value so the next probe reports the right oldValue.
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
extern "js" fn js_set_inner_html(id : Int32, html : String) -> Unit =
  #|(id, html) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el) {
  #|    el.innerHTML = html;
  #|  }
  #|}

///|
pub extern "js" fn probe_inner_html(id : Int32) -> String =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  return el ? el.innerHTML || "" : "";
  #|}

///|
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
pub extern "js" fn probe_connect(id : Int32) -> Unit =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el) {
  #|    el.connectedCallback();
  #|  }
  #|}

///|
pub extern "js" fn probe_disconnect(id : Int32) -> Unit =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (el) {
  #|    el.disconnectedCallback();
  #|  }
  #|}

///|
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

///|
/// Sets an attribute on the host element, which re-renders the component through the normal
/// attribute pipeline. Returns silently for an unknown id.
pub extern "js" fn set_attribute(
  id : Int32,
  name : String,
  value : String,
) -> Unit =
  #|(id, name, value) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (!el) return;
  #|  if (typeof el.setAttribute === "function") {
  #|    el.setAttribute(name, String(value));
  #|    return;
  #|  }
  #|  const old = el.__moonAttrs ? el.__moonAttrs[name] : undefined;
  #|  el.attributeChangedCallback(name, old === undefined ? null : old, String(value));
  #|}

///|
/// Removes an attribute from the host element; the value falls back to the spec default.
pub extern "js" fn remove_attribute(id : Int32, name : String) -> Unit =
  #|(id, name) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (!el) return;
  #|  if (typeof el.removeAttribute === "function") {
  #|    el.removeAttribute(name);
  #|    return;
  #|  }
  #|  const old = el.__moonAttrs ? el.__moonAttrs[name] : undefined;
  #|  el.attributeChangedCallback(name, old === undefined ? null : old, null);
  #|}

///|
/// Simulates an event from an element carrying `data-act="action"`, with one non-actionable
/// element in between so the walk up the tree is exercised.
pub extern "js" fn probe_fire_action(
  id : Int32,
  event : String,
  action : String,
) -> Unit =
  #|(id, type, action) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (!el) return;
  #|  const container = el.shadowRoot ? el.shadowRoot : el;
  #|  const middle = { getAttribute: () => null, parentNode: container };
  #|  const target = {
  #|    getAttribute: (name) => (name === "data-act" && action ? action : null),
  #|    parentNode: middle,
  #|  };
  #|  container.dispatchEvent({ type, target, defaultPrevented: false });
  #|}

///|
pub extern "js" fn probe_shadow_html(id : Int32) -> String =
  #|(id) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  return el && el.shadowRoot ? el.shadowRoot.innerHTML : "";
  #|}
