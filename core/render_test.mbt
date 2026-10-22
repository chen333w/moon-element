///|
/// Black-box tests for rendering, pinning the output with inline snapshots.
/// Refresh snapshots: `moon test --update`.

///|
test "render: text is escaped" {
  inspect(@core.escape_text("a&b"), content="a&amp;b")
  inspect(@core.escape_text("<b>"), content="&lt;b&gt;")
  inspect(
    @core.render(@core.View::text("<b>&\"'")),
    content="&lt;b&gt;&amp;&quot;&#39;",
  )
}

///|
test "render: raw is not escaped (the caller owns safety)" {
  inspect(@core.render(@core.View::raw("<b>hi</b>")), content="<b>hi</b>")
}

///|
test "render: elements, attributes, and children" {
  inspect(
    @core.render(
      @core.View::element("div", [("class", "a")], [@core.View::text("hi")]),
    ),
    content="<div class=\"a\">hi</div>",
  )
}

///|
test "render: attribute values are escaped too" {
  inspect(
    @core.render(@core.View::element("a", [("title", "a\"b&c")], [])),
    content="<a title=\"a&quot;b&amp;c\"></a>",
  )
}

///|
test "render: attribute order is preserved, no reordering or deduplication" {
  inspect(
    @core.render(@core.View::element("x", [("b", "1"), ("a", "2")], [])),
    content="<x b=\"1\" a=\"2\"></x>",
  )
}

///|
test "render: void elements have no closing tag and render no children" {
  inspect(@core.render(@core.View::element("br", [], [])), content="<br>")
  inspect(@core.render(@core.View::element("hr", [], [])), content="<hr>")
  inspect(
    @core.render(
      @core.View::element("img", [("src", "x.png")], [
        @core.View::text("ignored"),
      ]),
    ),
    content="<img src=\"x.png\">",
  )
}

///|
test "render: fragments and the empty view" {
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
test "render: nested structures" {
  let items : Array[@core.View] = [
    @core.View::element("li", [], [@core.View::text("1")]),
    @core.View::element("li", [], [@core.View::text("2")]),
  ]
  inspect(
    @core.render(@core.View::element("ul", [], items)),
    content="<ul><li>1</li><li>2</li></ul>",
  )
}
