///|
/// 自定义元素的生命周期状态。
///
/// 与 DOM 规范一致，连接状态本身是一个布尔量：元素被移出文档后回到 `Unconnected`，
/// 与「从未连接过」不可区分；痕迹靠计数器与反应日志保留。
pub(all) enum LifecycleState {
  Unconnected
  Connected
} derive(Eq, @debug.Debug)

///|
/// 显式声明以消除派生方法被隐式提升的废弃警告。
pub extend LifecycleState with Eq::{equal, not_equal}

///|
/// 显式声明以消除派生方法被隐式提升的废弃警告。
pub extend LifecycleState with @debug.Debug::{to_repr}

///|
/// 生命周期反应（对应规范中的 custom element reactions）。
///
/// 构造器前缀 `React` 是为了避免与 `LifecycleState` 的同名构造器混淆。
pub(all) enum Reaction {
  ReactConnected
  ReactDisconnected
  ReactAttributeChanged(String, String?, String?)
  ReactAdopted
} derive(@debug.Debug)

///|
/// 显式声明 `Debug` 的方法，消除隐式提升的废弃警告。
pub extend Reaction with @debug.Debug::{to_repr}

///|
/// 生命周期状态机 + 反应记录。
///
/// 这个结构**完全不碰 DOM**：适配层把浏览器的回调转成这里的调用。
/// 因此这些规则可以在每个后端上用普通单元测试验证，不需要浏览器。
pub struct Lifecycle {
  mut state : LifecycleState
  mut connect_count : Int32
  mut disconnect_count : Int32
  // 不需要 mut：push 修改的是数组内容，而不是这个字段本身
  reactions : Array[Reaction]
}

///|
pub fn Lifecycle::new() -> Lifecycle {
  { state: Unconnected, connect_count: 0, disconnect_count: 0, reactions: [], }
}

///|
/// 元素被插入文档。
///
/// 已经处于连接状态时不产生任何反应（与规范一致：「若元素已连接则什么都不做」），
/// 返回 `false` 表示本次没有产生反应。
pub fn Lifecycle::on_connect(self : Lifecycle) -> Bool {
  if self.state == Connected {
    false
  } else {
    self.state = Connected
    self.connect_count = self.connect_count + 1
    self.reactions.push(ReactConnected)
    true
  }
}

///|
/// 元素被移出文档。未连接时无反应，返回 `false`。
pub fn Lifecycle::on_disconnect(self : Lifecycle) -> Bool {
  if self.state == Unconnected {
    false
  } else {
    self.state = Unconnected
    self.disconnect_count = self.disconnect_count + 1
    self.reactions.push(ReactDisconnected)
    true
  }
}

///|
/// 属性发生变化。
///
/// 按规范，无论元素是否已连接都会记录这次变化；「是否属于被观察属性」由适配层
/// 依据 `observed_attributes` 过滤，本结构不做过滤以便完整留痕。
pub fn Lifecycle::on_attribute_changed(
  self : Lifecycle,
  attr_name : String,
  old_value : String?,
  new_value : String?,
) -> Unit {
  self.reactions.push(ReactAttributeChanged(attr_name, old_value, new_value))
}

///|
/// 元素被移动到另一个文档（`adoptedCallback`）。
pub fn Lifecycle::on_adopted(self : Lifecycle) -> Unit {
  self.reactions.push(ReactAdopted)
}

///|
pub fn Lifecycle::is_connected(self : Lifecycle) -> Bool {
  self.state == Connected
}

///|
pub fn Lifecycle::state(self : Lifecycle) -> LifecycleState {
  self.state
}

///|
pub fn Lifecycle::connect_count(self : Lifecycle) -> Int32 {
  self.connect_count
}

///|
pub fn Lifecycle::disconnect_count(self : Lifecycle) -> Int32 {
  self.disconnect_count
}

///|
pub fn Lifecycle::reaction_count(self : Lifecycle) -> Int32 {
  self.reactions.length()
}

///|
/// 把反应序列转成稳定的字符串序列，便于断言与快照：
///
/// ```text
/// connected
/// disconnected
/// attribute:max-count:1->2
/// attribute:max-count:<none>->2     // 属性被新增时旧值为 none
/// adopted
/// ```
pub fn Lifecycle::reaction_log(self : Lifecycle) -> Array[String] {
  let out : Array[String] = []
  for r in self.reactions {
    out.push(reaction_to_string(r))
  }
  out
}

///|
fn reaction_to_string(r : Reaction) -> String {
  match r {
    ReactConnected => "connected"
    ReactDisconnected => "disconnected"
    ReactAdopted => "adopted"
    ReactAttributeChanged(name, old_value, new_value) => {
      let o = match old_value {
        Some(v) => v
        None => "<none>"
      }
      let n = match new_value {
        Some(v) => v
        None => "<none>"
      }
      "attribute:\{name}:\{o}->\{n}"
    }
  }
}
