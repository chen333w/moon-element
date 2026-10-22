///|
/// 事件派发：把 `core` 的事件描述落到浏览器的 `CustomEvent` 上。
///
/// 与属性反射一样，规则在 `core`（事件名校验、注册表、bubbles/composed 语义），
/// 这里只负责接线与日志。

///|
/// 派发一个自定义事件。
///
/// - 事件名在本实例的事件注册表里时，按声明的 `bubbles` / `composed` 派发
/// - 未声明的事件名仍可派发，用保守默认值（不冒泡、不穿 shadow 边界），
///   漏声明不会让事件意外穿透出去
/// - 返回 `true` 表示有监听者调用了 `preventDefault()`
/// - 实例 id 无效时返回 `false`，不抛错
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
/// 派发过的事件日志，用于诊断与测试。
pub fn instance_event_log(id : Int32) -> Array[String] {
  match instance_get(id) {
    Some(inst) => inst.event_log
    None => []
  }
}

///|
/// 本实例声明的事件名，用于诊断与测试。
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
  #|  // dispatchEvent 返回 false 表示有监听者调用了 preventDefault
  #|  const notCanceled = el.dispatchEvent(ev);
  #|  return !notCanceled;
  #|}

// ---------------------------------------------------------------------------
// 测试探针：无浏览器环境下模拟监听者
// ---------------------------------------------------------------------------

///|
/// 探针：给实例加一个记录型监听者（把事件名、detail、bubbles、composed 记下来）。
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
/// 探针：给实例加一个会 `preventDefault()` 的监听者。
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
/// 探针：读取记录型监听者收到的事件列表。
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
