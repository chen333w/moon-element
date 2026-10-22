# light DOM 模式的生成器产物

由 CLI **实际生成**并提交，让 CI 持续验证「light 模式的骨架也能编译、也能用」：

```bash
moon run cmd/main -- x-light-panel --mode light > examples/generated-light-panel/component.mbt
```

它与 [`../generated-x-counter`](../generated-x-counter) 的区别只有一处：
生成代码里多了 `mode=@core.LightDom`，于是内容不渲染进 shadow root，
而是渲染进元素自身、样式由 `core.scope_css` 作用域到 `x-light-panel`。
