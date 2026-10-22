///|
/// moon-element CLI：生成自定义元素骨架。
///
/// 用法：
/// ```text
/// moon run cmd/main -- x-counter
/// moon run cmd/main -- --help
/// ```
///
/// 生成逻辑在 `core/skeleton.mbt`，这里只负责参数解析与打印。

///|
fn usage(cmd : @argparse.Command) -> Unit {
  println(cmd.render_help())
  println("")
  println("示例：")
  println(
    "  moon run cmd/main -- x-counter                 # shadow DOM（默认）",
  )
  println(
    "  moon run cmd/main -- x-panel --mode light      # light DOM + scope_css 隔离",
  )
  println("")
  println(
    "自定义元素名规则：必须含连字符；只用小写字母、数字、-、.、_；",
  )
  println(
    "不能以连字符开头或结尾；不能以 xml 开头；不能是保留名。",
  )
}

///|
fn run() -> Unit {
  let cmd = @argparse.Command(
    "moon-element",
    options=[
      @argparse.OptionArg(
        "mode",
        long="mode",
        about="渲染模式：shadow（默认）或 light",
      ),
    ],
    positionals=[@argparse.PositionArg("tag")],
    about="生成 MoonBit 自定义元素骨架（标准 Web Components）",
  )
  let matches = cmd.parse() catch { _ => return usage(cmd) }
  // --mode 拼错必须报错：静默取默认值会让生成出来的代码与预期不符
  let mode = if matches.values is { "mode": [raw, ..], .. } {
    match @core.RenderMode::parse(raw) {
      Some(m) => m
      None => {
        println(
          "错误：--mode 只接受 shadow 或 light，收到 \"\{raw}\"",
        )
        println("")
        return usage(cmd)
      }
    }
  } else {
    @core.ShadowDom
  }
  if matches.values is { "tag": [tag, ..], .. } {
    match @core.component_skeleton(tag, mode~) {
      // 生成内容不带尾换行（由 println 补一个），写进文件后恰好一个结尾换行，
      // 与 moon fmt 规范化后的结果一致，CI 的漂移检查才有意义。
      Some(code) => println(code)
      None => {
        println("错误：\"\{tag}\" 不是合法的自定义元素名。")
        println("")
        usage(cmd)
      }
    }
  } else {
    usage(cmd)
  }
}

///|
fn main {
  run()
}
