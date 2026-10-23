///|
/// Binds a DOM event type to elements in the rendered content that carry `data-act`.
///
/// Rendering replaces the content, so a listener on an inner element would be dropped by the
/// next render. The adapter instead attaches one listener per event type to the shadow root
/// (or to the host element in light mode), both of which survive rendering, and reads the
/// `data-act` value from the element the event came from.
pub(all) struct ActionSpec {
  event : String
  action : String
}

///|
pub fn ActionSpec::new(event : String, action : String) -> ActionSpec {
  { event, action, }
}

///|
pub fn ActionSpec::event(self : ActionSpec) -> String {
  self.event
}

///|
pub fn ActionSpec::action(self : ActionSpec) -> String {
  self.action
}

///|
/// Non-empty, with no ASCII whitespace and no quote characters: the value ends up in an
/// attribute written by the view layer.
pub fn is_valid_action(action : String) -> Bool {
  let n = action.char_length()
  if n == 0 {
    return false
  }
  let mut i = 0
  while i < n {
    match action.get_char(i) {
      Some(c) => {
        let v = c.to_int()
        // space, tab, newline, carriage return, double quote, single quote
        if v == 32 || v == 9 || v == 10 || v == 13 || v == 34 || v == 39 {
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
/// The actions a component handles. A spec is rejected when the event type or the action is
/// invalid, or when the same pair is already registered.
pub struct ActionRegistry {
  specs : Array[ActionSpec]
}

///|
pub fn ActionRegistry::new() -> ActionRegistry {
  { specs: [], }
}

///|
pub fn ActionRegistry::add(self : ActionRegistry, spec : ActionSpec) -> Bool {
  if !is_valid_event_name(spec.event()) || !is_valid_action(spec.action()) {
    return false
  }
  match self.find(spec.event(), spec.action()) {
    Some(_) => false
    None => {
      self.specs.push(spec)
      true
    }
  }
}

///|
pub fn ActionRegistry::find(
  self : ActionRegistry,
  event : String,
  action : String,
) -> ActionSpec? {
  for spec in self.specs {
    if spec.event() == event && spec.action() == action {
      return Some(spec)
    }
  }
  None
}

///|
/// Distinct event types in registration order; one listener per type is enough.
pub fn ActionRegistry::event_types(self : ActionRegistry) -> Array[String] {
  let out : Array[String] = []
  for spec in self.specs {
    let mut seen = false
    for existing in out {
      if existing == spec.event() {
        seen = true
      }
    }
    if !seen {
      out.push(spec.event())
    }
  }
  out
}

///|
pub fn ActionRegistry::length(self : ActionRegistry) -> Int32 {
  self.specs.length()
}
