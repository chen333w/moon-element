# demo · 用 MoonBit 写的标准 Web Components

四个组件 + 一个可交互页面 + 一个无头验证脚本。

## 怎么跑

```bash
# 1) 在仓库根目录构建 js 产物
moon build --target js --release

# 2) 起本地 HTTP 服务（ES 模块不能用 file:// 直接打开）
python3 -m http.server 8000

# 3) 浏览器打开
open http://localhost:8000/examples/demo/
```

跳过浏览器，直接验证运行时行为：

```bash
node examples/demo/verify.mjs
```

它加载构建产物（页面加载的同一个文件），在 node 的最小 DOM 桩上断言组件注册、属性反射、
非法值回退、HTML 转义、事件派发、light DOM 渲染，共 16 项。

## 页面上能看到什么

| 区域 | 演示的能力 |
| --- | --- |
| 1 · 计数器 | 属性驱动重渲染（`el.setAttribute("count", n)`）、非法值回退默认值、通过 `crossing` 事件（`bubbles + composed`）通知页面 |
| 2 · 徽章 | shadow DOM 样式隔离：页面给 `.pill` / `span` 定了很强的样式，组件内部不受影响 |
| 3 · 转义 | 把 `label` 设成 `<b>加粗</b>`，渲染为字面文本 |
| 4 · 卡片 | 组合结构 + 实时更新（输入框改 `body` 属性） |
| 5 · light DOM 面板 | `mode=LightDom` + `styles`：适配层用 `scope_css` 把选择器前缀成 `x-panel ...` |

数据流是单向的：页面改属性 → 组件重渲染 → 组件抛事件 → 页面收到。组件内部不挂 DOM 监听器
（渲染是整块 `innerHTML` 替换，内部监听器会随重渲染丢失），交互按钮放在页面侧。

## 两种隔离模式的差别

| | shadow DOM（默认） | light DOM |
| --- | --- | --- |
| 隔离方式 | 结构性：页面 CSS 进不到 shadow root | 优先级：选择器被前缀成 `x-panel .pill`，优先级高于页面 `.pill` |
| `:host` | 直接可用 | 由 `scope_css` 改写成标签名 |
| 页面 `!important` | 无效（进不来） | 有效（会压过组件规则） |
| 页面普通规则 | 无效 | 直接命中的仍会生效（例如 `span { letter-spacing }`） |
| 适用 | 组件样式自治 | SSR 输出、需要宿主样式透入 |

## `link.js.format` 对可执行包是 no-op

实测（`moon 0.1.20261020`）：加上与不加上 `link: { "js": { "format": "esm" } }`，产物逐字节相同。
可执行包的 js 产物既无 `export` 也无 `require`，是普通脚本。

浏览器仍能用 `<script type="module" src="./demo.js">` 加载：模块脚本不要求必须有导出，
产物末尾的自执行初始化会照常运行。`moon.pkg` 因此不写该选项。