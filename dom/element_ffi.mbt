///|
/// JS backend spike: register a real custom element and call back into MoonBit.
/// `install_dom_stub` makes the path testable headlessly.

///|
/// Install a minimal DOM shim when running headless; no-op if a DOM is present.
pub extern "js" fn install_dom_stub() -> Unit =
  #|() => {
  #|  if (typeof globalThis.customElements === "undefined") {
  #|    globalThis.__moon_element_registry = Object.create(null);
  #|    globalThis.HTMLElement = class HTMLElement {};
  #|    // The stub needs attachShadow too, or the shadow DOM path is untestable headlessly.
  #|    globalThis.HTMLElement.prototype.attachShadow = function (opts) {
  #|      this.shadowRoot = {
  #|        innerHTML: "",
  #|        host: this,
  #|        mode: (opts && opts.mode) || "open",
  #|      };
  #|      return this.shadowRoot;
  #|    };
  #|    globalThis.customElements = {
  #|      define(name, ctor) {
  #|        globalThis.__moon_element_registry[name] = ctor;
  #|      },
  #|      get(name) {
  #|        return globalThis.__moon_element_registry[name];
  #|      },
  #|    };
  #|    // Minimal event subset: synchronous dispatch, no capture or bubble propagation.
  #|    globalThis.CustomEvent = class CustomEvent {
  #|      constructor(type, init) {
  #|        this.type = type;
  #|        this.detail = init && init.detail;
  #|        this.bubbles = !!(init && init.bubbles);
  #|        this.composed = !!(init && init.composed);
  #|        this.cancelable = !!(init && init.cancelable);
  #|        this.defaultPrevented = false;
  #|      }
  #|      preventDefault() {
  #|        if (this.cancelable) {
  #|          this.defaultPrevented = true;
  #|        }
  #|      }
  #|    };
  #|    globalThis.HTMLElement.prototype.addEventListener = function (type, fn) {
  #|      if (!this.__listeners) {
  #|        this.__listeners = Object.create(null);
  #|      }
  #|      (this.__listeners[type] || (this.__listeners[type] = [])).push(fn);
  #|    };
  #|    globalThis.HTMLElement.prototype.dispatchEvent = function (ev) {
  #|      const list = (this.__listeners && this.__listeners[ev.type]) || [];
  #|      for (const fn of list) {
  #|        fn(ev);
  #|      }
  #|      return !ev.defaultPrevented;
  #|    };
  #|  }
  #|}

///|
/// The JS backend supports closures natively, so this takes a plain MoonBit
/// function type rather than `FuncRef`.
pub extern "js" fn define_element(
  name : String,
  on_connected : () -> Unit,
) -> Unit =
  #|(name, onConnected) => {
  #|  class MoonElement extends globalThis.HTMLElement {
  #|    connectedCallback() {
  #|      onConnected();
  #|    }
  #|  }
  #|  globalThis.customElements.define(name, MoonElement);
  #|}

///|
pub extern "js" fn is_registered_element(name : String) -> Bool =
  #|(name) => {
  #|  const ctor = globalThis.customElements.get(name);
  #|  return (
  #|    typeof ctor === "function" &&
  #|    ctor.prototype instanceof globalThis.HTMLElement
  #|  );
  #|}

///|
pub extern "js" fn fire_connected(name : String) -> Unit =
  #|(name) => {
  #|  const ctor = globalThis.customElements.get(name);
  #|  const el = new ctor();
  #|  if (typeof el.connectedCallback === "function") {
  #|    el.connectedCallback();
  #|  }
  #|}

///|
pub extern "js" fn js_mark() -> Unit =
  #|() => {
  #|  globalThis.__moon_element_marks = (globalThis.__moon_element_marks || 0) + 1;
  #|}

///|
pub extern "js" fn js_mark_count() -> Int32 =
  #|() => globalThis.__moon_element_marks || 0
