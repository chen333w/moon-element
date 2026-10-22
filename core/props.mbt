///|
/// The current values of a group of attributes.
///
/// `Props` is the runtime-state half of attribute reflection: it keeps `specs` (the
/// specification, shareable between instances) apart from `values` (one set per
/// instance), so two instances cannot pollute each other. Fallback semantics match
/// `AttrSpec::parse` exactly: missing or invalid → the default.
pub struct Props {
  specs : Array[AttrSpec]
  values : Array[AttrValue]
}

///|
/// Build a value set from the specs, all initialized to their defaults.
pub fn Props::new(specs : Array[AttrSpec]) -> Props {
  let values : Array[AttrValue] = []
  for spec in specs {
    values.push(spec.default_value())
  }
  { specs, values, }
}

///|
/// Apply one attribute change: `None` means the attribute was removed → fall back to the
/// default.
///
/// `false` means the attribute name is not in the specs (not observed), in which case no
/// value changes. Browsers only call back for observed attributes; the return value is
/// for defensive checks and debugging.
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
/// Read a string value by attribute name; returns `None` on a **type mismatch** or a
/// missing attribute. There is no implicit conversion, so numeric attributes such as
/// `max-count` are never quietly read as strings.
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
/// The attribute names in the specs, in `specs` order, for debugging and snapshots.
pub fn Props::keys(self : Props) -> Array[String] {
  let out : Array[String] = []
  for spec in self.specs {
    out.push(spec.attr_name())
  }
  out
}
