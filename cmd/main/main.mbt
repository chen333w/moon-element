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
