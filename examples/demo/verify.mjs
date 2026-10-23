// Headless check: imports the build artifact (the file the browser loads) in node.
//
// Usage, from the repository root:
//   moon build --target js --release
//   node examples/demo/verify.mjs
//
// Exit code 0 means every check passed; 1 means an assertion failed.

import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

// Minimal DOM stub, equivalent to install_dom_stub in dom/element_ffi.mbt.
function installDomStub() {
  if (globalThis.customElements) return;
  globalThis.HTMLElement = class HTMLElement {};
  const stubAdd = function (type, fn) {
    if (!this.__listeners) this.__listeners = Object.create(null);
    (this.__listeners[type] || (this.__listeners[type] = [])).push(fn);
  };
  const stubDispatch = function (ev) {
    const list = (this.__listeners && this.__listeners[ev.type]) || [];
    for (const fn of list) fn(ev);
    return !ev.defaultPrevented;
  };
  // The shadow root needs the same listener surface as an element: actions are bound there.
  globalThis.HTMLElement.prototype.attachShadow = function (opts) {
    this.shadowRoot = {
      innerHTML: "",
      host: this,
      mode: (opts && opts.mode) || "open",
      addEventListener: stubAdd,
      dispatchEvent: stubDispatch,
    };
    return this.shadowRoot;
  };
  globalThis.HTMLElement.prototype.addEventListener = stubAdd;
  globalThis.HTMLElement.prototype.dispatchEvent = stubDispatch;
  globalThis.CustomEvent = class CustomEvent {
    constructor(type, init) {
      this.type = type;
      this.detail = init && init.detail;
      this.bubbles = !!(init && init.bubbles);
      this.composed = !!(init && init.composed);
      this.cancelable = !!(init && init.cancelable);
      this.defaultPrevented = false;
    }
    preventDefault() {
      if (this.cancelable) this.defaultPrevented = true;
    }
  };
  // Real attribute methods, so set_attribute goes through attributeChangedCallback.
  globalThis.HTMLElement.prototype.setAttribute = function (name, value) {
    if (!this.__moonAttrs) this.__moonAttrs = Object.create(null);
    const old = this.__moonAttrs[name];
    this.__moonAttrs[name] = String(value);
    if (typeof this.attributeChangedCallback === "function") {
      this.attributeChangedCallback(name, old === undefined ? null : old, String(value));
    }
  };
  globalThis.HTMLElement.prototype.removeAttribute = function (name) {
    const old = this.__moonAttrs ? this.__moonAttrs[name] : undefined;
    if (this.__moonAttrs) delete this.__moonAttrs[name];
    if (typeof this.attributeChangedCallback === "function") {
      this.attributeChangedCallback(name, old === undefined ? null : old, null);
    }
  };
  globalThis.HTMLElement.prototype.getAttribute = function (name) {
    const value = this.__moonAttrs ? this.__moonAttrs[name] : undefined;
    return value === undefined ? null : value;
  };
  const registry = Object.create(null);
  globalThis.customElements = {
    define(name, ctor) {
      registry[name] = ctor;
    },
    get(name) {
      return registry[name];
    },
  };
  globalThis.__stubRegistry = registry;
}

// Minimal assertions
let failed = 0;
let passed = 0;
function check(name, cond, detail) {
  if (cond) {
    passed += 1;
    console.log(`  ok   ${name}`);
  } else {
    failed += 1;
    console.log(`  FAIL ${name}${detail === undefined ? "" : "  → " + detail}`);
  }
}

// 模拟组件内部点击：从 shadow root 派发带 data-act 的 target 链，与适配层的查找路径一致。
function fireAction(el, action) {
  const container = el.shadowRoot || el;
  const target = {
    getAttribute: (name) => (name === "data-act" ? action : null),
    parentNode: container,
  };
  container.dispatchEvent({ type: "click", target, defaultPrevented: false });
}

// 渲染出的计数，用于按数值比较而不是匹配整段 HTML。
function shownCount(el) {
  return Number(el.shadowRoot.innerHTML.match(/>(-?\d+)<\/div>/)?.[1]);
}

const bundlePath = new URL(
  "../../_build/js/release/build/examples/demo/demo.js",
  import.meta.url,
);

console.log("moon-element demo headless verification");
console.log(`bundle: ${bundlePath.pathname}`);

installDomStub();

// In the browser this is <script type="module" src="....js">.
let importError = null;
try {
  await import(pathToFileURL(bundlePath.pathname).href);
} catch (e) {
  importError = e;
}
check("the bundle loads and runs as an ES module", importError === null, String(importError));

const registry = globalThis.__stubRegistry || {};
check(
  "all four custom elements are registered after loading",
  ["x-counter", "x-badge", "x-card", "x-panel"].every((t) => typeof registry[t] === "function"),
  Object.keys(registry).join(","),
);

