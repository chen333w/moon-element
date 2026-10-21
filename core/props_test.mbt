///|
/// Props 的黑盒测试：纯逻辑，全后端可跑。

///|
fn badge_specs() -> Array[@core.AttrSpec] {
  [
    @core.AttrSpec::string("label", "?"),
    @core.AttrSpec::int("max-count", 3),
    @core.AttrSpec::double("ratio", 1.5),
    @core.AttrSpec::bool("disabled", false),
  ]
}

///|
test "Props: 初始值来自默认值" {
  let props = @core.Props::new(badge_specs())
  assert_eq(props.keys(), ["label", "max-count", "ratio", "disabled"])
  assert_eq(props.get_string("label"), Some("?"))
  assert_eq(props.get_int("max-count"), Some(3))
  assert_eq(props.get_double("ratio"), Some(1.5))
  assert_eq(props.get_bool("disabled"), Some(false))
}

///|
test "Props: 应用合法值" {
  let props = @core.Props::new(badge_specs())
  assert_true(props.apply("label", Some("hi")))
  assert_true(props.apply("max-count", Some("12")))
  assert_eq(props.get_string("label"), Some("hi"))
  assert_eq(props.get_int("max-count"), Some(12))
}

///|
test "Props: 非法值回退默认值，而不是报错" {
  let props = @core.Props::new(badge_specs())
  assert_true(props.apply("max-count", Some("abc")))
  assert_eq(props.get_int("max-count"), Some(3))
  // 先设成合法值，再设成非法值：应当回到默认值而不是保留旧值
  assert_true(props.apply("max-count", Some("9")))
  assert_eq(props.get_int("max-count"), Some(9))
  assert_true(props.apply("max-count", Some("9.5")))
  assert_eq(props.get_int("max-count"), Some(3))
}

///|
test "Props: 移除属性回退默认值" {
  let props = @core.Props::new(badge_specs())
  assert_true(props.apply("label", Some("hi")))
  assert_true(props.apply("label", None))
  assert_eq(props.get_string("label"), Some("?"))
}

///|
test "Props: 未声明的属性名被拒绝，且不改变任何取值" {
  let props = @core.Props::new(badge_specs())
  assert_false(props.apply("unknown", Some("x")))
  assert_eq(props.get("unknown"), None)
  assert_eq(props.get_string("label"), Some("?"))
}

///|
test "Props: 类型不符的读取返回 None（不做隐式转换）" {
  let props = @core.Props::new(badge_specs())
  assert_eq(props.get_int("label"), None)
  assert_eq(props.get_string("max-count"), None)
  assert_eq(props.get_bool("label"), None)
  assert_eq(props.get_double("max-count"), None)
  // 同名的通用读取仍能看到真实取值
  assert_eq(props.get("label"), Some(@core.VString("?")))
}

///|
test "Props: 布尔按存在即真" {
  let props = @core.Props::new(badge_specs())
  assert_true(props.apply("disabled", Some("")))
  assert_eq(props.get_bool("disabled"), Some(true))
  assert_true(props.apply("disabled", Some("false")))
  assert_eq(props.get_bool("disabled"), Some(true))
  assert_true(props.apply("disabled", None))
  assert_eq(props.get_bool("disabled"), Some(false))
}

///|
test "Props: 多个实例互不污染（specs 可共享，取值各自独立）" {
  let shared = badge_specs()
  let a = @core.Props::new(shared)
  let b = @core.Props::new(shared)
  assert_true(a.apply("label", Some("A")))
  assert_true(b.apply("label", Some("B")))
  assert_eq(a.get_string("label"), Some("A"))
  assert_eq(b.get_string("label"), Some("B"))
}
