///|
/// demo 用的四个组件：属性反射（含非法值回退）、shadow DOM 样式隔离、
/// HTML 转义、组件对外派发事件。
///
/// 数据流单向：页面改属性 → 组件重渲染 → 组件抛事件 → 页面收到。
/// 组件内部不挂 DOM 监听器（渲染用 innerHTML 替换，内部监听器会随重渲染丢失），
/// 交互按钮因此放在页面（light DOM）里。

///|
const COUNTER_CSS : String =
  #|  :host { display: inline-block; }
  #|  .wrap { font: 14px/1.4 system-ui, sans-serif; border: 1px solid #d5dbe3;
  #|          border-radius: 10px; padding: 12px 14px; min-width: 160px; background: #fff; }
  #|  .label { color: #5b6472; font-size: 12px; letter-spacing: .04em; }
  #|  .num { font-size: 30px; font-weight: 650; color: #1f6feb; margin: 2px 0 8px; }
  #|  .bar { height: 6px; border-radius: 3px; background: #eaeef3; overflow: hidden; }
  #|  .bar > i { display: block; height: 100%; background: #1f6feb; }

///|
fn counter_view(props : @core.Props) -> @core.View {
  let count = props.get_int("count").unwrap_or(0)
  let max = props.get_int("max").unwrap_or(10)
  let label = props.get_string("label").unwrap_or("计数")
  // max 为 0 或负数时不做除法，避免除零
  let pct = if max > 0 {
    let raw = count * 100 / max
    if raw < 0 {
      0
    } else if raw > 100 {
      100
    } else {
      raw
    }
  } else {
    0
  }
  @core.View::fragment([
    @core.View::element("div", [("class", "wrap")], [
      @core.View::element("div", [("class", "label")], [@core.View::text(label)]),
      @core.View::element("div", [("class", "num")], [
        @core.View::text(count.to_string()),
      ]),
      @core.View::element("div", [("class", "bar")], [
        @core.View::element("i", [("style", "width:\{pct}%")], []),
      ]),
    ]),
  ])
}

///|
const BADGE_CSS : String =
  #|  :host { display: inline-block; }
  #|  .pill { display: inline-block; font: 13px/1 system-ui, sans-serif;
  #|          padding: 6px 10px; border-radius: 999px; border: 1px solid transparent; }
  #|  .info { background: #e8f1ff; color: #12457f; border-color: #bcd6fb; }
  #|  .warn { background: #fff3e0; color: #8a4b00; border-color: #ffd8a8; }
  #|  .danger { background: #ffe9e9; color: #8f1d1d; border-color: #ffc9c9; }
  #|  .plain { background: #f2f4f7; color: #3b4453; border-color: #dde2e9; }

///|
fn tone_class(tone : String) -> String {
  if tone == "warn" || tone == "danger" || tone == "info" {
    tone
  } else {
    "plain"
  }
}

///|
fn badge_view(props : @core.Props) -> @core.View {
  let label = props.get_string("label").unwrap_or("?")
  let tone = props.get_string("tone").unwrap_or("info")
  @core.View::fragment([
    @core.View::element("span", [("class", "pill \{tone_class(tone)}")], [
      // label 走 VText，会被转义——页面传 <b>hi</b> 时看到的是字面文本
      @core.View::text(label),
    ]),
  ])
}

///|
const CARD_CSS : String =
  #|  :host { display: block; }
  #|  .card { font: 14px/1.6 system-ui, sans-serif; border: 1px solid #d5dbe3;
  #|          border-radius: 12px; overflow: hidden; background: #fff; }
  #|  .hd { padding: 10px 14px; font-weight: 600; background: #f7f9fc; }
  #|  .hd.warn { background: #fff8ec; color: #8a4b00; }
  #|  .bd { padding: 12px 14px; color: #3b4453; }

///|
fn card_view(props : @core.Props) -> @core.View {
  let title = props.get_string("title").unwrap_or("无标题")
  let body = props.get_string("body").unwrap_or("")
  let tone = props.get_string("tone").unwrap_or("info")
  @core.View::fragment([
    @core.View::element("div", [("class", "card")], [
      @core.View::element("div", [("class", "hd \{tone}")], [
        @core.View::text(title),
      ]),
      @core.View::element("div", [("class", "bd")], [@core.View::text(body)]),
    ]),
  ])
}

///|
/// light DOM 组件的样式直接写在 `:host` 上：适配层会用 `core.scope_css`
/// 把它改写成 `x-panel ...`，避免污染整页。
const PANEL_CSS : String =
  #|:host { display: block; margin-top: 8px; }
  #|.panel-title { font-weight: 600; color: #12457f; }
  #|.panel-body { color: #3b4453; }
  #|/* 与页面里的 .pill 同名；background 与 color 都要自己定，
  #|   否则页面的 color:#fff 会透入，变成浅底白字 */
  #|.pill { background: #eef2f7; color: #3b4453; }

///|
fn panel_view(props : @core.Props) -> @core.View {
  let title = props.get_string("title").unwrap_or("面板")
  let body = props.get_string("body").unwrap_or("")
  @core.View::element("div", [("class", "panel")], [
    @core.View::element("div", [("class", "panel-title")], [
      @core.View::text(title),
    ]),
    @core.View::element("div", [("class", "panel-body")], [
      @core.View::text(body),
    ]),
    @core.View::element("span", [("class", "pill")], [
      @core.View::text("light DOM 里的 .pill"),
    ]),
  ])
}

///|
/// 注册四个组件。
/// `on_change` 里派发对外事件，调用方不需要知道实例 id。
pub fn register_demo() -> Unit {
  @dom.define_component(
    "x-counter",
    [
      @core.AttrSpec::int("count", 0),
      @core.AttrSpec::int("max", 10),
      @core.AttrSpec::string("label", "计数"),
    ],
    counter_view,
    styles=COUNTER_CSS,
    events=[@core.EventSpec::crossing("count-changed")],
    on_change=fn(id, _name) {
      let _ = @dom.dispatch(id, "count-changed", "", false)
    },
  )
  @dom.define_component(
    "x-badge",
    [
      @core.AttrSpec::string("label", "?"),
      @core.AttrSpec::string("tone", "info"),
    ],
    badge_view,
    styles=BADGE_CSS,
    events=[@core.EventSpec::crossing("badge-changed")],
    on_change=fn(id, _name) {
      let _ = @dom.dispatch(id, "badge-changed", "", false)
    },
  )
  @dom.define_component(
    "x-card",
    [
      @core.AttrSpec::string("title", "无标题"),
      @core.AttrSpec::string("body", ""),
      @core.AttrSpec::string("tone", "info"),
    ],
    card_view,
    styles=CARD_CSS,
  )
  // light DOM 模式：用 core.scope_css 把样式作用域到标签名
  @dom.define_component(
    "x-panel",
    [
      @core.AttrSpec::string("title", "面板"),
      @core.AttrSpec::string("body", ""),
    ],
    panel_view,
    styles=PANEL_CSS,
    mode=@core.LightDom,
  )
}

///|
fn main {
  register_demo()
  // 打印一行确认，便于排查模块是否加载
  println(
    "[moon-element] demo 组件已注册：x-counter / x-badge / x-card / x-panel（light DOM）",
  )
}
