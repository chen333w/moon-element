# moon-element

[![ci](https://github.com/chen333w/moon-element/actions/workflows/ci.yml/badge.svg)](https://github.com/chen333w/moon-element/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Standard Web Components in [MoonBit](https://www.moonbitlang.com/).

Components register as standard custom elements (`customElements.define`), so they can be embedded
in any page or framework (plain HTML / React / Vue) without a MoonBit-side framework runtime.

Status (2026-10-22): CI green; tests 65/65 (wasm, wasm-gc, native) and 90/90 (js); library line
coverage 96.5%.

## How it differs from a frontend framework

| | frontend framework (e.g. rabbita) | moon-element |
| --- | --- | --- |
| Shape | ships a virtual DOM and takes over the page | standard Web Components runtime, no framework dependency |
| Interop | renders inside the framework | browser-native: `customElements` / shadow DOM / lifecycle / attribute reflection |
| Host | whole-page application | a single `<x-badge>` in any existing page |

## Features

| Capability | Notes |
| --- | --- |
| Custom element registration | `define_component(tag, specs, render_fn)`; `observedAttributes` is derived from the attribute specs |
| Attribute reflection | `attribute` ↔ typed value; missing or invalid values fall back to the default (HTML semantics); booleans follow presence = true |
| Attribute name mapping | `max-count` ↔ `maxCount` in both directions; the MoonBit-side name is derived from the attribute name |
| Lifecycle | connect / disconnect / attribute-change / adoptedCallback state machine; repeated connects do not fire twice; reconnecting after disconnect works |
| Rendering | `View` tree → HTML string; text and attribute values are escaped by default; void elements get no closing tag; output is deterministic (snapshot-testable) |
| Render mode | `mode` selects shadow DOM (default, `:host` works) or light DOM (no shadow root, styles scoped to the tag name via `scope_css`) |
| Style declaration | `styles` declares component CSS once: injected as-is in shadow mode, prefixed with the scope in light mode |
| CSS scoping | `scope_css(css, scope)` rewrites a `:host` stylesheet into prefixed form |
| Events | declarative event specs (`crossing` = `bubbles + composed`, crosses the shadow boundary); call `dispatch` from `on_change` to notify the host page |
| CLI | `moon run cmd/main -- x-counter` generates a component skeleton; `--mode shadow\|light`; tag names validated against the HTML spec |

## Quick start

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

Defining a component (from [`examples/demo/main.mbt`](examples/demo/main.mbt)):

```mbt nocheck
///|
fn badge_view(props : @core.Props) -> @core.View {
  let label = props.get_string("label").unwrap_or("?")
  // VText is escaped: <b>hi</b> renders as literal text
  @core.View::element("span", [("class", "pill")], [@core.View::text(label)])
}

///|
pub fn register() -> Unit {
  @dom.define_component(
    "x-badge",
    [
      @core.AttrSpec::string("label", "?"),
      @core.AttrSpec::string("tone", "info"),
    ],
    badge_view,
    events=[@core.EventSpec::crossing("badge-changed")],
    on_change=fn(id, _name) { @dom.dispatch(id, "badge-changed", "", false) },
  )
}
```

In a page:

```html
<x-badge label="styled by the component" tone="info"></x-badge>
<script type="module" src="./your-bundle.js"></script>
```

Run the demo:

```bash
moon build --target js --release
python3 -m http.server 8000          # from the repository root
open http://localhost:8000/examples/demo/
```

Verify runtime behavior without a browser (loads the build artifact itself, 16 assertions):

```bash
node examples/demo/verify.mjs
```

## Commands

```bash
moon check --deny-warn --target all          # static checks on every backend (warnings fail)
moon test --target all --deny-warn           # tests on all four backends
moon test --target js --enable-coverage && moon coverage report -f summary
moon run cmd/main -- x-counter               # generate a component skeleton (shadow DOM)
moon run cmd/main -- x-panel --mode light    # generate a light DOM skeleton
moon build --target js --release             # produce browser-loadable JS
```

## Layout

```
core/    target-agnostic logic (attribute reflection, lifecycle, Props, rendering, CSS scoping,
         events, render modes, tag-name validation, skeleton generation)
dom/     js-only adapter (DOM callback wiring, shadow / light rendering, CustomEvent dispatch)
examples/demo/                 four components + interactive page + headless verification script
examples/generated-x-counter/      CLI output, shadow mode (compiled and drift-checked by CI)
examples/generated-light-panel/    CLI output, light mode (same)
cmd/main/          CLI (--mode shadow|light)
```

Rules live in `core` and the adapter only wires them up, so attribute parsing, fallback semantics
and lifecycle transitions are covered by ordinary unit tests on wasm / wasm-gc / native / js
without a browser.

## Testing and quality

- Unit tests on four backends: 65/65 (wasm, wasm-gc, native) and 90/90 (js)
- `install_dom_stub()` provides a minimal DOM stub (`attachShadow`, `CustomEvent`, event dispatch),
  so adapter logic is testable under node with no jsdom / happy-dom npm dependency
- `examples/demo/verify.mjs` imports the build artifact (the same file the browser loads) and runs
  16 assertions
- Generator drift check: the committed examples must match the current CLI output byte for byte
- Interface drift check: after `moon info`, `.mbti` files must show no diff and no untracked files
- Coverage: library 96.5% (688/713), whole repo 83.9% (704/839). Per-package numbers via
  `moon coverage report -f html -o /tmp/cov-html`: `core/` 95.9% (568/592), `dom/` 99.2% (120/121),
  generated examples 100%. The CLI entry point (0/30) and the demo (0/80) are integration paths,
  covered by artifact verification, the drift checks and CI compilation

## Known limitations

- Rendering replaces `shadowRoot.innerHTML` as a whole, with no diff; components should not attach
  DOM listeners internally (the next render replaces them) — put interaction in the page instead
- Tag-name validation accepts an ASCII subset only (the spec allows some non-ASCII)
- `::slotted()` / `:host-context()` are shadow DOM semantics and are not rewritten
- No threads / async support (MoonBit currently has no OS threads; async is complete on native only)

## Next

Per-element diffing, component-internal events, a DOM test fixture for `moon test --target js`.

## License

Apache-2.0, see [LICENSE](LICENSE).