///|
/// The demo's four components: attribute reflection with fallback, shadow DOM isolation,
/// HTML escaping, and events dispatched to the page. x-counter also handles its own +/-
/// buttons through `on_action` + `data-act`, so a click survives re-rendering.

///|
const COUNTER_CSS : String =
  #|  :host { display: inline-block; }
  #|  .wrap { font: 14px/1.4 system-ui, sans-serif; border: 1px solid #d5dbe3;
  #|          border-radius: 10px; padding: 12px 14px; min-width: 160px; background: #fff; }
  #|  .label { color: #5b6472; font-size: 12px; letter-spacing: .04em; }
  #|  .num { font-size: 30px; font-weight: 650; color: #1f6feb; margin: 2px 0 8px; }
  #|  .bar { height: 6px; border-radius: 3px; background: #eaeef3; overflow: hidden; }
  #|  .bar > i { display: block; height: 100%; background: #1f6feb; }
  #|  .acts { display: flex; gap: 6px; margin-top: 10px; }
  #|  .acts button { font: inherit; padding: 4px 10px; border: 1px solid #cfd8e3;
  #|                 border-radius: 8px; background: #fff; cursor: pointer; }

///|
fn counter_view(props : @core.Props) -> @core.View {
  let count = props.get_int("count").unwrap_or(0)
  let max = props.get_int("max").unwrap_or(10)
  let label = props.get_string("label").unwrap_or("Count")
  // No division when max is zero or negative.
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
      @core.View::element("div", [("class", "acts")], [
        @core.View::element("button", [("data-act", "dec")], [
          @core.View::text("-"),
        ]),
        @core.View::element("button", [("data-act", "inc")], [
          @core.View::text("+"),
        ]),
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
      // Text views are escaped: <b>hi</b> passed from the page renders literally.
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
  let title = props.get_string("title").unwrap_or("Untitled")
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
/// Styles are written against `:host`; the adapter rewrites them with `core.scope_css`
/// to `x-panel ...`, so they cannot leak into the page.
const PANEL_CSS : String =
  #|:host { display: block; margin-top: 8px; }
  #|.panel-title { font-weight: 600; color: #12457f; }
  #|.panel-body { color: #3b4453; }
  #|/* Same class name as the page's .pill. Set both background and color here,
  #|   otherwise the page's color:#fff bleeds in and the text goes white on a light background. */
  #|.pill { background: #eef2f7; color: #3b4453; }

///|
fn panel_view(props : @core.Props) -> @core.View {
  let title = props.get_string("title").unwrap_or("Panel")
  let body = props.get_string("body").unwrap_or("")
  @core.View::element("div", [("class", "panel")], [
    @core.View::element("div", [("class", "panel-title")], [
      @core.View::text(title),
    ]),
    @core.View::element("div", [("class", "panel-body")], [
      @core.View::text(body),
    ]),
    @core.View::element("span", [("class", "pill")], [
      @core.View::text("the .pill inside light DOM"),
    ]),
  ])
}

///|
/// 内部按钮用：读当前属性、夹在 0..max，再写回属性管线触发重渲染。
fn step_count(id : Int32, delta : Int32) -> Unit {
  let count = @dom.instance_prop_int(id, "count").unwrap_or(0)
  let max = @dom.instance_prop_int(id, "max").unwrap_or(10)
  let next = count + delta
  let clamped = if next < 0 { 0 } else if next > max { max } else { next }
  @dom.set_attribute(id, "count", clamped.to_string())
}

///|
/// Registers the four demo components.
pub fn register_demo() -> Unit {
  @dom.define_component(
    "x-counter",
    [
      @core.AttrSpec::int("count", 0),
      @core.AttrSpec::int("max", 10),
      @core.AttrSpec::string("label", "Count"),
    ],
    counter_view,
    styles=COUNTER_CSS,
    events=[@core.EventSpec::crossing("count-changed")],
    on_change=fn(id, _name) {
      let _ = @dom.dispatch(id, "count-changed", "", false)
    },
    on_action=[
      (
        @core.ActionSpec::new("click", "inc"),
        fn(id, _action) { step_count(id, 1) },
      ),
      (
        @core.ActionSpec::new("click", "dec"),
        fn(id, _action) { step_count(id, -1) },
      ),
    ],
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
      @core.AttrSpec::string("title", "Untitled"),
      @core.AttrSpec::string("body", ""),
      @core.AttrSpec::string("tone", "info"),
    ],
    card_view,
    styles=CARD_CSS,
  )
  @dom.define_component(
    "x-panel",
    [
      @core.AttrSpec::string("title", "Panel"),
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
  println(
    "[moon-element] demo components registered: x-counter / x-badge / x-card / x-panel (light DOM)",
  )
}
