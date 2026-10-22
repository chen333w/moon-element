# light DOM 模式的生成器产物

由 CLI 生成并提交，让 CI 验证 light 模式骨架同样能编译、能运行。

```bash
moon run cmd/main -- x-light-panel --mode light > examples/generated-light-panel/component.mbt
```

与 [`../generated-x-counter`](../generated-x-counter) 的区别：生成代码多一行 `mode=@core.LightDom`，
内容不渲染进 shadow root，而是渲染进元素自身，样式由 `core.scope_css` 作用域到 `x-light-panel`。