///|
/// Description of an event a component dispatches. The fields map to `CustomEvent` init
/// options; a host page only receives an event thrown inside the component when it is
/// `composed = true`, otherwise the shadow root stops it.
pub struct EventSpec {
  name : String
  bubbles : Bool
  composed : Bool
}

///|
pub fn EventSpec::new(
  name : String,
  bubbles : Bool,
  composed : Bool,
) -> EventSpec {
  { name, bubbles, composed, }
}

///|
/// Bubbles and crosses the shadow boundary (`bubbles` and `composed` are both true).
pub fn EventSpec::crossing(name : String) -> EventSpec {
  { name, bubbles: true, composed: true, }
}

///|
/// Does not bubble and does not cross the shadow boundary. Named `contained` because
/// `local` is a MoonBit reserved word.
pub fn EventSpec::contained(name : String) -> EventSpec {
  { name, bubbles: false, composed: false, }
}

///|
pub fn EventSpec::name(self : EventSpec) -> String {
  self.name
}

///|
pub fn EventSpec::bubbles(self : EventSpec) -> Bool {
  self.bubbles
}

///|
pub fn EventSpec::composed(self : EventSpec) -> Bool {
  self.composed
}

///|
/// Valid event name: non-empty with no ASCII whitespace (a spaced name is dispatched to
/// nobody).
pub fn is_valid_event_name(name : String) -> Bool {
  let n = name.char_length()
  if n == 0 {
    return false
  }
  let mut i = 0
  while i < n {
    match name.get_char(i) {
      Some(c) => {
        let v = c.to_int()
        // space, tab, newline, carriage return
        if v == 32 || v == 9 || v == 10 || v == 13 {
          return false
        }
      }
      None => ()
    }
    i = i + 1
  }
  true
}

///|
/// The set of events a component declares. Duplicate and invalid names are rejected at
/// registration time.
pub struct EventRegistry {
  specs : Array[EventSpec]
}

///|
pub fn EventRegistry::new() -> EventRegistry {
  { specs: [], }
}

///|
/// Register an event; `false` means the name is invalid or already registered.
pub fn EventRegistry::add(self : EventRegistry, spec : EventSpec) -> Bool {
  if !is_valid_event_name(spec.name()) {
    return false
  }
  match self.find(spec.name()) {
    Some(_) => false
    None => {
      self.specs.push(spec)
      true
    }
  }
}

///|
pub fn EventRegistry::find(self : EventRegistry, name : String) -> EventSpec? {
  for spec in self.specs {
    if spec.name() == name {
      return Some(spec)
    }
  }
  None
}

///|
pub fn EventRegistry::names(self : EventRegistry) -> Array[String] {
  let out : Array[String] = []
  for spec in self.specs {
    out.push(spec.name())
  }
  out
}

///|
pub fn EventRegistry::length(self : EventRegistry) -> Int32 {
  self.specs.length()
}
