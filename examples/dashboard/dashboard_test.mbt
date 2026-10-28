///|
fn near(a : Double, b : Double) -> Bool {
  (a - b).abs() <= 0.02
}

///|
test "dashboard: the root is the requested width and the nav spans the content box" {
  let (_, box) = @pipeline.run(
    @dashboard.dashboard_view(),
    @dashboard.dashboard_css(),
    640.0,
    @pipeline.measure_monospace,
  )
  let page = @layout.LayoutBox::find(box, 0).unwrap()
  assert_true(near(page.w, 640.0))
  // 页面 padding 16，导航条是第 1 个节点
  let nav = @layout.LayoutBox::find(box, 1).unwrap()
  assert_true(near(nav.x, 16.0))
  assert_true(near(nav.w, 608.0))
}

///|
test "dashboard: three cards share a row and split the space evenly" {
  let (_, box) = @pipeline.run(
    @dashboard.dashboard_view(),
    @dashboard.dashboard_css(),
    640.0,
    @pipeline.measure_monospace,
  )
  // 每张卡片 7 个节点（卡片盒 + 3 组标题/数值/说明）
  let first = @layout.LayoutBox::find(box, 7).unwrap()
  let second = @layout.LayoutBox::find(box, 14).unwrap()
  let third = @layout.LayoutBox::find(box, 21).unwrap()
  let even = (608.0 - 24.0) / 3.0
  assert_true(near(first.w, even))
  assert_true(near(second.x, 16.0 + even + 12.0))
  assert_true(near(third.x, 16.0 + 2.0 * (even + 12.0)))
  // 同一行：三张卡的 y 相同
  assert_true(near(first.y, second.y))
  assert_true(near(second.y, third.y))
}

///|
test "dashboard: cards wrap when the page is narrow" {
  let (_, box) = @pipeline.run(
    @dashboard.dashboard_view(),
    @dashboard.dashboard_css(),
    300.0,
    @pipeline.measure_monospace,
  )
  let first = @layout.LayoutBox::find(box, 7).unwrap()
  let third = @layout.LayoutBox::find(box, 21).unwrap()
  // 换行后第三张卡不在第一行
  assert_true(third.y > first.y + 1.0)
}

///|
test "dashboard: layout is deterministic and its visit count is linear" {
  let (_, box1) = @pipeline.run(
    @dashboard.dashboard_view(),
    @dashboard.dashboard_css(),
    640.0,
    @pipeline.measure_monospace,
  )
  let visits = @layout.layout_visit_count()
  let (_, box2) = @pipeline.run(
    @dashboard.dashboard_view(),
    @dashboard.dashboard_css(),
    640.0,
    @pipeline.measure_monospace,
  )
  assert_eq(
    @svg.to_json(
      @pipeline.build(
        @dashboard.dashboard_view(),
        @style.Stylesheet::parse(@dashboard.dashboard_css()),
      ),
      box1,
    ),
    @svg.to_json(
      @pipeline.build(
        @dashboard.dashboard_view(),
        @style.Stylesheet::parse(@dashboard.dashboard_css()),
      ),
      box2,
    ),
  )
  let lines = @pipeline.nodes_of(@dashboard.dashboard_view()).length()
  assert_true(visits <= 4 * lines)
  assert_true(@layout.LayoutBox::count(box1) >= lines)
}

///|
test "dashboard: exports json and svg" {
  let (root, box) = @pipeline.run(
    @dashboard.dashboard_view(),
    @dashboard.dashboard_css(),
    640.0,
    @pipeline.measure_monospace,
  )
  let json = @svg.to_json(root, box)
  assert_true(json.contains("\"node\": 0"))
  assert_true(json.contains("\"rect\": ["))
  assert_true(json.contains("\"children\": ["))
  let svg = @svg.to_svg(root, box)
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("<rect"))
  assert_true(svg.contains("<text"))
  assert_true(svg.contains("</svg>"))
}
