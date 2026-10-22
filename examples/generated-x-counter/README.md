# 生成器产出的示例组件

本目录内容由 CLI 生成并提交，用于让 CI 持续验证骨架生成器的产物能编译。

重新生成：

```bash
moon run cmd/main -- x-counter > examples/generated-x-counter/component.mbt
```

`import` 属于包配置，依赖写在同目录的 `moon.pkg` 里，生成结果中只以注释提示。