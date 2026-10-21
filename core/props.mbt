///|
/// 一组属性的当前取值。
///
/// `Props` 是属性反射的「运行时状态」部分：它把 `specs`（规格，可被多个实例共享）
/// 与 `values`（取值，每个实例一份）分开存放，避免两个实例互相污染。
/// 取值的回退语义与 `AttrSpec::parse` 完全一致：缺失或非法 → 默认值。
pub struct Props {
  specs : Array[AttrSpec]
  values : Array[AttrValue]
}

///|
/// 按规格建立一份取值，初始全部为默认值。
pub fn Props::new(specs : Array[AttrSpec]) -> Props {
  let values : Array[AttrValue] = []
  for spec in specs {
    values.push(spec.default_value())
  }
  { specs, values, }
}

///|
/// 应用一次属性变化：`None` 表示属性被移除 → 回退默认值。
///
/// 返回 `false` 表示这个属性名不在规格里（未被观察）；此时取值不变。
/// 注意：调用方**不应**把 `false` 当作错误——真实浏览器只会回调被观察的属性，
/// 这个返回值主要用于防御性检查与调试。
pub fn Props::apply(self : Props, attr_name : String, raw : String?) -> Bool {
  let mut i = 0
  while i < self.specs.length() {
    if self.specs[i].attr_name() == attr_name {
      self.values[i] = self.specs[i].parse(raw)
      return true
    }
    i = i + 1
  }
  false
}

///|
pub fn Props::get(self : Props, attr_name : String) -> AttrValue? {
  let mut i = 0
  while i < self.specs.length() {
    if self.specs[i].attr_name() == attr_name {
      return Some(self.values[i])
    }
    i = i + 1
  }
  None
}

///|
/// 按属性名读字符串值；**类型不符**或属性不存在时返回 `None`（不做隐式转换，
/// 以免把 `max-count` 这类数字属性悄悄当成字符串用）。
pub fn Props::get_string(self : Props, attr_name : String) -> String? {
  match self.get(attr_name) {
    Some(VString(s)) => Some(s)
    _ => None
  }
}

///|
pub fn Props::get_int(self : Props, attr_name : String) -> Int32? {
  match self.get(attr_name) {
    Some(VInt(v)) => Some(v)
    _ => None
  }
}

///|
pub fn Props::get_double(self : Props, attr_name : String) -> Double? {
  match self.get(attr_name) {
    Some(VDouble(v)) => Some(v)
    _ => None
  }
}

///|
pub fn Props::get_bool(self : Props, attr_name : String) -> Bool? {
  match self.get(attr_name) {
    Some(VBool(v)) => Some(v)
    _ => None
  }
}

///|
/// 规格里的属性名（顺序与 `specs` 一致），用于调试与快照。
pub fn Props::keys(self : Props) -> Array[String] {
  let out : Array[String] = []
  for spec in self.specs {
    out.push(spec.attr_name())
  }
  out
}
