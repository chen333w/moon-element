///|
/// CSS 作用域化的黑盒测试：用内联快照钉住改写结果。
/// 刷新快照：`moon test --update`。

///|
test "scope_css: 普通规则加后代前缀" {
  inspect(
    @core.scope_css("p { color: red }", ".x"),
    content=".x p { color: red }",
  )
}

///|
test "scope_css: 逗号分隔的选择器逐个处理" {
  inspect(
    @core.scope_css("p, a { color: red }", ".x"),
    content=".x p, .x a { color: red }",
  )
}

///|
test "scope_css: 括号内的逗号不是分隔符" {
  inspect(
    @core.scope_css("a:is(b, c) p { color: red }", ".x"),
    content=".x a:is(b, c) p { color: red }",
  )
}

///|
test "scope_css: :host 被替换为 scope" {
  inspect(
    @core.scope_css(":host { display: block }", "my-el"),
    content="my-el { display: block }",
  )
  inspect(
    @core.scope_css(":host(.active) { color: red }", "my-el"),
    content="my-el.active { color: red }",
  )
  inspect(
    @core.scope_css(":host .child { color: red }", "my-el"),
    content="my-el .child { color: red }",
  )
}

///|
test "scope_css: @media 内部递归处理" {
  inspect(
    @core.scope_css("@media (min-width: 600px) { p { color: red } }", ".x"),
    content="@media (min-width: 600px) { .x p { color: red } }",
  )
}

///|
test "scope_css: @keyframes 原样保留（帧选择器不能加前缀）" {
  inspect(
    @core.scope_css(
      "@keyframes spin { from { opacity: 0 } to { opacity: 1 } }", ".x",
    ),
    content="@keyframes spin { from { opacity: 0 } to { opacity: 1 } }",
  )
}

///|
test "scope_css: 注释保留" {
  inspect(
    @core.scope_css("/* 说明 */ p { color: red }", ".x"),
    content="/* 说明 */ .x p { color: red }",
  )
}

///|
test "scope_css: 选择器空白被归一化" {
  inspect(
    @core.scope_css("p   >   a { color: red }", ".x"),
    content=".x p > a { color: red }",
  )
  inspect(
    @core.scope_css("  p  {  color : red  }  ", ".x"),
    content="  .x p {  color : red  }  ",
  )
}

///|
test "scope_css: 多条规则与 at-statement" {
  inspect(
    @core.scope_css("p { a: b } a { c: d }", ".x"),
    content=".x p { a: b } .x a { c: d }",
  )
  inspect(
    @core.scope_css("@import url(x.css); p { a: b }", ".x"),
    content="@import url(x.css); .x p { a: b }",
  )
}

///|
test "scope_css: 空 scope 是恒等操作，空输入返回空" {
  inspect(@core.scope_css("p { color: red }", ""), content="p { color: red }")
  inspect(@core.scope_css("", ".x"), content="")
}
