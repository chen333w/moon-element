///|
/// Attribute value types. Boolean attributes follow HTML semantics: presence means true,
/// regardless of the literal content (`<x-flag>` and `<x-flag="">` are both true).
pub(all) enum AttrKind {
  AttrString
  AttrInt
  AttrDouble
  AttrBool
} derive(Eq, @debug.Debug)

///|
/// Implicitly promoted derived methods are deprecated; declare them explicitly to
/// silence the warning.
pub extend AttrKind with Eq::{equal, not_equal}

///|
pub extend AttrKind with @debug.Debug::{to_repr}

///|
/// An attribute value. Integers are carried as `Int`; the parsers accept at most 9
/// decimal digits because `Int` width differs between backends.
pub(all) enum AttrValue {
  VString(String)
  VInt(Int32)
  VDouble(Double)
  VBool(Bool)
} derive(Eq, @debug.Debug)

///|
pub extend AttrValue with Eq::{equal, not_equal}

///|
pub extend AttrValue with @debug.Debug::{to_repr}

///|
/// Specification of one observable attribute. `attr_name` is the HTML-side kebab-case name
/// (e.g. `max-count`); `default` is used when the attribute is missing or invalid.
pub struct AttrSpec {
  attr_name : String
  kind : AttrKind
  default : AttrValue
}

///|
pub fn AttrSpec::string(attr_name : String, default : String) -> AttrSpec {
  { attr_name, kind: AttrString, default: VString(default), }
}

///|
pub fn AttrSpec::int(attr_name : String, default : Int32) -> AttrSpec {
  { attr_name, kind: AttrInt, default: VInt(default), }
}

///|
pub fn AttrSpec::double(attr_name : String, default : Double) -> AttrSpec {
  { attr_name, kind: AttrDouble, default: VDouble(default), }
}

///|
pub fn AttrSpec::bool(attr_name : String, default : Bool) -> AttrSpec {
  { attr_name, kind: AttrBool, default: VBool(default), }
}

///|
pub fn AttrSpec::prop_name(self : AttrSpec) -> String {
  kebab_to_camel(self.attr_name)
}

///|
pub fn AttrSpec::attr_name(self : AttrSpec) -> String {
  self.attr_name
}

///|
pub fn AttrSpec::kind(self : AttrSpec) -> AttrKind {
  self.kind
}

///|
pub fn AttrSpec::default_value(self : AttrSpec) -> AttrValue {
  self.default
}

///|
/// Parse a raw attribute value. `None` or an invalid string yields the default (HTML's
/// lenient semantics); for `AttrBool` any `Some(_)` is true.
pub fn AttrSpec::parse(self : AttrSpec, raw : String?) -> AttrValue {
  match raw {
    None => self.default
    Some(s) =>
      match self.kind {
        AttrString => VString(s)
        AttrInt =>
          match parse_int(s) {
            Some(v) => VInt(v)
            None => self.default
          }
        AttrDouble =>
          match parse_double(s) {
            Some(v) => VDouble(v)
            None => self.default
          }
        AttrBool => VBool(true)
      }
  }
}

///|
/// Value to attribute string; `None` means remove the attribute. Only `VBool(false)`
/// returns `None`, since `"false"` would parse back as true.
pub fn AttrValue::to_attr(self : AttrValue) -> String? {
  match self {
    VString(s) => Some(s)
    VInt(v) => Some(v.to_string())
    VDouble(v) => Some(v.to_string())
    VBool(true) => Some("")
    VBool(false) => None
  }
}

///|
/// Names exposed as `observedAttributes`; only these receive change callbacks.
pub fn observed_attributes(specs : Array[AttrSpec]) -> Array[String] {
  let out : Array[String] = []
  for spec in specs {
    out.push(spec.attr_name)
  }
  out
}

///|
fn digit_value(c : Char) -> Int32? {
  let v = c.to_int() - '0'.to_int()
  if v >= 0 && v <= 9 {
    Some(v)
  } else {
    None
  }
}

///|
fn is_ascii_upper(c : Char) -> Bool {
  let v = c.to_int()
  v >= 'A'.to_int() && v <= 'Z'.to_int()
}

///|
fn ascii_to_upper(c : Char) -> Char {
  if is_ascii_upper(c) {
    c
  } else {
    let v = c.to_int()
    if v >= 'a'.to_int() && v <= 'z'.to_int() {
      match (v - 32).to_char() {
        Some(u) => u
        None => c
      }
    } else {
      c
    }
  }
}

