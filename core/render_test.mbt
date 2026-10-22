///|
/// 渲染的黑盒测试。
///
/// 用内联快照（`inspect(..., content=...)`）钉住输出：渲染输出必须是确定性的。
/// 刷新快照：`moon test --update`。

///|
test "render: 文本被转义" {
  inspect(@core.escape_text("a&b"), content="a&amp;b")
  inspect(@core.escape_text("<b>"), content="&lt;b&gt;")
  inspect(
    @core.render(@core.View::text("<b>&\"'")),
    content="&lt;b&gt;&amp;&quot;&#39;",
  )
}

///|
test "render: raw 不转义（调用方负责安全）" {
  inspect(@core.render(@core.View::raw("<b>hi</b>")), content="<b>hi</b>")
}

///|
test "render: 元素、属性与子节点" {
  inspect(
    @core.render(
      @core.View::element("div", [("class", "a")], [@core.View::text("hi")]),
    ),
    content="<div class=\"a\">hi</div>",
  )
}

///|
test "render: 属性值也会被转义" {
  inspect(
    @core.render(@core.View::element("a", [("title", "a\"b&c")], [])),
    content="<a title=\"a&quot;b&amp;c\"></a>",
  )
}

///|
test "render: 属性顺序原样保留，不做重排或去重" {
  inspect(
    @core.render(@core.View::element("x", [("b", "1"), ("a", "2")], [])),
    content="<x b=\"1\" a=\"2\"></x>",
  )
}

///|
test "render: void 元素没有闭合标签，且不渲染子节点" {
  inspect(@core.render(@core.View::element("br", [], [])), content="<br>")
  inspect(@core.render(@core.View::element("hr", [], [])), content="<hr>")
  inspect(
    @core.render(
      @core.View::element("img", [("src", "x.png")], [
        @core.View::text("会被忽略"),
      ]),
    ),
    content="<img src=\"x.png\">",
  )
}

///|
test "render: 片段与空视图" {
  inspect(
    @core.render(
      @core.View::fragment([
        @core.View::text("a"),
        @core.View::nothing(),
        @core.View::text("b"),
      ]),
    ),
    content="ab",
  )
  inspect(@core.render(@core.View::nothing()), content="")
}

///|
test "render: 嵌套结构" {
  let items : Array[@core.View] = [
    @core.View::element("li", [], [@core.View::text("1")]),
    @core.View::element("li", [], [@core.View::text("2")]),
  ]
  inspect(
    @core.render(@core.View::element("ul", [], items)),
    content="<ul><li>1</li><li>2</li></ul>",
  )
}
