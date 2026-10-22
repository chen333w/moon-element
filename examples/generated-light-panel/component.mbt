// 由 moon-element CLI 生成的自定义元素骨架：x-light-panel（渲染模式：light）
//
// 使用方式：
// 1) 在本包的 moon.pkg 里声明依赖（import 属于包配置，不能写进 .mbt）：
//      import {
//        "chen333w/moon-element/core" @core,
//        "chen333w/moon-element/dom" @dom,
//      }
// 2) 把本文件放进包里，并在入口处调用 register_x_light_panel()
// 3) 产物是标准自定义元素：宿主页面里写 <x-light-panel> 即可
//    light 模式：不建 shadow root，内容渲染进元素自身；
//    下面的 CSS 会被 core.scope_css 作用域到 `x-light-panel`，不会污染整页

///|
const X_LIGHT_PANEL_CSS : String =
  #|:host { display: block; }
  #|.label { color: #3b4453; }

///|
fn render_x_light_panel(props : @core.Props) -> @core.View {
  let label = props.get_string("label").unwrap_or("")
  @core.View::element("span", [("class", "label")], [@core.View::text(label)])
}

///|
pub fn register_x_light_panel() -> Unit {
  @dom.define_component(
    "x-light-panel",
    [@core.AttrSpec::string("label", "")],
    render_x_light_panel,
    styles=X_LIGHT_PANEL_CSS,
    mode=@core.LightDom,
    events=[
      // 需要让宿主页面收到的事件，用 crossing（bubbles + composed）
      @core.EventSpec::crossing("x-light-panel-changed"),
    ],
  )
}
