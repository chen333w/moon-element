# D0 致命假设验证报告

日期：**2026-10-21** ｜ 工具链：`moon 0.1.20261020 (2284bd2 2026-10-20)` ｜ 机器：macOS arm64（Darwin 25.6.0）

选题「MoonBit Web Component 运行时」成立的前提，是 MoonBit 的 JS 后端能把一个**真正继承 `HTMLElement` 的类**注册进浏览器的自定义元素注册表，并且 DOM 回调能回到 MoonBit 代码。若这条路径不通，整个选题要换成降级方案（渲染/SSR 子集）。

下面三条假设在动手写核心功能**之前**验证，每条都记录「假设 / 做法 / 实际命令 / 真实输出 / 结论」。

---

## 假设 1：JS 后端能注册真正继承 `HTMLElement` 的自定义元素

**做法**：在 `dom/element_ffi.mbt` 里用 `extern "js"` 内联 JS 定义一个 `class MoonElement extends globalThis.HTMLElement`，并调用 `customElements.define(name, MoonElement)`；再用一个探针函数返回 `ctor.prototype instanceof HTMLElement`。

**命令与真实输出**：

```bash
$ moon check --target js
Finished. moon: ran 2 tasks, now up to date

$ moon test --target js
Total tests: 2, passed: 2, failed: 0.
```

**结论：✅ 成立。** 测试 `d0: js 后端可注册真正继承 HTMLElement 的自定义元素` 先断言未注册时为 `false`，注册后为 `true`——即原型链确实扎根于 `HTMLElement`（这是 Custom Elements 注册表的硬性要求，而不是随便一个类）。

---

## 假设 2：DOM 回调能进入 MoonBit 代码

**做法**：把 MoonBit 函数作为回调传给类；探针触发 `connectedCallback` 两次，断言 MoonBit 侧标记计数增加 2。

**命令与真实输出**：

```bash
$ moon test --target js
Total tests: 2, passed: 2, failed: 0.
```

**结论：✅ 成立。** 测试 `d0: 自定义元素回调能进 MoonBit` 通过，证明 DOM → MoonBit 的方向可用。

### 过程中发现的一个真实约束（值得记录）

第一次尝试把回调参数写成 `FuncRef[() -> Unit]`，编译失败：

```
Error: [4014] Expr Type Mismatch
  has type : () -> Unit
  wanted   : FuncRef[() -> Unit]
```

原因是 `extern "js"` 函数取值为值时其类型是普通函数类型，而非 `FuncRef`。而官方 FFI 文档对 JS 后端明确写着「JavaScript supports closure, so there's nothing special to be done here」，`FuncRef[T]` 是为无捕获闭包准备的、且 ABI 为 `Function`。于是**改用普通函数类型 `() -> Unit`**，编译通过、运行正确。

> 这条约束会写进适配层的设计：JS 后端用普通闭包，未来的 Wasm/GC 后端若要复用同一层，需要另行评估 `FuncRef` 与 `make_closure` 的差异。

---

## 假设 3：MoonBit 产出的 JS 可被外部加载

**做法**：构建 js 产物并在 node 中运行入口；检查产物形态。

**命令与真实输出**：

```bash
$ moon build --target js
Finished. moon: ran 2 tasks, now up to date

$ moon run cmd/main --target js
Hello

$ find _build -name "*.js" | head
_build/js/debug/build/cmd/main/main.js
```

**结论：🟡 部分验证。** 产物存在于 `_build/js/debug/build/cmd/main/main.js`，node 可直接运行。**但**「浏览器 `<script type="module">` 直接加载」这一条尚未验证：默认产物是普通（非 ESM）脚本，需要在可执行包上配置 `link: { "js": { "format": "esm" } }` 并生成 demo 页后复验。

后续动作：在做 demo 页那一步补齐 `format = "esm"` 的真实产物验证；若受阻，用 IIFE 产物 + 一段薄加载脚本兜底（不影响选题成立）。

---

## 附：本阶段的工程约定（后续沿用）

- 纯逻辑放 target-agnostic 包，js 相关的 FFI 集中在 `supported_targets = "js"` 的 `dom/` 包，避免污染全后端构建。
- 测试用无依赖的 `install_dom_stub()` 在 node 下跑通，不引入 jsdom/happy-dom 这类 npm 依赖；真实浏览器行为另用 demo 页验证。
- 每次改动跑 `moon check --deny-warn --target all`，警告视为错误。