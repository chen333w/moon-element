///|
/// moon-element CLI: generates a custom element skeleton.
///
/// Usage:
/// ```text
/// moon run cmd/main -- x-counter
/// moon run cmd/main -- --help
/// ```

///|
fn usage(cmd : @argparse.Command) -> Unit {
  println(cmd.render_help())
  println("")
  println("Examples:")
  println(
    "  moon run cmd/main -- x-counter                 # shadow DOM (default)",
  )
  println(
    "  moon run cmd/main -- x-panel --mode light      # light DOM + scope_css isolation",
  )
  println(
    "  moon run cmd/main -- layout --width 640        # lay the dashboard out without a browser",
  )
  println(
    "  moon run cmd/main -- layout --format svg       # ... and emit an SVG document",
  )
  println("")
  println(
    "Custom element name rules: must contain a hyphen; only lowercase letters,",
  )
  println(
    "digits, -, ., _; must not start or end with a hyphen; must not start with xml;",
  )
  println("must not be a reserved name.")
}

///|
fn run() -> Unit {
  let cmd = @argparse.Command(
    "moon-element",
    options=[
      @argparse.OptionArg(
        "mode",
        long="mode",
        about="Render mode: shadow (default) or light",
      ),
      @argparse.OptionArg(
        "width",
        long="width",
        about="Page width for `layout` (default 640)",
      ),
      @argparse.OptionArg(
        "format",
        long="format",
        about="`layout` output: json (default) or svg",
      ),
    ],
    positionals=[@argparse.PositionArg("tag")],
    about="Generate a MoonBit custom element skeleton (standard Web Components)",
  )
  let matches = cmd.parse() catch { _ => return usage(cmd) }
  // A misspelled --mode must fail: silently defaulting generates code the caller did not ask for
  let mode = if matches.values is { "mode": [raw, ..], .. } {
    match @core.RenderMode::parse(raw) {
      Some(m) => m
      None => {
        println("Error: --mode only accepts shadow or light, got \"\{raw}\"")
        println("")
        return usage(cmd)
      }
    }
  } else {
    @core.ShadowDom
  }
  if matches.values is { "tag": [tag, ..], .. } {
    if tag == "layout" {
      return run_layout(matches)
    }
    match @core.component_skeleton(tag, mode~) {
      // No trailing newline here (println adds one), so the written file matches what
      // moon fmt normalizes to; the CI drift check relies on that.
      Some(code) => println(code)
      None => {
        println("Error: \"\{tag}\" is not a valid custom element name.")
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

///|
/// 解析 CLI 里的非负小数（例如 640 或 640.5）；非法输入返回 None。
fn parse_number(raw : String) -> Double? {
  if raw.length() == 0 {
    return None
  }
  let mut seen_dot = false
  let mut digits = 0
  for ch in raw.iter() {
    if ch == '.' {
      if seen_dot {
        return None
      }
      seen_dot = true
    } else if ch >= '0' && ch <= '9' {
      digits = digits + 1
    } else {
      return None
    }
  }
  if digits == 0 {
    return None
  }
  let mut value = 0.0
  let mut scale = 1.0
  let mut after_dot = false
  for ch in raw.iter() {
    if ch == '.' {
      after_dot = true
      continue
    }
    let digit = (ch.to_int() - '0'.to_int()).to_double()
    if after_dot {
      scale = scale / 10.0
      value = value + digit * scale
    } else {
      value = value * 10.0 + digit
    }
  }
  Some(value)
}

///|
/// `layout`：把内置仪表盘布局成几何，输出确定性 JSON 或 SVG。
fn run_layout(matches : @argparse.Matches) -> Unit {
  let width = if matches.values is { "width": [raw, ..], .. } {
    match parse_number(raw) {
      Some(w) => w
      None => {
        println("Error: --width expects a positive number, got \"\{raw}\"")
        return
      }
    }
  } else {
    640.0
  }
  if width <= 0.0 {
    println("Error: --width must be greater than 0")
    return
  }
  let format = if matches.values is { "format": [raw, ..], .. } {
    raw
  } else {
    "json"
  }
  let (root, box) = @pipeline.run(
    @dashboard.dashboard_view(),
    @dashboard.dashboard_css(),
    width,
    @pipeline.measure_monospace,
  )
  if format == "json" {
    println(@svg.to_json(root, box))
  } else if format == "svg" {
    println(@svg.to_svg(root, box))
  } else {
    println("Error: --format only accepts json or svg, got \"\{format}\"")
  }
}
