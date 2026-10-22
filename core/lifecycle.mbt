///|
/// Lifecycle state of a custom element. As in the DOM spec this is a boolean: a removed
/// element is indistinguishable from one that was never connected.
pub(all) enum LifecycleState {
  Unconnected
  Connected
} derive(Eq, @debug.Debug)

///|
pub extend LifecycleState with Eq::{equal, not_equal}

///|
pub extend LifecycleState with @debug.Debug::{to_repr}

///|
/// A lifecycle reaction (custom element reactions in the spec). The `React` prefix avoids
/// clashing with the same-named `LifecycleState` constructors.
pub(all) enum Reaction {
  ReactConnected
  ReactDisconnected
  ReactAttributeChanged(String, String?, String?)
  ReactAdopted
} derive(@debug.Debug)

///|
pub extend Reaction with @debug.Debug::{to_repr}

///|
/// The lifecycle state machine plus its reaction log. It never touches the DOM; the
/// adapter layer turns browser callbacks into these calls.
pub struct Lifecycle {
  mut state : LifecycleState
  mut connect_count : Int32
  mut disconnect_count : Int32
  // no mut needed: push mutates the array contents, not this field
  reactions : Array[Reaction]
}

///|
pub fn Lifecycle::new() -> Lifecycle {
  { state: Unconnected, connect_count: 0, disconnect_count: 0, reactions: [], }
}

///|
/// The element was inserted into the document. An already connected element produces no
/// reaction (per spec); `false` means no reaction happened this time.
pub fn Lifecycle::on_connect(self : Lifecycle) -> Bool {
  if self.state == Connected {
    false
  } else {
    self.state = Connected
    self.connect_count = self.connect_count + 1
    self.reactions.push(ReactConnected)
    true
  }
}

///|
/// The element was removed from the document. No reaction when unconnected; returns `false`.
pub fn Lifecycle::on_disconnect(self : Lifecycle) -> Bool {
  if self.state == Unconnected {
    false
  } else {
    self.state = Unconnected
    self.disconnect_count = self.disconnect_count + 1
    self.reactions.push(ReactDisconnected)
    true
  }
}

///|
/// An attribute changed. Per spec the change is recorded whether or not the element is
/// connected; filtering unobserved attributes is the adapter's job.
pub fn Lifecycle::on_attribute_changed(
  self : Lifecycle,
  attr_name : String,
  old_value : String?,
  new_value : String?,
) -> Unit {
  self.reactions.push(ReactAttributeChanged(attr_name, old_value, new_value))
}

///|
/// The element was moved to another document (`adoptedCallback`).
pub fn Lifecycle::on_adopted(self : Lifecycle) -> Unit {
  self.reactions.push(ReactAdopted)
}

///|
pub fn Lifecycle::is_connected(self : Lifecycle) -> Bool {
  self.state == Connected
}

///|
pub fn Lifecycle::state(self : Lifecycle) -> LifecycleState {
  self.state
}

///|
pub fn Lifecycle::connect_count(self : Lifecycle) -> Int32 {
  self.connect_count
}

///|
pub fn Lifecycle::disconnect_count(self : Lifecycle) -> Int32 {
  self.disconnect_count
}

///|
pub fn Lifecycle::reaction_count(self : Lifecycle) -> Int32 {
  self.reactions.length()
}

///|
/// The reaction sequence as stable strings, for assertions and snapshots, e.g.
/// `attribute:max-count:1->2` with `<none>` for a missing old value.
pub fn Lifecycle::reaction_log(self : Lifecycle) -> Array[String] {
  let out : Array[String] = []
  for r in self.reactions {
    out.push(reaction_to_string(r))
  }
  out
}

///|
fn reaction_to_string(r : Reaction) -> String {
  match r {
    ReactConnected => "connected"
    ReactDisconnected => "disconnected"
    ReactAdopted => "adopted"
    ReactAttributeChanged(name, old_value, new_value) => {
      let o = match old_value {
        Some(v) => v
        None => "<none>"
      }
      let n = match new_value {
        Some(v) => v
        None => "<none>"
      }
      "attribute:\{name}:\{o}->\{n}"
    }
  }
}
