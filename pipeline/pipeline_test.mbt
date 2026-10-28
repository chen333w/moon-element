// 适配层的黑盒测试：节点表、样式树、根盒宽度。

///|
fn sample_view() -> @core.View {
  @core.View::element("div", [("class", "box wide"), ("id", "root")], [
    @core.View::element("span", [("class", "a")], [@core.View::text("hi")]),
    @core.View::text("yo"),
  ])
}

///|
test "nodes_of flattens in preorder and splits attributes" {
  let nodes = @pipeline.nodes_of(sample_view())
  assert_eq(nodes.length(), 4)
  assert_eq(nodes[0].tag, "div")
  assert_eq(nodes[0].id, "root")
  assert_eq(nodes[0].classes, ["box", "wide"])
  assert_eq(nodes[0].parent, -1)
  assert_eq(nodes[1].tag, "span")
  assert_eq(nodes[1].parent, 0)
  assert_eq(nodes[2].tag, "#text")
  assert_eq(nodes[2].parent, 1)
  assert_eq(nodes[3].tag, "#text")
  assert_eq(nodes[3].parent, 0)
}

///|
test "nodes_of splits the style attribute into declaration pairs" {
  let view = @core.View::element(
    "div",
    [("style", "color: red; padding: 4px")],
    [],
  )
  let nodes = @pipeline.nodes_of(view)
  assert_eq(nodes[0].inline.length(), 2)
  assert_eq(nodes[0].inline[0].0, "color")
  assert_eq(nodes[0].inline[0].1, "red")
  assert_eq(nodes[0].inline[1].0, "padding")
}

///|
test "fragments and empty views do not take a node index" {
  let view = @core.View::fragment([
    @core.View::nothing(),
    @core.View::element("p", [], [@core.View::text("a")]),
  ])
  let nodes = @pipeline.nodes_of(view)
  assert_eq(nodes.length(), 2)
  assert_eq(nodes[0].tag, "p")
  assert_eq(nodes[0].parent, -1)
  assert_eq(nodes[1].tag, "#text")
  assert_eq(nodes[1].parent, 0)
}

///|
test "build attaches computed styles and keeps text nodes" {
  let sheet = @style.Stylesheet::parse(".box { padding: 8px; }")
  let root = @pipeline.build(sample_view(), sheet)
  assert_eq(root.info.tag, "div")
  assert_eq(root.style.padding.top, 8.0)
  assert_eq(root.children.length(), 2)
  assert_eq(root.children[0].info.tag, "span")
  assert_eq(root.children[0].children[0].text, Some("hi"))
  assert_eq(root.children[1].text, Some("yo"))
}

///|
test "text nodes inherit font size and color from the parent" {
  let sheet = @style.Stylesheet::parse(".box { font-size: 20px; color: red; }")
  let root = @pipeline.build(sample_view(), sheet)
  assert_eq(root.children[0].children[0].style.font_size, 20.0)
  let inherited = root.children[0].children[0].style.color
  assert_eq(inherited.r, root.style.color.r)
  assert_eq(inherited.g, root.style.color.g)
  assert_eq(inherited.a, root.style.color.a)
}

///|
test "run lays the view out at the requested width" {
  let view = @core.View::element("div", [("class", "box")], [
    @core.View::text("hi"),
  ])
  let (_, box) = @pipeline.run(
    view, ".box { display: block; }", 320.0, @pipeline.measure_monospace,
  )
  match box {
    @layout.LayoutBox::Box(b) => assert_eq(b.rect.w, 320.0)
    @layout.LayoutBox::Text(_) => assert_true(false)
  }
}

///|
test "measure_monospace uses 0.6em per character and 1.2em lines" {
  let (w, h) = @pipeline.measure_monospace("abc", 10.0)
  assert_eq(w, 18.0)
  assert_eq(h, 12.0)
}

///|
test "an empty fragment and a nothing view produce no nodes" {
  assert_eq(@pipeline.nodes_of(@core.View::fragment([])).length(), 0)
  assert_eq(@pipeline.nodes_of(@core.View::nothing()).length(), 0)
}

///|
test "nested fragments keep preorder indices and parents" {
  let view = @core.View::fragment([
    @core.View::element("div", [], [
      @core.View::fragment([
        @core.View::element("b", [], [@core.View::text("x")]),
        @core.View::text("y"),
      ]),
    ]),
  ])
  let nodes = @pipeline.nodes_of(view)
  assert_eq(nodes.length(), 4)
  assert_eq(nodes[0].tag, "div")
  assert_eq(nodes[0].parent, -1)
  assert_eq(nodes[1].tag, "b")
  assert_eq(nodes[1].parent, 0)
  assert_eq(nodes[2].tag, "#text")
  assert_eq(nodes[2].parent, 1)
  assert_eq(nodes[3].tag, "#text")
  assert_eq(nodes[3].parent, 0)
}

///|
test "an empty string text node still takes an index" {
  let view = @core.View::element("p", [], [@core.View::text("")])
  assert_eq(@pipeline.nodes_of(view).length(), 2)
  let root = @pipeline.build(view, @style.Stylesheet::parse(""))
  assert_eq(root.children.length(), 1)
  assert_eq(root.children[0].text, Some(""))
}

///|
test "a 400 character run keeps its measured width" {
  let mut long = ""
  for _ in 0..<400 {
    long = long + "a"
  }
  let (w, h) = @pipeline.measure_monospace(long, 10.0)
  assert_eq(w, 2400.0)
  assert_eq(h, 12.0)
  let view = @core.View::element("p", [], [@core.View::text(long)])
  let root = @pipeline.build(
    view,
    @style.Stylesheet::parse("p { display: block; }"),
  )
  assert_eq(root.children[0].text, Some(long))
}

///|
test "the pipeline is deterministic for the same input" {
  let view = sample_view()
  let (_, first) = @pipeline.run(
    view, ".box { padding: 8px; }", 320.0, @pipeline.measure_monospace,
  )
  let (_, second) = @pipeline.run(
    view, ".box { padding: 8px; }", 320.0, @pipeline.measure_monospace,
  )
  assert_eq(first.count(), second.count())
  match first.find(0) {
    Some(a) =>
      match second.find(0) {
        Some(b) => {
          assert_eq(a.x, b.x)
          assert_eq(a.y, b.y)
          assert_eq(a.w, b.w)
          assert_eq(a.h, b.h)
        }
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}
