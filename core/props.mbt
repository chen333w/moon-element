///|
/// The current values of a group of attributes. `specs` is shareable between instances
/// while `values` is one set per instance; missing or invalid falls back to the default.
pub struct Props {
  specs : Array[AttrSpec]
  values : Array[AttrValue]
}

///|
pub fn Props::new(specs : Array[AttrSpec]) -> Props {
  let values : Array[AttrValue] = []
  for spec in specs {
    values.push(spec.default_value())
  }
  { specs, values, }
}

///|
/// Apply one attribute change; `None` means the attribute was removed. `false` means the
/// name is not in the specs, and no value changes.
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
/// Read a string value; `None` on type mismatch or a missing attribute. No implicit
/// conversion.
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
/// Attribute names in `specs` order.
pub fn Props::keys(self : Props) -> Array[String] {
  let out : Array[String] = []
  for spec in self.specs {
    out.push(spec.attr_name())
  }
  out
}
