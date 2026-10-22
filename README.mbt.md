# moon-element

[![ci](https://github.com/chen333w/moon-element/actions/workflows/ci.yml/badge.svg)](https://github.com/chen333w/moon-element/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

用 [MoonBit](https://www.moonbitlang.com/) 写**标准 Web Components**。

组件以标准自定义元素（`customElements.define`）注册，因此可以直接嵌进**任意**网页或框架
（原生 HTML / React / Vue / 任何能写标签的地方），**不需要引入 MoonBit 侧的前端框架运行时**。

> 状态：**核心可用**（2026-10-22）
> CI 全绿 · 测试 wasm/wasm-gc/native **61/61**、js **82/82** · 库本体行覆盖 **96.2%**
> （数字为 2026-10-22 快照，复现命令见下文；提交记录连续、数量 ≥10，不写死以免每次提交都漂）

## 为什么不是「又一个前端框架」

| | 既有 MoonBit 前端框架（如 rabbita） | moon-element |
| --- | --- | --- |
| 形态 | 自带 virtual DOM 的**框架**，接管整个页面 | **标准 Web Components 运行时**，无框架依赖 |
| 互操作 | 需要在框架内部渲染 | 与浏览器原生一致：`customElements` / shadow DOM / 生命周期 / 属性反射 |
| 宿主 | 整页应用 | 任意既有页面里的一个 `<x-badge>` |

## 现在能做什么

| 能力 | 说明 |
| --- | --- |
| 自定义元素注册 | `define_component(tag, specs, render_fn)`；`observedAttributes` 由属性规格自动生成，不用手写 |
| 属性反射 | `attribute` ↔ 类型化取值；**缺失或非法一律回退默认值**（对齐 HTML 的宽松语义）；布尔按「存在即真」 |
| 属性名映射 | `max-count` ↔ `maxCount` 双向转换，MoonBit 侧名字由属性名推导，杜绝两处不一致 |
| 生命周期 | 连接 / 断开 / 属性变化 / adoptedCallback 状态机；重复连接不重复触发；断开后可重连 |
| 渲染 | `View` 树 → HTML 字符串；文本与属性值**默认转义**；void 元素不加闭合标签；输出确定性（可快照） |
| shadow DOM | 渲染结果写进 shadow root，样式天然隔离 |
| CSS 作用域 | `scope_css(css, scope)` 把 `:host` 样式表改写成前缀形式，供**不能上 shadow DOM** 的场合使用 |
| 事件 | 声明式事件规格（`crossing` = `bubbles + composed`，可穿 shadow 边界到宿主页面）；`on_change` 回调里 `dispatch` 即可对外抛事件 |
| CLI | `moon run cmd/main -- x-counter` 生成组件骨架；元素名按 HTML 规范校验 |

## 快速开始

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

写一个组件（这段代码来自 [`examples/demo/main.mbt`](examples/demo/main.mbt)）：

```mbt nocheck
///|
fn badge_view(props : @core.Props) -> @core.View {
  let label = props.get_string("label").unwrap_or("?")
  // label 走 VText，会被转义：用户传 <b>hi</b> 时看到的是字面文本
  @core.View::element("span", [("class", "pill")], [@core.View::text(label)])
}

///|
pub fn register() -> Unit {
  @dom.define_component(
    "x-badge",
    [
      @core.AttrSpec::string("label", "?"),
      @core.AttrSpec::string("tone", "info"),
    ],
    badge_view,
    events=[@core.EventSpec::crossing("badge-changed")],
    on_change=fn(id, _name) { @dom.dispatch(id, "badge-changed", "", false) },
  )
}
```

在页面里（任何页面、任何框架都可以）：

```html
<x-badge label="受组件样式控制" tone="info"></x-badge>
<script type="module" src="./你的产物.js"></script>
```

看完整 demo：

```bash
moon build --target js --release
python3 -m http.server 8000          # 在仓库根目录执行
open http://localhost:8000/examples/demo/
```

不想开浏览器也可以验证运行时行为（加载的是**构建产物本身**）：

```bash
node examples/demo/verify.mjs        # 11 项断言
```

## 命令

```bash
moon check --deny-warn --target all          # 全后端静态检查（警告即失败）
moon test --target all --deny-warn           # 四个后端上都跑测试
moon test --target js --enable-coverage && moon coverage report -f summary
moon run cmd/main -- x-counter               # 生成组件骨架
moon build --target js --release             # 产出浏览器可加载的 JS
```

## 架构：为什么切成 `core` 和 `dom`

```
core/    目标无关的纯逻辑（属性反射、生命周期、Props、渲染、CSS 作用域、事件、元素名校验）
dom/     js-only 适配层（真实 DOM 回调接线、shadow 渲染、CustomEvent 派发）
examples/demo/     三个真实组件 + 可交互页面 + 无头验证脚本
examples/generated-x-counter/   CLI 生成器的产物（提交进仓库，由 CI 编译验证）
cmd/main/          CLI
```

规则都在 `core`，适配层只负责接线。这样切的好处是**可测性**：属性解析、回退语义、
生命周期转换这些真正容易出错的规则，能在 `wasm` / `wasm-gc` / `native` / `js`
四个后端上跑普通单元测试，不需要浏览器。`dom` 里只剩「有没有接对」这一件事。

## 测试与质量

- **四后端单元测试**：61/61（wasm、wasm-gc、native）+ 82/82（js）
- **无浏览器也能测 DOM 行为**：`install_dom_stub()` 提供一个最小 DOM 桩（含 `attachShadow`、
  `CustomEvent`、事件派发），因此适配层逻辑在 node 下就能测，**不引入 jsdom/happy-dom 等 npm 依赖**
- **产物级验证**：`examples/demo/verify.mjs` 直接 import 构建产物（浏览器加载的同一份文件）跑断言
- **生成器漂移检查**：仓库里的示例必须与 CLI 当前产出逐字节一致，忘了重新生成 CI 就会红
- **接口漂移检查**：`moon info` 后校验 `.mbti` 无 diff、无未提交接口文件
- **覆盖率**：库本体（`core` + `dom`）行覆盖 **96.2%**（640/665）；计入 CLI 入口与 demo 的整仓数字为 84.9%（640/754）——后两者是集成路径，由「构建产物验证 + 生成器漂移检查 + CI 编译」覆盖，不计入单元测试分母

## 已知限制

- 渲染是**整块 `shadowRoot.innerHTML` 替换**，没有 diff。因此组件内部不适合挂 DOM 监听器（会被下次重渲染换掉），交互应放在页面侧；等引入逐元素 diff 或导出函数后再改
- 元素名校验只接受 ASCII 子集（规范允许部分非 ASCII，这里保守拒绝）
- `::slotted()` / `:host-context()` 属 shadow DOM 语义，未做等价转换
- 不支持多线程 / async（MoonBit 现状：无 OS 线程，async 仅 native 完整）——本库也不需要

## 路线图

1. ~~D0 可行性验证~~（[报告](docs/d0-assumptions.md)）
2. ~~属性反射 + 生命周期状态机 + Props~~
3. ~~渲染 + CSS 作用域（快照测试）~~
4. ~~DOM 适配层（注册 / 属性回调 / shadow 渲染）~~
5. ~~事件系统 + 骨架生成器 CLI~~
6. ~~demo 页（3 个组件）~~ + 发布到 mooncakes.io
7. 下一步：逐元素 diff、组件内部事件、`moon test --target js` 的 DOM 夹具

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。