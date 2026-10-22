///|
/// Attribute value types, plus the rules that map an HTML attribute string to a
/// MoonBit value.
///
/// Boolean attributes follow HTML semantics: **presence means true**, independent of
/// the literal content (`<x-flag>` and `<x-flag="">` are both true).
pub(all) enum AttrKind {
  AttrString
  AttrInt
  AttrDouble
  AttrBool
} derive(Eq, @debug.Debug)

///|
/// `derive` produces these as implicitly promoted methods (deprecated); declare them
/// explicitly to silence the warning.
pub extend AttrKind with Eq::{equal, not_equal}

///|
pub extend AttrKind with @debug.Debug::{to_repr}

///|
/// An attribute value.
///
/// Integers are carried as `Int`. The parsers accept at most **9 decimal digits**:
/// `Int` width may differ between backends, so capping the digit count keeps invalid
/// values on the default and behaviour identical across backends.
pub(all) enum AttrValue {
  VString(String)
  VInt(Int32)
  VDouble(Double)
  VBool(Bool)
} derive(Eq, @debug.Debug)

///|
/// Declare explicitly to silence the deprecation warning for implicitly promoted derived methods.
pub extend AttrValue with Eq::{equal, not_equal}

///|
/// Declare explicitly to silence the deprecation warning for implicitly promoted derived methods.
pub extend AttrValue with @debug.Debug::{to_repr}

///|
/// Specification of one observable attribute.
///
/// - `attr_name` is the HTML-side name, kebab-case by convention (e.g. `max-count`)
/// - `prop_name()` derives the MoonBit-side camelCase name, so the two cannot drift apart
/// - `default` is used when the attribute is missing **or its value is invalid**
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
/// MoonBit-side attribute name: `max-count` → `maxCount`.
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
/// Parse a raw attribute value.
///
/// - `None` (attribute absent or removed) → the default
/// - invalid string (e.g. `"abc"` for `AttrInt`) → the **default**, matching HTML's lenient semantics
/// - `AttrBool`: any `Some(_)` is true (presence means true)
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
/// Value → attribute string. `None` means the attribute should be removed.
///
/// Only `VBool(false)` returns `None`: a boolean's state lives in whether the attribute
/// is present, not in its text. Setting the string to `"false"` cannot express false —
/// it would parse back as true under presence-means-true.
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
/// Derive `observedAttributes` from the specs: only these names receive change callbacks.
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
/// `max-count` → `maxCount` (ASCII kebab-case to camelCase).
///
/// Consecutive hyphens capitalize only once (`a--b` → `aB`); a trailing hyphen is
/// ignored (`a-` → `a`); a leading hyphen capitalizes the first character (`-a` → `A`).
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
/// `maxCount` → `max-count` (ASCII camelCase to kebab-case).
///
/// Inserts a hyphen before every uppercase character except the first
/// (`MaxCount` → `max-count`).
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
/// Parse a strict decimal integer.
///
/// Accepts an optional `+`/`-` followed by 1–9 decimal digits; leading zeros are allowed
/// (`007` → 7). Rejects empty input, a sign alone, whitespace, underscores, decimal
/// points, scientific notation, and 10 or more digits.
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
/// Parse a strict decimal number.
///
/// Accepts an optional `+`/`-`, 0–9 integer digits, and an optional `.` followed by 1–9
/// fractional digits; integer and fractional digits together must number at least 1
/// (so `.5` and `5` are valid, while `.` and `5.` are not). Rejects whitespace,
/// scientific notation (`1e3`), hexadecimal, multiple decimal points, and more than 9
/// fractional digits.
///
/// The fractional part accumulates as an integer and is divided once at the end, which
/// limits accumulated rounding error.
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
