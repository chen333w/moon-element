# moon-element

[![ci](https://github.com/chen333w/moon-element/actions/workflows/ci.yml/badge.svg)](https://github.com/chen333w/moon-element/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

用 [MoonBit](https://www.moonbitlang.com/) 写标准 Web Components。

组件以自定义元素（`customElements.define`）注册，可直接嵌进任意网页或框架
（原生 HTML / React / Vue），不需要 MoonBit 侧的前端框架运行时。

状态（2026-10-22）：CI 全绿；测试 65/65（wasm、wasm-gc、native）、90/90（js）；库本体行覆盖 96.5%。

## 与前端框架的区别

| | 前端框架（如 rabbita） | moon-element |
| --- | --- | --- |
| 形态 | 自带 virtual DOM，接管整个页面 | 标准 Web Components 运行时，无框架依赖 |
| 互操作 | 在框架内部渲染 | 浏览器原生：`customElements` / shadow DOM / 生命周期 / 属性反射 |
| 宿主 | 整页应用 | 任意页面里的一个 `<x-badge>` |

## 功能

| 能力 | 说明 |
| --- | --- |
| 自定义元素注册 | `define_component(tag, specs, render_fn)`；`observedAttributes` 由属性规格生成 |
| 属性反射 | `attribute` ↔ 类型化取值；缺失或非法一律回退默认值（对齐 HTML 语义）；布尔按「存在即真」 |
| 属性名映射 | `max-count` ↔ `maxCount` 双向转换；MoonBit 侧名字由属性名推导 |
| 生命周期 | 连接 / 断开 / 属性变化 / adoptedCallback 状态机；重复连接不重复触发；断开后可重连 |
| 渲染 | `View` 树 → HTML 字符串；文本与属性值默认转义；void 元素不加闭合标签；输出确定性（可快照） |
| 渲染模式 | `mode` 选 shadow DOM（默认，`:host` 可用）或 light DOM（不建 shadow root，样式用 `scope_css` 作用域到标签名） |
| 样式声明 | `styles` 声明组件 CSS：shadow 模式原样注入，light 模式自动加作用域前缀 |
| CSS 作用域 | `scope_css(css, scope)` 把 `:host` 样式表改写成前缀形式 |
| 事件 | 声明式事件规格（`crossing` = `bubbles + composed`，可穿 shadow 边界）；在 `on_change` 里调 `dispatch` 对外抛事件 |
| CLI | `moon run cmd/main -- x-counter` 生成组件骨架；`--mode shadow\|light`；元素名按 HTML 规范校验 |

## 快速开始

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

组件定义（来自 [`examples/demo/main.mbt`](examples/demo/main.mbt)）：

```mbt nocheck
///|
fn badge_view(props : @core.Props) -> @core.View {
  let label = props.get_string("label").unwrap_or("?")
  // VText 会转义：<b>hi</b> 渲染为字面文本
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

页面里：

```html
<x-badge label="受组件样式控制" tone="info"></x-badge>
<script type="module" src="./你的产物.js"></script>
```

跑 demo：

```bash
moon build --target js --release
python3 -m http.server 8000          # 在仓库根目录执行
open http://localhost:8000/examples/demo/
```

验证运行时行为（加载构建产物本身，16 项断言）：

```bash
node examples/demo/verify.mjs
```

## 命令

```bash
moon check --deny-warn --target all          # 全后端静态检查（警告即失败）
moon test --target all --deny-warn           # 四个后端上都跑测试
moon test --target js --enable-coverage && moon coverage report -f summary
moon run cmd/main -- x-counter               # 生成组件骨架（shadow DOM）
moon run cmd/main -- x-panel --mode light    # 生成 light DOM 骨架
moon build --target js --release             # 产出浏览器可加载的 JS
```

## 结构

```
core/    目标无关的纯逻辑（属性反射、生命周期、Props、渲染、CSS 作用域、事件、
         渲染模式、元素名校验、骨架生成）
dom/     js-only 适配层（DOM 回调接线、shadow / light 两种渲染、CustomEvent 派发）
examples/demo/                 四个组件 + 可交互页面 + 无头验证脚本
examples/generated-x-counter/      CLI 产物：shadow 模式（由 CI 编译与漂移检查验证）
examples/generated-light-panel/    CLI 产物：light 模式（同上）
cmd/main/          CLI（--mode shadow|light）
```

规则放在 `core`，适配层只负责接线，因此属性解析、回退语义、生命周期转换这些规则
可以在 wasm / wasm-gc / native / js 四个后端上跑普通单元测试，不需要浏览器。

## 测试与质量

- 四后端单元测试：65/65（wasm、wasm-gc、native）+ 90/90（js）
- `install_dom_stub()` 提供最小 DOM 桩（`attachShadow`、`CustomEvent`、事件派发），
  适配层逻辑在 node 下即可测试，不引入 jsdom / happy-dom 等 npm 依赖
- `examples/demo/verify.mjs` 直接 import 构建产物（浏览器加载的同一份文件）跑 16 项断言
- 生成器漂移检查：仓库里的示例必须与 CLI 当前产出逐字节一致
- 接口漂移检查：`moon info` 后校验 `.mbti` 无 diff、无未提交接口文件
- 覆盖率：库本体 96.5%（688/713），整仓 83.9%（704/839）。
  逐包数字用 `moon coverage report -f html -o /tmp/cov-html` 查看：`core/` 95.9%（568/592）、
  `dom/` 99.2%（120/121）、生成器产物示例各 100%。CLI 入口（0/30）与 demo（0/80）
  属集成路径，由产物级验证、漂移检查与 CI 编译覆盖

## 已知限制

- 渲染是整块 `shadowRoot.innerHTML` 替换，没有 diff；组件内部不适合挂 DOM 监听器（会被下次重渲染换掉），交互放在页面侧
- 元素名校验只接受 ASCII 子集（规范允许部分非 ASCII）
- `::slotted()` / `:host-context()` 属 shadow DOM 语义，未做等价转换
- 不支持多线程 / async（MoonBit 现状：无 OS 线程，async 仅 native 完整）

## 下一步

逐元素 diff、组件内部事件、`moon test --target js` 的 DOM 测试夹具。

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。