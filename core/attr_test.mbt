///|
/// 属性反射的黑盒测试：只通过 `core` 的公开 API 断言行为。
/// 这些测试不碰 DOM，因此可以在每个后端上运行（`moon test --target all`）。

///|
fn close(actual : Double?, expected : Double) -> Bool {
  match actual {
    Some(v) => v.is_close(expected)
    None => false
  }
}

///|
test "kebab_to_camel" {
  assert_eq(@core.kebab_to_camel("max-count"), "maxCount")
  assert_eq(@core.kebab_to_camel("already"), "already")
  assert_eq(@core.kebab_to_camel("a-b-c"), "aBC")
  assert_eq(@core.kebab_to_camel(""), "")
  assert_eq(@core.kebab_to_camel("a--b"), "aB")
  assert_eq(@core.kebab_to_camel("a-"), "a")
  assert_eq(@core.kebab_to_camel("-a"), "A")
}

///|
test "camel_to_kebab" {
  assert_eq(@core.camel_to_kebab("maxCount"), "max-count")
  assert_eq(@core.camel_to_kebab("MaxCount"), "max-count")
  assert_eq(@core.camel_to_kebab("A"), "a")
  assert_eq(@core.camel_to_kebab("AB"), "a-b")
  assert_eq(@core.camel_to_kebab(""), "")
  assert_eq(@core.camel_to_kebab("already"), "already")
}

///|
test "属性名与 MoonBit 名可往返" {
  for name in ["max-count", "a-b-c", "x", "min-value-limit"] {
    assert_eq(@core.camel_to_kebab(@core.kebab_to_camel(name)), name)
  }
}

///|
test "parse_int: 合法输入" {
  assert_eq(@core.parse_int("0"), Some(0))
  assert_eq(@core.parse_int("42"), Some(42))
  assert_eq(@core.parse_int("-7"), Some(-7))
  assert_eq(@core.parse_int("+7"), Some(7))
  assert_eq(@core.parse_int("007"), Some(7))
  assert_eq(@core.parse_int("999999999"), Some(999999999))
}

///|
test "parse_int: 非法输入一律 None（不抛错、不静默截断）" {
  for
    bad in [
      "", "-", "+", " 42", "42 ", "4.2", "1_000", "0x10", "abc", "1e3", "1000000000",
      "9999999999", "-1000000000",
    ] {
    assert_eq(@core.parse_int(bad), None)
  }
}

///|
test "parse_double: 合法输入" {
  assert_true(close(@core.parse_double("3.5"), 3.5))
  assert_true(close(@core.parse_double("-0.25"), -0.25))
  assert_true(close(@core.parse_double("+2"), 2.0))
  assert_true(close(@core.parse_double(".5"), 0.5))
  assert_true(close(@core.parse_double("5"), 5.0))
  assert_true(close(@core.parse_double("100.125"), 100.125))
  assert_true(close(@core.parse_double("0.1"), 0.1))
}

///|
test "parse_double: 非法输入一律 None" {
  for
    bad in [
      "", "-", "+", ".", "5.", "1e3", "0x10", "abc", "1.2.3", "1.1234567890", "1000000000",
      "9.9999999999",
    ] {
    assert_eq(@core.parse_double(bad), None)
  }
}

///|
test "AttrSpec: 属性缺失时回退默认值" {
  assert_eq(@core.AttrSpec::int("max-count", 10).parse(None), @core.VInt(10))
  assert_eq(
    @core.AttrSpec::string("label", "hi").parse(None),
    @core.VString("hi"),
  )
  assert_eq(
    @core.AttrSpec::bool("disabled", false).parse(None),
    @core.VBool(false),
  )
  assert_eq(
    @core.AttrSpec::double("ratio", 1.0).parse(None),
    @core.VDouble(1.0),
  )
}

///|
test "AttrSpec: 非法值回退默认值（HTML 的宽松语义）" {
  assert_eq(
    @core.AttrSpec::int("max-count", 10).parse(Some("abc")),
    @core.VInt(10),
  )
  assert_eq(
    @core.AttrSpec::int("max-count", 10).parse(Some("4.5")),
    @core.VInt(10),
  )
  assert_eq(
    @core.AttrSpec::double("ratio", 0.5).parse(Some("nope")),
    @core.VDouble(0.5),
  )
  assert_eq(
    @core.AttrSpec::string("label", "hi").parse(Some("anything")),
    @core.VString("anything"),
  )
}

///|
test "AttrSpec: 合法值被采用" {
  assert_eq(
    @core.AttrSpec::int("max-count", 10).parse(Some("12")),
    @core.VInt(12),
  )
  assert_eq(
    @core.AttrSpec::double("ratio", 0.5).parse(Some("-2.5")),
    @core.VDouble(-2.5),
  )
}

///|
test "AttrSpec: 布尔按「存在即真」解析" {
  let spec = @core.AttrSpec::bool("disabled", false)
  assert_eq(spec.parse(Some("")), @core.VBool(true))
  assert_eq(spec.parse(Some("false")), @core.VBool(true))
  assert_eq(spec.parse(Some("0")), @core.VBool(true))
  assert_eq(spec.parse(None), @core.VBool(false))
}

///|
test "AttrValue::to_attr: 布尔假用「移除属性」表达" {
  assert_eq(@core.VString("x").to_attr(), Some("x"))
  assert_eq(@core.VInt(5).to_attr(), Some("5"))
  assert_eq(@core.VDouble(2.5).to_attr(), Some("2.5"))
  assert_eq(@core.VBool(true).to_attr(), Some(""))
  assert_eq(@core.VBool(false).to_attr(), None)
}

///|
test "kebab_to_camel: 短横线后的非小写字母不被改动" {
  // 已是大写：不重复大写
  assert_eq(@core.kebab_to_camel("-A"), "A")
  assert_eq(@core.kebab_to_camel("x-A"), "xA")
  // 不是字母：原样保留，并且会「消耗掉」这一次大写动作
  assert_eq(@core.kebab_to_camel("-1"), "1")
  assert_eq(@core.kebab_to_camel("x-_y"), "x_y")
  assert_eq(@core.kebab_to_camel("x-_Y"), "x_Y")
}

///|
test "AttrSpec::prop_name 由属性名推导，避免两处不一致" {
  assert_eq(@core.AttrSpec::int("max-count", 0).prop_name(), "maxCount")
  assert_eq(@core.AttrSpec::bool("show-icon", false).prop_name(), "showIcon")
}

///|
test "observed_attributes 只列出被声明的属性" {
  let specs : Array[@core.AttrSpec] = [
    @core.AttrSpec::string("label", ""),
    @core.AttrSpec::int("max-count", 0),
    @core.AttrSpec::bool("disabled", false),
  ]
  assert_eq(@core.observed_attributes(specs), ["label", "max-count", "disabled"])
}

///|
test "AttrSpec::kind 与 default_value 可读（供适配层与调试使用）" {
  assert_eq(@core.AttrSpec::string("a", "").kind(), @core.AttrString)
  assert_eq(@core.AttrSpec::int("b", 1).kind(), @core.AttrInt)
  assert_eq(@core.AttrSpec::double("c", 1.0).kind(), @core.AttrDouble)
  assert_eq(@core.AttrSpec::bool("d", false).kind(), @core.AttrBool)
  assert_eq(@core.AttrSpec::int("b", 1).default_value(), @core.VInt(1))
  assert_eq(@core.AttrSpec::string("a", "x").attr_name(), "a")
}
