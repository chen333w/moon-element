# 设计说明

记录关键决策与理由。

## 分层：core 与 dom

- 规则（属性解析、回退语义、生命周期、渲染、CSS 作用域、事件、渲染模式）放在 `core`；
  DOM 接线与实例状态放在 `dom`
- 动机：规则可在 wasm / wasm-gc / native / js 四个后端上跑普通单元测试，不需要浏览器；
  `dom` 只需验证「有没有接对」

## 跨 FFI 的取舍

- `extern "js"` 的回调参数用普通函数类型：`FuncRef[T]` 要求无捕获，而适配层需要把
  `specs` 与 `render_fn` 捕获进回调。详见 [feasibility](feasibility.md)
- 不传 `Option`：跨 FFI 表示不是稳定 ABI。属性老/新值用「存在性 `Bool` + `String`」传递
- 实例状态取出 → 修改 → 写回：不依赖结构体赋值是引用还是拷贝
- 实例注册表用按 id 索引的数组，id 由 JS 侧自增分配

## 属性与渲染

- 属性缺失或值非法 → 回退默认值（对齐 HTML 宽松语义）；布尔按「存在即真」；
  反射时 `false` 用「移除属性」表达
- 整数解析限制 9 位十进制数字：`Int` 宽度可能随后端而异，限制位数可避免静默溢出，
  让「不接受的值一律回退默认值」在四个后端上一致
- 渲染是整块 `shadowRoot.innerHTML` 替换，没有 diff。因此组件内部不挂 DOM 监听器
  （会被下次重渲染换掉），交互放在页面侧
- 样式通过 `styles` 声明一次：shadow 模式原样注入（`:host` 可用），light 模式先用
  `scope_css` 作用域到标签名
- light DOM 的隔离是**选择器优先级**级别的，压不过页面 `!important`，页面直接命中的
  规则也仍会生效；shadow DOM 是**结构性**隔离

## 生成器与 CI

- CLI 产物提交进仓库：CI 编译它，并检查「当前 CLI 产出 == 仓库文件」（漂移检查）
- 生成器产出已格式化的代码，避免与 `moon fmt` 的结果不一致
- 门禁：`moon check --deny-warn --target all`、四后端测试、接口漂移检查
  （`moon info` 后校验 `.mbti`）、生成器漂移检查、构建产物级验证

## 已知限制

- 无逐元素 diff；元素名校验只接受 ASCII 子集；`::slotted()` / `:host-context()` 未做
  等价转换；不支持多线程 / async（MoonBit 现状：无 OS 线程，async 仅 native 完整）

## 覆盖率

库本体 96.5%（688/713），整仓 83.9%（704/839）。未覆盖的主要是三类：防御性分支
（索引合法时 `String::get_char` 不返回 `None`）、内联造成的行号归属偏差、
以及 CLI 入口与 demo 这两条集成路径（由产物级验证、漂移检查与 CI 编译覆盖）。