///|
fn ascii_to_lower(c : Char) -> Char {
  let v = c.to_int()
  if v >= 'A'.to_int() && v <= 'Z'.to_int() {
    match (v + 32).to_char() {
      Some(l) => l
      None => c
    }
  } else {
    c
  }
}

///|
/// ASCII kebab-case to camelCase. Consecutive hyphens capitalize once (`a--b` → `aB`), a
/// trailing hyphen is ignored, a leading hyphen capitalizes the first character.
pub fn kebab_to_camel(name : String) -> String {
  let out : Array[Char] = []
  let n = name.char_length()
  let mut i : Int32 = 0
  let mut upper_next = false
  while i < n {
    match name.get_char(i) {
      Some(c) =>
        if c == '-' {
          upper_next = true
        } else if upper_next {
          out.push(ascii_to_upper(c))
          upper_next = false
        } else {
          out.push(c)
        }
      None => ()
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
/// ASCII camelCase to kebab-case; a hyphen goes before every uppercase character except
/// the first (`MaxCount` → `max-count`).
pub fn camel_to_kebab(name : String) -> String {
  let out : Array[Char] = []
  let n = name.char_length()
  let mut i : Int32 = 0
  while i < n {
    match name.get_char(i) {
      Some(c) =>
        if is_ascii_upper(c) {
          if i > 0 {
            out.push('-')
          }
          out.push(ascii_to_lower(c))
        } else {
          out.push(c)
        }
      None => ()
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
/// Strict decimal integer: optional `+`/`-`, 1–9 digits, leading zeros allowed. Rejects
/// whitespace, `_`, `.`, scientific notation and 10 or more digits.
pub fn parse_int(s : String) -> Int32? {
  let n = s.char_length()
  if n == 0 {
    return None
  }
  let mut i : Int32 = 0
  let mut negative = false
  match s.get_char(0) {
    Some(c) =>
      if c == '-' {
        negative = true
        i = 1
      } else if c == '+' {
        i = 1
      }
    None => return None
  }
  if i >= n {
    return None
  }
  let mut acc : Int32 = 0
  let mut digits = 0
  while i < n {
    let ok = match s.get_char(i) {
      Some(c) =>
        match digit_value(c) {
          Some(d) => {
            acc = acc * 10 + d
            digits = digits + 1
            digits <= 9
          }
          None => false
        }
      None => false
    }
    if !ok {
      return None
    }
    i = i + 1
  }
  if negative {
    Some(-acc)
  } else {
    Some(acc)
  }
}

///|
/// Strict decimal number: optional `+`/`-`, optional `.` with 1–9 fractional digits
/// (`.5` is valid, `5.` is not). Rejects `1e3`, hex, multiple dots and 10+ digits.
pub fn parse_double(s : String) -> Double? {
  let n = s.char_length()
  if n == 0 {
    return None
  }
  let mut i : Int32 = 0
  let mut negative = false
  match s.get_char(0) {
    Some(c) =>
      if c == '-' {
        negative = true
        i = 1
      } else if c == '+' {
        i = 1
      }
    None => return None
  }
  let mut int_part : Int32 = 0
  let mut int_digits = 0
  let mut frac_part : Int32 = 0
  let mut frac_digits = 0
  let mut seen_dot = false
  while i < n {
    match s.get_char(i) {
      Some(c) =>
        if c == '.' {
          if seen_dot {
            return None
          }
          seen_dot = true
        } else {
          match digit_value(c) {
            Some(d) =>
              if seen_dot {
                frac_digits = frac_digits + 1
                if frac_digits > 9 {
                  return None
                }
                frac_part = frac_part * 10 + d
              } else {
                int_digits = int_digits + 1
                if int_digits > 9 {
                  return None
                }
                int_part = int_part * 10 + d
              }
            None => return None
          }
        }
      None => return None
    }
    i = i + 1
  }
  if int_digits + frac_digits == 0 {
    return None
  }
  if seen_dot && frac_digits == 0 {
    return None
  }
  let mut value = Double::from_int(int_part)
  if frac_digits > 0 {
    let mut scale = 1.0
    let mut k = 0
    while k < frac_digits {
      scale = scale * 10.0
      k = k + 1
    }
    value = value + Double::from_int(frac_part) / scale
  }
  if negative {
    Some(-value)
  } else {
    Some(value)
  }
}
