# 生成器产出的示例组件

这个目录的内容由 CLI **实际生成**，并**提交进仓库**，目的是让 CI 持续验证
「骨架生成器的产物确实能编译」——如果生成器改坏了，CI 会红。

重新生成：

```bash
moon run cmd/main -- x-counter > examples/generated-x-counter/component.mbt
```

（`import` 属于包配置，所以依赖写在同目录的 `moon.pkg` 里，生成结果里只以注释提示。）
