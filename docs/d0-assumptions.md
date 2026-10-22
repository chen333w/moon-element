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

**做法**：构建 demo 的 js 产物，**直接 import 那个文件**（浏览器会加载的同一份），在 node 的最小 DOM 桩上断言真实行为。

**命令与真实输出**（2026-10-22 补测完成）：

```bash
$ moon build --target js --release
Finished. moon: ran 2 tasks, now up to date

$ node examples/demo/verify.mjs
moon-element demo 无头验证
产物: .../_build/js/release/build/examples/demo/demo.js
[moon-element] demo 组件已注册：x-counter / x-badge / x-card
  ok   构建产物可以被 ES 模块方式加载并执行
  ok   加载后三个自定义元素都已注册
  ok   observedAttributes 由属性规格生成
  ok   默认值生效（count=0, max=10）
  ok   合法属性被采用并重渲染
  ok   组件通过 crossing 事件通知页面（bubbles+composed）
  ok   进度条宽度按 count/max 计算
  ok   非法属性值回退默认值而不是报错
  ok   用户输入被转义，不会被当成标签执行
  ok   卡片渲染标题与正文
  ok   卡片正文同样走转义

通过 11，失败 0
```

**结论：✅ 成立。** 产物能被 ES 模块方式加载并执行，组件注册与运行时行为全部符合预期。该验证已接入 CI（`Build demo (js) and verify the artifact headlessly`）。

### 附带实测结论：`link.js.format` 对可执行包是 no-op

上一轮我写的「需要配置 `format: "esm"`」是**错的**：实测加上与不加上该选项，产物**逐字节相同**——可执行包的 js 产物既无 `export` 也无 `require`，是一段普通脚本（末尾自带自执行初始化）。该选项只在需要对外导出符号时才有意义。

这也解释了为什么浏览器能用：`<script type="module" src="...">` 对「无导出的脚本」同样有效，模块脚本并不要求必须有导出。所以 `examples/demo/moon.pkg` 里**故意不写**这个选项，以免误导。

---

## 附：本阶段的工程约定（后续沿用）

- 纯逻辑放 target-agnostic 包，js 相关的 FFI 集中在 `supported_targets = "js"` 的 `dom/` 包，避免污染全后端构建。
- 测试用无依赖的 `install_dom_stub()` 在 node 下跑通，不引入 jsdom/happy-dom 这类 npm 依赖；构建产物的真实行为由 `examples/demo/verify.mjs` 验证。
- 每次改动跑 `moon check --deny-warn --target all`，警告视为错误。
- 改过 `.github/workflows/*.yml` 必须本地校验 YAML：`ruby -ryaml -e 'YAML.load_file("...")'`（曾因步骤名里的 `": "` 把整个 workflow 打崩）。