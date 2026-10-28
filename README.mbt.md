# moon-element

[![ci](https://github.com/chen333w/moon-element/actions/workflows/ci.yml/badge.svg)](https://github.com/chen333w/moon-element/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![mooncakes](https://img.shields.io/badge/mooncakes-chen333w%2Fmoon--element-blue.svg)](https://mooncakes.io/docs/chen333w/moon-element)

Standard Web Components in [MoonBit](https://www.moonbitlang.com/). Components register with
`customElements.define`, so they work in any page or framework without a MoonBit-side runtime.

The same view tree can also be laid out **without a browser**: `style` computes the cascade,
`layout` computes geometry and `svg` serializes the result. That is useful for server-side
pre-layout, generating images in CI, and geometry regression tests. This is not a frontend
framework: it does not own the page, and it does not do signals or diffing.

## Quick start

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash   # MoonBit toolchain
moon add chen333w/moon-element                                  # this package
```

Published on [mooncakes.io](https://mooncakes.io/docs/chen333w/moon-element).

A component (from [`examples/demo/main.mbt`](examples/demo/main.mbt)):

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

Demo:

```bash
moon build --target js --release
python3 -m http.server 8000          # from the repository root
open http://localhost:8000/examples/demo/
```

Headless check of the built artifact (the same file the browser loads):

```bash
node examples/demo/verify.mjs
```

## Layout without a browser

```moonbit nocheck
let view = @core.View::element("div", [("class", "card")], [
  @core.View::element("h2", [], [@core.View::text("Total")]),
  @core.View::element("span", [("class", "num")], [@core.View::text("42")]),
])
let css = #|.card { display: flex; padding: 12px; gap: 8px; width: 100%; }
let (style_root, box) = @pipeline.run(view, css, 640.0, @pipeline.measure_monospace)
println(@svg.to_json(style_root, box))   // deterministic geometry, one line per box
println(@svg.to_svg(style_root, box))    // a standalone SVG document
```

Text width comes from an injected measurer, so the engine does not depend on a font stack:
`measure_monospace` is deterministic and good enough for tests, and a browser build can pass
`CanvasRenderingContext2D` metrics instead.

## API

| | |
| --- | --- |
| `define_component(tag, specs, render_fn, events~, on_change~, styles~, mode~)` | registers the element; `observedAttributes` comes from `specs` |
| `AttrSpec::string/int/double/bool(name, default)` | attribute spec; missing or invalid values fall back to the default, booleans are true when the attribute is present |
| `Props::get_string/get_int/get_double/get_bool/keys` | typed access inside the render function |
| `View::element/text/raw/fragment/nothing` | the view tree; text and attribute values are escaped, `VRaw` is not |
| `EventSpec::crossing(name)` / `contained(name)` | `crossing` = bubbles + composed, `contained` stays inside |
| `on_action=[(ActionSpec::new("click", "inc"), handler)]` | handles DOM events on elements marked `data-act="inc"` inside the component, including when a re-render has replaced them |
| `set_attribute` / `remove_attribute` | writes back to the component's own attributes, which re-renders it |
| `dispatch(id, name, detail, cancelable)` | sends an event from a component |
| `scope_css(css, scope)` | rewrites a `:host` stylesheet into prefixed form |
| `mode` | `ShadowDom` (default) or `LightDom`; in light mode `styles` is scoped to the tag name |
| `Stylesheet::parse(css)` / `compute(nodes)` | the cascade: selectors, specificity, `!important`, shorthand expansion, inheritance |
| `layout(root, width, measure)` | block flow and flexbox geometry as a tree of border boxes |
| `to_json` / `to_svg` | deterministic layout dump, and an SVG document |
| `pipeline::run(view, css, width, measure)` | the whole chain in one call |

Attribute names map both ways: `max-count` in HTML, `maxCount` in MoonBit.

## Commands

```bash
moon check --deny-warn --target all          # warnings are errors
moon test --target all --deny-warn           # wasm, wasm-gc, native, js
moon test --target js --enable-coverage && moon coverage report -f summary
moon run cmd/main -- x-counter               # generate a component skeleton (shadow DOM)
moon run cmd/main -- x-panel --mode light    # generate a light DOM skeleton
moon build --target js --release             # browser-loadable JS
moon run cmd/main -- layout --width 640      # lay the dashboard out headlessly (JSON)
moon run cmd/main -- layout --format svg     # ... or emit an SVG document
python3 examples/dashboard/verify_layout.py  # 18 checks over the CLI output
```

## Layout

```
core/    attribute parsing, lifecycle, props, rendering, CSS scoping, events, tag validation
dom/     js-only adapter: DOM callbacks, shadow/light rendering, CustomEvent dispatch
style/   CSS parsing, selector matching, cascade and computed values
layout/  box tree and flexbox geometry, with an injected text measurer
svg/     deterministic layout JSON and SVG output
pipeline/ view tree -> styled nodes -> geometry
examples/demo/                 four components, an interactive page and verify.mjs
examples/generated-*/          CLI output committed so CI compiles and drift-checks it
cmd/main/                      the CLI
```

Rules live in `core`, so they are unit-tested on every backend without a browser; `dom` only wires
them to the DOM. The adapter tests use a small in-repo DOM stub, so no npm dependencies are needed.

## Limitations

- Rendering replaces the content as a whole, with no diff. Keep state in attributes and handle DOM
  events with `on_action`: a listener attached to a rendered element is dropped by the next render.
- Tag name validation accepts an ASCII subset (the spec allows some non-ASCII).
- `::slotted()` and `:host-context()` are shadow DOM semantics and are not rewritten.
- No threads or async (MoonBit has no OS threads, and async is complete on native only).

The layout engine covers a subset of CSS:

- no adjacent-margin collapsing, no float, no absolute or relative positioning, no grid;
- text does not wrap: a run wider than its container overflows it;
- selectors cover type, class, id, compounds, descendant and child combinators, and lists; pseudo
  classes, attribute selectors, sibling combinators and `@media` blocks are skipped with a warning;
- percentages resolve against the containing block for box properties only, so percentage
  `padding`, `margin` and `gap` are treated as zero, and `gap` uses the row value.

Geometry is computed without a font stack or a browser, so it is not pixel-identical to a browser.
It is meant for pre-layout, image export and regression testing, not for replacing rendering.

## License

Apache-2.0, see [LICENSE](LICENSE).