# moon-element

用 [MoonBit](https://www.moonbitlang.com/) 写**标准 Web Components**。

目标是让 MoonBit 产出的组件以自定义元素（`customElements.define`）的形式，直接嵌入**任意**网页、任意框架（React / Vue / 原生 HTML），不需要引入任何 MoonBit 侧的前端框架运行时。

> 状态：**D0 可行性验证阶段**（2026-10）。已有可运行证据见 [`docs/d0-assumptions.md`](docs/d0-assumptions.md)。

## 为什么不是「又一个前端框架」

| | 既有 MoonBit 前端框架（如 rabbita） | moon-element |
| --- | --- | --- |
| 形态 | 自带 virtual DOM 的**框架**，接管整个页面 | **标准 Web Components 运行时**，无框架依赖 |
| 互操作 | 需要在框架内部渲染 | 与浏览器原生一致：`customElements` / shadow DOM / 生命周期 / 属性反射 |
| 宿主 | 整页应用 | 任意既有页面里的一个 `<my-widget>` |

## 设计边界（刻意做小）

- **做**：自定义元素注册、属性（attribute ↔ typed prop）反射、生命周期状态机、shadow DOM 样式作用域、事件描述与委托、字符串渲染与最小 diff。
- **不做**：路由、全局状态管理、服务端框架、编译期新语法。
- 依赖数保持 ≤2；不依赖运行时反射；不需要 async / 线程。

## 目录结构

```
moon-element/
├─ moon.mod              # 模块元数据
├─ dom/                  # js-only：浏览器适配层（supported_targets = "js"）
│   ├─ element_ffi.mbt   # 自定义元素注册与 DOM 回调桥
│   └─ element_ffi_test.mbt
├─ cmd/main/             # CLI 入口
└─ docs/                 # 设计记录与验证报告
```

后续会加入 `core/`：target-agnostic 的纯逻辑包（属性反射、生命周期、渲染、CSS 作用域、事件），用 `moon test --target all` 在全部后端上验证。

## 快速开始

安装工具链：

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

在项目根目录运行：

```bash
moon check --deny-warn --target all   # 全后端静态检查
moon test --target js                 # 浏览器适配层的测试
moon build --target js                # 产出 JavaScript
```

## 使用形态（API 草图）

```mbt nocheck
// 注册一个自定义元素：connectedCallback 会进入 MoonBit 逻辑
@dom.install_dom_stub()   // 浏览器里不需要（真实 DOM 已存在时是 no-op）
@dom.define_element("hello-badge", fn () { println("connected") })
```

## 路线图

1. **D0（已完成）**：验证 JS 后端可注册真正继承 `HTMLElement` 的类，且回调能进 MoonBit。
2. `core/` 纯逻辑包 + 全后端测试。
3. 属性反射与生命周期状态机的边界用例。
4. shadow DOM 样式作用域 + 事件系统。
5. CLI 组件骨架生成器。
6. 浏览器 demo 页（3 个组件示例）+ 发布 mooncakes.io。

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。