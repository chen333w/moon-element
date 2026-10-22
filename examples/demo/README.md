# demo · standard Web Components in MoonBit

Four components, one interactive page, one headless verification script.

## Running it

```bash
# 1) build the js artifact from the repository root
moon build --target js --release

# 2) serve it locally (ES modules cannot load over file://)
python3 -m http.server 8000

# 3) open it in a browser
open http://localhost:8000/examples/demo/
```

To verify runtime behaviour without a browser:

```bash
node examples/demo/verify.mjs
```

It imports the build artifact (the same file the page loads) and asserts component
registration, attribute reflection, fallback for invalid values, HTML escaping, event
dispatch, and light DOM rendering on a minimal DOM stub: 16 checks in total.

## What the page shows

| Section | Capability |
| --- | --- |
| 1 · counter | attribute-driven re-rendering (`el.setAttribute("count", n)`), fallback to the default for invalid values, notification through a `crossing` event (`bubbles + composed`) |
| 2 · badge | shadow DOM style isolation: the page sets strong styles on `.pill` / `span`, the component is unaffected |
| 3 · escaping | set `label` to `<b>bold</b>`, it renders as literal text |
| 4 · card | composed structure with live updates (the input drives the `body` attribute) |
| 5 · light DOM panel | `mode=LightDom` + `styles`: the adapter prefixes selectors with `scope_css` to `x-panel ...` |

Data flows one way: page sets attribute → component re-renders → component emits event →
page receives it. Components attach no DOM listeners (re-rendering replaces the whole
`innerHTML` and would drop them), so the interactive controls live on the page side.

## The two isolation modes

| | shadow DOM (default) | light DOM |
| --- | --- | --- |
| Isolation | structural: page CSS cannot reach the shadow root | specificity: selectors are prefixed to `x-panel .pill`, outranking the page's `.pill` |
| `:host` | usable as is | rewritten to the tag name by `scope_css` |
| page `!important` | has no effect | wins over the component's rules |
| ordinary page rules | have no effect | still apply where they match directly (e.g. `span { letter-spacing }`) |
| suited to | self-contained component styles | SSR output, or hosts that want their styles to bleed in |

## `link.js.format` is a no-op for executable packages

Measured on `moon 0.1.20261020`: with and without `link: { "js": { "format": "esm" } }`,
the artifact is byte-for-byte identical. The js artifact of an executable package exports
nothing and requires nothing; it is a plain script.

Browsers still load it with `<script type="module" src="./demo.js">`: a module script does
not need exports, and the self-executing initialization at the end of the artifact runs as
usual. `moon.pkg` therefore omits the option.
