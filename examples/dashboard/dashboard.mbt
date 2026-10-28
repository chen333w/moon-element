// 一个真实页面级的离屏布局用例：导航条 + 三张指标卡片 + 状态栏。
// 它同时是 CLI 输入和几何基线测试的对象。

///|
const DASHBOARD_CSS : String =
  #|.page { display: flex; flex-direction: column; padding: 16px; gap: 12px;
  #|        background: #f5f7fa; }
  #|.nav { display: flex; flex-direction: row; justify-content: space-between; align-items: center;
  #|       padding: 12px; background: #ffffff; }
  #|.cards { display: flex; flex-direction: row; flex-wrap: wrap; gap: 12px; }
  #|.card { display: flex; flex-direction: column; flex: 1 1 160px; padding: 12px;
  #|        gap: 4px; background: #ffffff; }
  #|.title { font-size: 12px; color: #5b6472; }
  #|.num { font-size: 28px; color: #1f6feb; }
  #|.note { font-size: 12px; color: #8a94a6; }
  #|.footer { display: flex; flex-direction: row; justify-content: space-between;
  #|          padding: 8px; font-size: 12px; color: #5b6472; }

///|
pub fn dashboard_css() -> String {
  DASHBOARD_CSS
}

///|
fn card(title : String, num : String, note : String) -> @core.View {
  @core.View::element("div", [("class", "card")], [
    @core.View::element("div", [("class", "title")], [@core.View::text(title)]),
    @core.View::element("div", [("class", "num")], [@core.View::text(num)]),
    @core.View::element("div", [("class", "note")], [@core.View::text(note)]),
  ])
}

///|
pub fn dashboard_view() -> @core.View {
  @core.View::element("div", [("class", "page")], [
    @core.View::element("div", [("class", "nav")], [
      @core.View::element("span", [("class", "title")], [
        @core.View::text("Moon Dashboard"),
      ]),
      @core.View::element("span", [("class", "note")], [
        @core.View::text("last 24h"),
      ]),
    ]),
    @core.View::element("div", [("class", "cards")], [
      card("Tasks", "128", "queued"),
      card("Latency", "42ms", "p95"),
      card("Errors", "0.4%", "1h"),
    ]),
    @core.View::element("div", [("class", "footer")], [
      @core.View::element("span", [], [@core.View::text("moon-element")]),
      @core.View::element("span", [], [@core.View::text("offscreen layout")]),
    ]),
  ])
}
