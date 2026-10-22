// 无头验证脚本：在 node 里加载**构建产物**，验证它真的能注册组件并正常工作。
//
// 这是 D0 假设 3（"MoonBit 产出的 JS 能被外部加载运行"）的实测证据：
// 不经过 moon test，而是直接 import 浏览器会加载的那个文件。
//
// 用法（仓库根目录）：
//   moon build --target js --release
//   node examples/demo/verify.mjs
//
// 退出码 0 表示全部通过，1 表示有断言失败。

import { pathToFileURL } from "node:url";

// ---------------------------------------------------------------------------
// 最小 DOM 桩（与 dom/element_ffi.mbt 里的 install_dom_stub 等价，这里是浏览器侧的替代品）
// ---------------------------------------------------------------------------
function installDomStub() {
  if (globalThis.customElements) return;
  globalThis.HTMLElement = class HTMLElement {};
  globalThis.HTMLElement.prototype.attachShadow = function (opts) {
    this.shadowRoot = {
      innerHTML: "",
      host: this,
      mode: (opts && opts.mode) || "open",
    };
    return this.shadowRoot;
  };
  globalThis.HTMLElement.prototype.addEventListener = function (type, fn) {
    if (!this.__listeners) this.__listeners = Object.create(null);
    (this.__listeners[type] || (this.__listeners[type] = [])).push(fn);
  };
  globalThis.HTMLElement.prototype.dispatchEvent = function (ev) {
    const list = (this.__listeners && this.__listeners[ev.type]) || [];
    for (const fn of list) fn(ev);
    return !ev.defaultPrevented;
  };
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

// ---------------------------------------------------------------------------
// 极简断言
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// 开始
// ---------------------------------------------------------------------------
const bundlePath = new URL(
  "../../_build/js/release/build/examples/demo/demo.js",
  import.meta.url,
);

console.log("moon-element demo 无头验证");
console.log(`产物: ${bundlePath.pathname}`);

installDomStub();

// 关键一步：直接 import 构建产物（浏览器里就是 <script type="module" src="....js">）
let importError = null;
try {
  await import(pathToFileURL(bundlePath.pathname).href);
} catch (e) {
  importError = e;
}
check("构建产物可以被 ES 模块方式加载并执行", importError === null, String(importError));

const registry = globalThis.__stubRegistry || {};
check(
  "加载后四个自定义元素都已注册",
  ["x-counter", "x-badge", "x-card", "x-panel"].every((t) => typeof registry[t] === "function"),
  Object.keys(registry).join(","),
);

if (typeof registry["x-counter"] === "function") {
  check(
    "observedAttributes 由属性规格生成",
    JSON.stringify(registry["x-counter"].observedAttributes) ===
      JSON.stringify(["count", "max", "label"]),
    JSON.stringify(registry["x-counter"].observedAttributes),
  );

  // —— x-counter：属性反射 + 渲染 ——
  const c = new registry["x-counter"]();
  c.connectedCallback();
  check(
    "默认值生效（count=0, max=10）",
    c.shadowRoot.innerHTML.includes(">0</div>"),
    c.shadowRoot.innerHTML.slice(0, 120),
  );

  const events = [];
  c.addEventListener("count-changed", (ev) => events.push(ev));

  c.attributeChangedCallback("count", null, "7");
  check("合法属性被采用并重渲染", c.shadowRoot.innerHTML.includes(">7</div>"));
  check(
    "组件通过 crossing 事件通知页面（bubbles+composed）",
    events.length === 1 && events[0].bubbles === true && events[0].composed === true,
    JSON.stringify(events.map((e) => ({ t: e.type, b: e.bubbles, c: e.composed }))),
  );
  check("进度条宽度按 count/max 计算", c.shadowRoot.innerHTML.includes("width:70%"));

  c.attributeChangedCallback("count", "7", "abc");
  check(
    "非法属性值回退默认值而不是报错",
    c.shadowRoot.innerHTML.includes(">0</div>"),
    c.shadowRoot.innerHTML.match(/>-?\d+<\/div>/)?.[0],
  );

  // —— x-badge：HTML 转义 ——
  const b = new registry["x-badge"]();
  b.connectedCallback();
  b.attributeChangedCallback("label", null, "<b>加粗</b>");
  check(
    "用户输入被转义，不会被当成标签执行",
    b.shadowRoot.innerHTML.includes("&lt;b&gt;加粗&lt;/b&gt;") &&
      !b.shadowRoot.innerHTML.includes("<b>加粗</b>"),
  );

  // —— x-card：组合与实时更新 ——
  const k = new registry["x-card"]();
  k.connectedCallback();
  k.attributeChangedCallback("title", null, "T");
  k.attributeChangedCallback("body", null, "B");
  check(
    "卡片渲染标题与正文",
    k.shadowRoot.innerHTML.includes(">T</div>") && k.shadowRoot.innerHTML.includes(">B</div>"),
  );
  // 反转义由浏览器负责；这里只确认保留的是转义文本
  k.attributeChangedCallback("body", "B", "<i>x</i>");
  check("卡片正文同样走转义", k.shadowRoot.innerHTML.includes("&lt;i&gt;x&lt;/i&gt;"));
}

// —— x-panel：light DOM 模式（没有 shadow root，样式被 scope_css 作用域到标签名）——
if (typeof registry["x-panel"] === "function") {
  const panel = new registry["x-panel"]();
  panel.connectedCallback();
  check("light 模式不创建 shadow root", !panel.shadowRoot);
  check(
    "light 模式的内容写在元素自身",
    panel.innerHTML.includes("panel-title"),
    panel.innerHTML.slice(0, 120),
  );
  check(
    "样式被 scope_css 作用域到标签名（:host 变成 x-panel）",
    panel.innerHTML.includes("x-panel { display: block; margin-top: 8px; }") &&
      !panel.innerHTML.includes(":host"),
  );
  check(
    "普通选择器也加了标签名前缀（不会污染页面的 .pill）",
    panel.innerHTML.includes("x-panel .pill { background: #eef2f7; }"),
  );
  panel.attributeChangedCallback("body", null, "更新");
  check("light 模式属性变化同样重渲染", panel.innerHTML.includes("更新"));
}

console.log(`\n通过 ${passed}，失败 ${failed}`);
process.exit(failed === 0 ? 0 : 1);