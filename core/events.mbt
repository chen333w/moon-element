///|
/// 组件对外派发的事件描述。
///
/// 三个字段直接对应 `CustomEvent` 的初始化项：
/// - `bubbles`：是否冒泡到祖先
/// - `composed`：是否能穿过 shadow 边界——**这条最容易被忘**。
///   为了让宿主页面的监听者能收到组件内部抛出的事件，跨 shadow 边界的事件
///   必须 `composed = true`，否则事件会在 shadow root 处被挡住。
pub struct EventSpec {
  name : String
  bubbles : Bool
  composed : Bool
}

///|
pub fn EventSpec::new(
  name : String,
  bubbles : Bool,
  composed : Bool,
) -> EventSpec {
  { name, bubbles, composed, }
}

///|
/// 组件内部使用、需要穿过 shadow 边界到宿主页面的事件（bubbles + composed 都为 true）。
pub fn EventSpec::crossing(name : String) -> EventSpec {
  { name, bubbles: true, composed: true, }
}

///|
/// 只在组件内部使用的事件（不冒泡、不穿 shadow 边界）。
/// 命名用 `contained` 而不是 `local`：`local` 是 MoonBit 保留字。
pub fn EventSpec::contained(name : String) -> EventSpec {
  { name, bubbles: false, composed: false, }
}

///|
pub fn EventSpec::name(self : EventSpec) -> String {
  self.name
}

///|
pub fn EventSpec::bubbles(self : EventSpec) -> Bool {
  self.bubbles
}

///|
pub fn EventSpec::composed(self : EventSpec) -> Bool {
  self.composed
}

///|
/// 事件名是否合法：非空、且不含 ASCII 空白（把 `"count change"` 这种
/// 带空格的名字当成事件名是常见笔误，dispatch 出去永远没人收到）。
pub fn is_valid_event_name(name : String) -> Bool {
  let n = name.char_length()
  if n == 0 {
    return false
  }
  let mut i = 0
  while i < n {
    match name.get_char(i) {
      Some(c) => {
        let v = c.to_int()
        // 空格、制表、换行、回车
        if v == 32 || v == 9 || v == 10 || v == 13 {
          return false
        }
      }
      None => ()
    }
    i = i + 1
  }
  true
}

///|
/// 一个组件声明的事件集合。
///
/// 它的用途不是"省事"，而是**在派发前就能发现错误**：重名、非法名在注册阶段
/// 就被挡住，而不是等到线上发现某个事件永远收不到。
pub struct EventRegistry {
  specs : Array[EventSpec]
}

///|
pub fn EventRegistry::new() -> EventRegistry {
  { specs: [], }
}

///|
/// 注册一个事件。返回 `false` 表示被拒绝：名字非法，或与已注册的重名。
pub fn EventRegistry::add(self : EventRegistry, spec : EventSpec) -> Bool {
  if !is_valid_event_name(spec.name()) {
    return false
  }
  match self.find(spec.name()) {
    Some(_) => false
    None => {
      self.specs.push(spec)
      true
    }
  }
}

///|
pub fn EventRegistry::find(self : EventRegistry, name : String) -> EventSpec? {
  for spec in self.specs {
    if spec.name() == name {
      return Some(spec)
    }
  }
  None
}

///|
pub fn EventRegistry::names(self : EventRegistry) -> Array[String] {
  let out : Array[String] = []
  for spec in self.specs {
    out.push(spec.name())
  }
  out
}

///|
pub fn EventRegistry::length(self : EventRegistry) -> Int32 {
  self.specs.length()
}
