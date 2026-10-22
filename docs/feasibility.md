# 可行性验证记录

日期：2026-10-21（假设 3 补测于 2026-10-22）｜ 工具链：`moon 0.1.20261020` ｜ 机器：macOS arm64

选题「MoonBit Web Component 运行时」的前提是：MoonBit 的 JS 后端能把一个真正继承
`HTMLElement` 的类注册进自定义元素注册表，并且 DOM 回调能回到 MoonBit 代码。以下三条
假设在写核心功能之前验证，各记录「做法 / 命令 / 输出 / 结论」。

## 假设 1：JS 后端能注册真正继承 `HTMLElement` 的自定义元素

**做法**：在 `dom/element_ffi.mbt` 里用 `extern "js"` 内联 JS 定义
`class MoonElement extends globalThis.HTMLElement` 并调用 `customElements.define`；
探针返回 `ctor.prototype instanceof HTMLElement`。

```bash
$ moon check --target js
Finished. moon: ran 2 tasks, now up to date

$ moon test --target js
Total tests: 2, passed: 2, failed: 0.
```

**结论：成立。** 测试先断言未注册时为 `false`，注册后为 `true`，即原型链确实扎根于
`HTMLElement`（Custom Elements 注册表的硬性要求，普通类不满足）。

## 假设 2：DOM 回调能进入 MoonBit 代码

**做法**：把 MoonBit 函数作为回调传给类；探针触发 `connectedCallback` 两次，断言计数增加 2。

```bash
$ moon test --target js
Total tests: 2, passed: 2, failed: 0.
```

**结论：成立。** DOM → MoonBit 方向可用。

### 附带结论：JS 后端的回调参数用普通函数类型

写成 `FuncRef[() -> Unit]` 编译失败：

```
Error: [4014] Expr Type Mismatch
  has type : () -> Unit
  wanted   : FuncRef[() -> Unit]
```

`extern "js"` 函数取值为值时类型是普通函数类型，`FuncRef[T]` 用于无捕获闭包。FFI 文档对
JS 后端写着「JavaScript supports closure, so there's nothing special to be done here」。
改用普通函数类型后编译与运行均正常。适配层依赖这一点（它要把 `specs` 与 `render_fn`
捕获进回调）；若将来复用到 Wasm 后端，需要另行评估 `FuncRef` 与 `make_closure`。

## 假设 3：MoonBit 产出的 JS 可被外部加载

**做法**：构建 demo 的 js 产物，直接 import 该文件（浏览器加载的同一份），在 node 的最小
DOM 桩上断言运行时行为。

```bash
$ moon build --target js --release
Finished. moon: ran 2 tasks, now up to date

$ node examples/demo/verify.mjs
moon-element demo 无头验证
产物: .../_build/js/release/build/examples/demo/demo.js
[moon-element] demo 组件已注册：x-counter / x-badge / x-card / x-panel（light DOM）
  ok   构建产物可以被 ES 模块方式加载并执行
  ok   加载后四个自定义元素都已注册
  ok   observedAttributes 由属性规格生成
  ok   非法属性值回退默认值而不是报错
  ok   用户输入被转义，不会被当成标签执行
  ok   light 模式不创建 shadow root
  ok   样式被 scope_css 作用域到标签名（:host 变成 x-panel）
  ...
通过 16，失败 0
```

**结论：成立。** 产物可被 ES 模块方式加载执行，组件注册与运行时行为符合预期。
该验证已接入 CI（`Build demo and verify the artifact headlessly`）。

### 附带结论：`link.js.format` 对可执行包是 no-op

实测：加上与不加上 `link: { "js": { "format": "esm" } }`，产物逐字节相同。可执行包的
js 产物既无 `export` 也无 `require`，是普通脚本（末尾自带自执行初始化）。该选项只在需要
对外导出符号时才有意义。

浏览器侧能加载是因为 `<script type="module" src="...">` 对无导出的脚本同样有效，
模块脚本不要求必须有导出。`examples/demo/moon.pkg` 因此不写该选项。

## 工程约定

- 纯逻辑放 target-agnostic 包；js FFI 集中在 `supported_targets = "js"` 的 `dom/` 包，
  避免污染全后端构建。
- 适配层测试用无依赖的 `install_dom_stub()` 在 node 下跑通，不引入 jsdom / happy-dom；
  构建产物的真实行为由 `examples/demo/verify.mjs` 验证。
- 每次改动跑 `moon check --deny-warn --target all`，警告视为错误。
- 改过 `.github/workflows/*.yml` 必须校验 YAML：
  `ruby -ryaml -e 'YAML.load_file("...")'`。步骤名含 `": "` 会使整个 workflow 无法解析。