///|
/// D0 spike: define and register a real Web Component on the JavaScript backend
/// (a class that `extends HTMLElement`, registered through
/// `customElements.define`), and call back into MoonBit from the DOM callback
/// path.
///
/// `install_dom_stub` provides a minimal DOM shim, so the whole path runs
/// headlessly under `moon test --target js` without a browser or a DOM
/// emulator. Findings are recorded in `docs/feasibility.md`.

///|
/// Install a minimal DOM shim when running headless (e.g. under node).
/// No-op when a real DOM is present, so the same code runs in a browser page
/// and in tests.
pub extern "js" fn install_dom_stub() -> Unit =
  #|() => {
  #|  if (typeof globalThis.customElements === "undefined") {
  #|    globalThis.__moon_element_registry = Object.create(null);
  #|    globalThis.HTMLElement = class HTMLElement {};
  #|    // 真实的 HTMLElement 有 attachShadow；stub 也要有，否则适配层的
  #|    // shadow DOM 路径在无浏览器环境下无法测试。
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
  #|    // 事件相关的三个东西：CustomEvent、addEventListener、dispatchEvent。
  #|    // 只实现适配层与测试需要的最小子集（同步派发、不实现捕获/冒泡路径传播）。
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
  #|      // 浏览器语义：返回 false 表示有监听者取消了默认行为
  #|      return !ev.defaultPrevented;
  #|    };
  #|  }
  #|}

///|
/// Define a custom element named `name` whose `connectedCallback` calls
/// `on_connected`.
///
/// The class extends `HTMLElement` directly, as the Custom Elements registry
/// requires. The JS backend supports closures natively, so a plain MoonBit
/// function type is used here rather than `FuncRef`.
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
/// Headless probe: is `name` registered, and is its prototype chain rooted in
/// `HTMLElement`? Returns `false` for unknown names.
pub extern "js" fn is_registered_element(name : String) -> Bool =
  #|(name) => {
  #|  const ctor = globalThis.customElements.get(name);
  #|  return (
  #|    typeof ctor === "function" &&
  #|    ctor.prototype instanceof globalThis.HTMLElement
  #|  );
  #|}

///|
/// Headless probe: instantiate the registered element once and invoke its
/// `connectedCallback`. Used to exercise the DOM → MoonBit direction.
pub extern "js" fn fire_connected(name : String) -> Unit =
  #|(name) => {
  #|  const ctor = globalThis.customElements.get(name);
  #|  const el = new ctor();
  #|  if (typeof el.connectedCallback === "function") {
  #|    el.connectedCallback();
  #|  }
  #|}

///|
/// A marker incremented from JavaScript. Used as the MoonBit callback so the
/// test can tell whether MoonBit code actually ran.
pub extern "js" fn js_mark() -> Unit =
  #|() => {
  #|  globalThis.__moon_element_marks = (globalThis.__moon_element_marks || 0) + 1;
  #|}

///|
/// How many times `js_mark` ran.
pub extern "js" fn js_mark_count() -> Int32 =
  #|() => globalThis.__moon_element_marks || 0
