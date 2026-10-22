# demo · 用 MoonBit 写的标准 Web Components

三个真实组件 + 一个可交互页面 + 一个无头验证脚本。

## 怎么跑

```bash
# 1) 在仓库根目录构建 js 产物
moon build --target js --release

# 2) 起一个本地 HTTP 服务（ES 模块不能用 file:// 直接打开）
python3 -m http.server 8000

# 3) 浏览器打开
open http://localhost:8000/examples/demo/
```

想跳过浏览器、直接验证运行时行为：

```bash
node examples/demo/verify.mjs
```

它会加载**构建产物**（就是页面加载的那个文件），在 node 的最小 DOM 桩上断言
组件注册、属性反射、非法值回退、HTML 转义、事件派发——11 项断言。

## 页面上能看到什么

| 区域 | 演示的能力 |
| --- | --- |
| 1 · 计数器 | 属性驱动重渲染（`el.setAttribute("count", n)`）、**非法值回退默认值**、组件通过 `crossing` 事件（`bubbles + composed`）通知页面 |
| 2 · 徽章 | **shadow DOM 样式隔离**：页面给 `.pill` / `span` 定了很霸道的样式，组件内部完全不受影响 |
| 3 · 转义 | 把 `label` 设成 `<b>加粗</b>`，渲染出来是**字面文本**，不会被当标签执行 |
| 4 · 卡片 | 组合结构 + 实时更新（输入框改 `body` 属性） |
| 5 · light DOM 面板 | **不用 shadow DOM 的隔离**：`mode=LightDom` + `styles`，适配层用 `scope_css` 把选择器前缀成 `x-panel ...` |

数据流是单向的：**页面改属性 → 组件重渲染 → 组件抛事件 → 页面收到**。
组件内部不挂 DOM 监听器（渲染用 `innerHTML` 替换，内部监听器会随重渲染丢失），
所以交互按钮放在页面（light DOM）里。

## 两种隔离模式的机制差别（重要）

| | shadow DOM（默认） | light DOM |
| --- | --- | --- |
| 隔离方式 | **结构性**：页面 CSS 根本进不到 shadow root | **优先级**：选择器被前缀成 `x-panel .pill`，优先级高于页面 `.pill` |
| `:host` | 直接可用 | 由 `scope_css` 改写成标签名 |
| 页面 `!important` | 无效（进不来） | **有效**（会压过组件规则） |
| 页面普通规则 | 无效 | 直接命中的仍会生效（例如 `span { letter-spacing }`） |
| 适用 | 组件样式完全自治 | SSR 输出、需要宿主样式透入 |

理解这条差别，就不会把 light DOM 当成"shadow DOM 的等价替代"。页面第 5 节
把这一点也写在页面上了。

## 一个实测结论：`link.js.format` 对可执行包是 no-op

直觉上应该写：

```text
options(
  link: { "js": { "format": "esm" } },
)
```

但实测（2026-10-22，`moon 0.1.20261020`）**不写也一样**：可执行包的 js 产物
既没有 `export` 也没有 `require`，是一段普通脚本；加上这个选项后产物**逐字节相同**。
该选项应当只在需要对外导出符号时才起作用。

所以这里**故意不写**它——留着会让人以为它起了作用。

那浏览器怎么加载？`<script type="module" src="./demo.js">` 对「无导出的脚本」同样有效
（模块脚本不要求必须有导出），产物里那行自执行的初始化会照常跑。页面用的就是这种方式。

## 为什么组件不自己渲染按钮并绑定事件

因为我们的渲染是「整块 `shadowRoot.innerHTML` 替换」。如果组件内部给按钮挂了监听器，
下一次重渲染就把监听器一起换掉了。等后续迭代引入 `#export_name` 或逐元素 diff 之后，
组件内部事件才是干净的。现在把交互放在页面侧，是**当前实现下正确的做法**，
而不是回避问题。