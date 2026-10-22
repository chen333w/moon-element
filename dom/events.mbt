///|
/// Event dispatch: `core` event specs onto the browser `CustomEvent`.

///|
/// Undeclared names still dispatch, with conservative defaults (no bubbling, no
/// shadow boundary crossing).
pub fn dispatch(
  id : Int32,
  event_name : String,
  detail : String,
  cancelable : Bool,
) -> Bool {
  let spec = match instance_get(id) {
    Some(inst) => inst.event_registry.find(event_name)
    None => None
  }
  let bubbles = match spec {
    Some(s) => s.bubbles()
    None => false
  }
  let composed = match spec {
    Some(s) => s.composed()
    None => false
  }
  let canceled = js_dispatch(
    id, event_name, detail, bubbles, composed, cancelable,
  )
  match instance_get(id) {
    Some(inst) => {
      inst.event_log.push("\{event_name}|\{detail}|canceled=\{canceled}")
      instance_put(id, inst)
    }
    None => ()
  }
  canceled
}

///|
pub fn instance_event_log(id : Int32) -> Array[String] {
  match instance_get(id) {
    Some(inst) => inst.event_log
    None => []
  }
}

///|
pub fn instance_event_names(id : Int32) -> Array[String] {
  match instance_get(id) {
    Some(inst) => inst.event_registry.names()
    None => []
  }
}

///|
extern "js" fn js_dispatch(
  id : Int32,
  event_name : String,
  detail : String,
  bubbles : Bool,
  composed : Bool,
  cancelable : Bool,
) -> Bool =
  #|(id, name, detail, bubbles, composed, cancelable) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (!el) {
  #|    return false;
  #|  }
  #|  const ev = new globalThis.CustomEvent(name, {
  #|    detail,
  #|    bubbles,
  #|    composed,
  #|    cancelable,
  #|  });
  #|  // dispatchEvent returns false when a listener called preventDefault
  #|  const notCanceled = el.dispatchEvent(ev);
  #|  return !notCanceled;
  #|}

// Test probes: simulate listeners headlessly

///|
pub extern "js" fn probe_add_listener(id : Int32, event_name : String) -> Unit =
  #|(id, name) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (!el) {
  #|    return;
  #|  }
  #|  const logs =
  #|    globalThis.__moon_element_listener_log ||
  #|    (globalThis.__moon_element_listener_log = Object.create(null));
  #|  if (!logs[id]) {
  #|    logs[id] = [];
  #|  }
  #|  el.addEventListener(name, (ev) => {
  #|    logs[id].push(
  #|      ev.type +
  #|        "|" +
  #|        ev.detail +
  #|        "|bubbles=" +
  #|        ev.bubbles +
  #|        "|composed=" +
  #|        ev.composed,
  #|    );
  #|  });
  #|}

///|
pub extern "js" fn probe_add_canceling_listener(
  id : Int32,
  event_name : String,
) -> Unit =
  #|(id, name) => {
  #|  const reg = globalThis.__moon_element_instances;
  #|  const el = reg && reg.byId[id];
  #|  if (!el) {
  #|    return;
  #|  }
  #|  el.addEventListener(name, (ev) => {
  #|    ev.preventDefault();
  #|  });
  #|}

///|
pub fn probe_listener_log(id : Int32) -> Array[String] {
  let out : Array[String] = []
  for line in js_probe_listener_log(id) {
    out.push(line)
  }
  out
}

///|
extern "js" fn js_probe_listener_log(id : Int32) -> FixedArray[String] =
  #|(id) => {
  #|  const logs = globalThis.__moon_element_listener_log;
  #|  const list = logs && logs[id];
  #|  return list ? list.slice() : [];
  #|}