if (typeof registry["x-counter"] === "function") {
  check(
    "observedAttributes is generated from the attribute specs",
    JSON.stringify(registry["x-counter"].observedAttributes) ===
      JSON.stringify(["count", "max", "label"]),
    JSON.stringify(registry["x-counter"].observedAttributes),
  );

  // x-counter: attribute reflection + rendering
  const c = new registry["x-counter"]();
  c.connectedCallback();
  check(
    "defaults apply (count=0, max=10)",
    c.shadowRoot.innerHTML.includes(">0</div>"),
    c.shadowRoot.innerHTML.slice(0, 120),
  );

  const events = [];
  c.addEventListener("count-changed", (ev) => events.push(ev));

  c.attributeChangedCallback("count", null, "7");
  check("a valid attribute is adopted and re-renders", c.shadowRoot.innerHTML.includes(">7</div>"));
  check(
    "the component notifies the page through a crossing event (bubbles + composed)",
    events.length === 1 && events[0].bubbles === true && events[0].composed === true,
    JSON.stringify(events.map((e) => ({ t: e.type, b: e.bubbles, c: e.composed }))),
  );
  check("the bar width is computed from count/max", c.shadowRoot.innerHTML.includes("width:70%"));

  c.attributeChangedCallback("count", "7", "abc");
  check(
    "an invalid attribute value falls back to the default instead of erroring",
    c.shadowRoot.innerHTML.includes(">0</div>"),
    c.shadowRoot.innerHTML.match(/>-?\d+<\/div>/)?.[0],
  );

  // 组件自己的 + / - 按钮：由 on_action 处理，值夹在 0..max。
  c.setAttribute("count", "3");
  fireAction(c, "inc");
  check(
    "an in-component + button raises count to 4",
    c.shadowRoot.innerHTML.includes('data-act="inc"') && shownCount(c) === 4,
    `count=${shownCount(c)}`,
  );
  c.setAttribute("count", "4");
  fireAction(c, "dec");
  const afterDec = shownCount(c);
  c.setAttribute("count", "0");
  fireAction(c, "dec");
  check(
    "an in-component - button lowers count and stops at 0",
    c.shadowRoot.innerHTML.includes('data-act="dec"') &&
      afterDec === 3 &&
      shownCount(c) === 0,
    `after dec: ${afterDec}, again at 0: ${shownCount(c)}`,
  );

  // x-badge: HTML escaping
  const b = new registry["x-badge"]();
  b.connectedCallback();
  b.attributeChangedCallback("label", null, "<b>bold</b>");
  check(
    "user input is escaped and never executed as markup",
    b.shadowRoot.innerHTML.includes("&lt;b&gt;bold&lt;/b&gt;") &&
      !b.shadowRoot.innerHTML.includes("<b>bold</b>"),
  );

  // x-card: composition and live updates
  const k = new registry["x-card"]();
  k.connectedCallback();
  k.attributeChangedCallback("title", null, "T");
  k.attributeChangedCallback("body", null, "B");
  check(
    "the card renders title and body",
    k.shadowRoot.innerHTML.includes(">T</div>") && k.shadowRoot.innerHTML.includes(">B</div>"),
  );
  k.attributeChangedCallback("body", "B", "<i>x</i>");
  check("the card body is escaped as well", k.shadowRoot.innerHTML.includes("&lt;i&gt;x&lt;/i&gt;"));
}

// x-panel: light DOM mode
if (typeof registry["x-panel"] === "function") {
  const panel = new registry["x-panel"]();
  panel.connectedCallback();
  check("light mode creates no shadow root", !panel.shadowRoot);
  check(
    "light mode writes its content into the element itself",
    panel.innerHTML.includes("panel-title"),
    panel.innerHTML.slice(0, 120),
  );
  check(
    "styles are scoped to the tag name by scope_css (:host becomes x-panel)",
    panel.innerHTML.includes("x-panel { display: block; margin-top: 8px; }") &&
      !panel.innerHTML.includes(":host"),
  );
  check(
    "plain selectors get the tag name prefix too (the page's .pill is unaffected)",
    panel.innerHTML.includes("x-panel .pill { background: #eef2f7; color: #3b4453; }"),
  );
  panel.attributeChangedCallback("body", null, "updated");
  check("an attribute change re-renders in light mode too", panel.innerHTML.includes("updated"));
}

// The page itself is the acceptance artifact, but it cannot be rendered here, so check the
// page/bundle contract statically. These catch breakage that only shows up in a browser.
const htmlPath = fileURLToPath(new URL("./index.html", import.meta.url));
const html = readFileSync(htmlPath, "utf8");
// ignore the inline script when scanning for elements
const markup = html.replace(/<script[\s\S]*?<\/script>/g, "");
const GLOBAL_ATTRS = new Set([
  "id",
  "class",
  "style",
  "slot",
  "part",
  "role",
  "tabindex",
  "hidden",
  "dir",
  "lang",
  "draggable",
]);

const used = [...markup.matchAll(/<(x-[a-z0-9-]+)((?:\s+[^<>]*?)?)\s*>/g)];
const problems = [];
for (const [, tag, attrs] of used) {
  const ctor = registry[tag];
  if (typeof ctor !== "function") {
    problems.push(`<${tag}> is not registered`);
    continue;
  }
  const observed = new Set(ctor.observedAttributes || []);
  for (const m of attrs.matchAll(/([a-zA-Z][\w-]*)\s*=/g)) {
    const name = m[1];
    if (GLOBAL_ATTRS.has(name) || name.startsWith("data-") || name.startsWith("aria-")) continue;
    if (!observed.has(name)) problems.push(`<${tag}> sets "${name}", which is not observed`);
  }
}
check("the demo page uses custom elements", used.length > 0, `${used.length} tags`);
check(
  "every element and attribute used by the page is registered and observed",
  problems.length === 0,
  problems.join("; "),
);

const spec = html.match(/await import\("([^"]+)"\)/);
check(
  "the bundle the page imports exists after a build",
  !!spec && existsSync(fileURLToPath(new URL(spec[1], pathToFileURL(htmlPath)))),
  spec ? spec[1] : "no dynamic import found",
);

console.log(`\npassed ${passed}, failed ${failed}`);
process.exit(failed === 0 ? 0 : 1);
