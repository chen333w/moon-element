///|
/// 组件的渲染模式。
///
/// 放在 `core` 而不是 `dom`：它属于**组件模型**——core 决定「渲染成什么、
/// 样式怎么处理」，dom 只决定「写到哪里」。CLI 与配置也因此能直接用它做参数类型。
///
/// - `ShadowDom`（默认）：渲染进 shadow root，样式天然隔离，`:host` 直接可用
/// - `LightDom`：渲染进元素自身（不建 shadow root）。组件 CSS 会先用
///   `scope_css` 作用域到标签名，避免污染整页
pub(all) enum RenderMode {
  ShadowDom
  LightDom
} derive(Eq, @debug.Debug)

///|
/// `derive` 生成的方法默认会被隐式提升为普通方法（已废弃行为），显式声明以消除警告。
pub extend RenderMode with Eq::{equal, not_equal}

///|
pub extend RenderMode with @debug.Debug::{to_repr}

///|
/// 解析模式名（CLI / 配置用）。
///
/// 只接受 `"shadow"` 与 `"light"`，其他一律返回 `None`：不做模糊匹配，
/// 免得把拼错的值静默当成默认值——这类错误很难在事后发现。
pub fn RenderMode::parse(s : String) -> RenderMode? {
  if s == "shadow" {
    Some(ShadowDom)
  } else if s == "light" {
    Some(LightDom)
  } else {
    None
  }
}

///|
pub fn RenderMode::name(self : RenderMode) -> String {
  match self {
    ShadowDom => "shadow"
    LightDom => "light"
  }
}
