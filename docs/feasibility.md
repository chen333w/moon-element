# Feasibility notes

Date: 2026-10-21 (assumption 3 re-checked 2026-10-22) | Toolchain: `moon 0.1.20261020` | Machine: macOS arm64

The premise of this project is that the MoonBit JS backend can register a class that genuinely
extends `HTMLElement` with the custom element registry, and that DOM callbacks can reach MoonBit
code. The three assumptions below were checked before writing any core functionality; each records
method, command, output and conclusion.

## Assumption 1: the JS backend can register a real `HTMLElement` subclass

**Method**: define `class MoonElement extends globalThis.HTMLElement` with inline JS in
`dom/element_ffi.mbt`, call `customElements.define`, and have a probe return
`ctor.prototype instanceof HTMLElement`.

```bash
$ moon check --target js
Finished. moon: ran 2 tasks, now up to date

$ moon test --target js
Total tests: 2, passed: 2, failed: 0.
```

**Conclusion: holds.** The test asserts `false` before registration and `true` after, i.e. the
prototype chain is rooted in `HTMLElement`, which the custom element registry requires (an ordinary
class does not qualify).

## Assumption 2: DOM callbacks can reach MoonBit code

**Method**: pass a MoonBit function as the callback, trigger `connectedCallback` twice through a
probe, and assert the MoonBit-side counter increased by 2.

```bash
$ moon test --target js
Total tests: 2, passed: 2, failed: 0.
```

**Conclusion: holds.** The DOM → MoonBit direction works.

### Finding: callback parameters use plain function types on the JS backend

Writing `FuncRef[() -> Unit]` fails to compile:

```
Error: [4014] Expr Type Mismatch
  has type : () -> Unit
  wanted   : FuncRef[() -> Unit]
```

When an `extern "js"` function takes a value of function type, the type is a plain function type;
`FuncRef[T]` is for capture-free closures. The FFI documentation states for the JS backend:
"JavaScript supports closure, so there's nothing special to be done here". Using a plain function
type compiles and runs correctly. The adapter relies on this, since it captures `specs` and
`render_fn` into the callbacks; reusing the same layer on a Wasm backend would require evaluating
`FuncRef` versus `make_closure`.

## Assumption 3: the JS output can be loaded externally

**Method**: build the demo's JS artifact, import that file directly (the same one the browser
loads), and assert runtime behavior on a minimal DOM stub under node.

```bash
$ moon build --target js --release
Finished. moon: ran 2 tasks, now up to date

$ node examples/demo/verify.mjs
bundle: .../_build/js/release/build/examples/demo/demo.js
[moon-element] demo components registered: x-counter / x-badge / x-card / x-panel (light DOM)
  ok   the bundle loads and runs as an ES module
  ok   all four custom elements are registered after loading
  ok   observedAttributes is generated from the attribute specs
  ok   an invalid attribute value falls back to the default instead of erroring
  ok   user input is escaped and never executed as markup
  ok   light mode creates no shadow root
  ok   styles are scoped to the tag name by scope_css (:host becomes x-panel)
  ...
passed 16, failed 0
```

**Conclusion: holds.** The artifact loads and executes as an ES module, and component registration
and runtime behavior match expectations. This check runs in CI
(`Build demo and verify the artifact headlessly`).

### Finding: `link.js.format` is a no-op for executable packages

Measured: with and without `link: { "js": { "format": "esm" } }` the artifact is byte-identical. An
executable package's JS output has neither `export` nor `require`; it is a plain script with a
self-executing initialization at the end. The option only matters when symbols must be exported.

The browser can still load it because `<script type="module" src="...">` accepts a script with no
exports — a module script does not have to export anything. `examples/demo/moon.pkg` therefore omits
the option.

## Conventions

- Target-agnostic logic lives in its own packages; JS FFI is confined to the `dom/` package with
  `supported_targets = "js"`, so the all-backend build is unaffected
- Adapter tests run under node against the dependency-free `install_dom_stub()`; no jsdom or
  happy-dom. Real behavior of the build artifact is verified by `examples/demo/verify.mjs`
- Every change runs `moon check --deny-warn --target all`; warnings are errors
- Changes to `.github/workflows/*.yml` must be validated locally with
  `ruby -ryaml -e 'YAML.load_file("...")'`. A step name containing `": "` makes the whole workflow
  unparseable