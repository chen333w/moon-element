///|
/// Black-box tests for CSS scoping, pinning the rewrite with inline snapshots.
/// Refresh snapshots: `moon test --update`.

///|
test "scope_css: a plain rule gets a descendant prefix" {
  inspect(
    @core.scope_css("p { color: red }", ".x"),
    content=".x p { color: red }",
  )
}

///|
test "scope_css: comma-separated selectors are scoped one by one" {
  inspect(
    @core.scope_css("p, a { color: red }", ".x"),
    content=".x p, .x a { color: red }",
  )
}

///|
test "scope_css: a comma inside parentheses is not a separator" {
  inspect(
    @core.scope_css("a:is(b, c) p { color: red }", ".x"),
    content=".x a:is(b, c) p { color: red }",
  )
}

///|
test "scope_css: :host is replaced by the scope" {
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
test "scope_css: @media contents are scoped recursively" {
  inspect(
    @core.scope_css("@media (min-width: 600px) { p { color: red } }", ".x"),
    content="@media (min-width: 600px) { .x p { color: red } }",
  )
}

///|
test "scope_css: @keyframes is kept verbatim (frame selectors must not be prefixed)" {
  inspect(
    @core.scope_css(
      "@keyframes spin { from { opacity: 0 } to { opacity: 1 } }", ".x",
    ),
    content="@keyframes spin { from { opacity: 0 } to { opacity: 1 } }",
  )
}

///|
test "scope_css: comments are preserved" {
  inspect(
    @core.scope_css("/* note */ p { color: red }", ".x"),
    content="/* note */ .x p { color: red }",
  )
}

///|
test "scope_css: selector whitespace is normalized" {
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
test "scope_css: several rules and an at-statement" {
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
test "scope_css: an empty scope is the identity, empty input returns empty" {
  inspect(@core.scope_css("p { color: red }", ""), content="p { color: red }")
  inspect(@core.scope_css("", ".x"), content="")
}

///|
test "scope_css: at-rule names are case-insensitive (@MEDIA is scoped too)" {
  inspect(
    @core.scope_css("@MEDIA (min-width: 600px) { p { color: red } }", ".x"),
    content="@MEDIA (min-width: 600px) { .x p { color: red } }",
  )
  inspect(
    @core.scope_css("@KeyFrames spin { from { opacity: 0 } }", ".x"),
    content="@KeyFrames spin { from { opacity: 0 } }",
  )
}

///|
test "scope_css: nested parentheses inside :host are kept verbatim" {
  inspect(
    @core.scope_css(":host(:is(.a, .b)) { color: red }", "my-el"),
    content="my-el:is(.a, .b) { color: red }",
  )
}

///|
test "scope_css: an empty comma segment produces no extra prefix" {
  inspect(@core.scope_css(", p { a: b }", ".x"), content=", .x p { a: b }")
}
