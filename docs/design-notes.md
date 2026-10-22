# Design notes

Key decisions and their rationale.

## Layering: core and dom

- Rules (attribute parsing, fallback semantics, lifecycle, rendering, CSS scoping, events, render
  modes) live in `core`; DOM wiring and instance state live in `dom`
- Rationale: the rules are covered by ordinary unit tests on wasm / wasm-gc / native / js without a
  browser, so `dom` only has to show that the wiring is right

## Cross-FFI trade-offs

- Callback parameters use plain function types: `FuncRef[T]` requires a capture-free closure, and the
  adapter needs to capture `specs` and `render_fn`. See [feasibility](feasibility.md)
- No `Option` across the FFI boundary: its representation is not a stable ABI. Old/new attribute
  values are passed as a presence `Bool` plus a `String`
- Instance state is read, mutated and written back, so the code does not depend on whether struct
  assignment copies or aliases
- The instance registry is an array indexed by id; ids are allocated on the JS side

## Attributes and rendering

- Missing or invalid attribute values fall back to the default (HTML semantics); booleans follow
  presence = true; reflection expresses `false` by removing the attribute
- Integer parsing accepts at most 9 decimal digits: `Int` width can differ per backend, and bounding
  the digit count keeps "invalid values always fall back to the default" consistent across backends
- Rendering replaces `shadowRoot.innerHTML` as a whole, with no diff. Components therefore do not
  attach DOM listeners internally (the next render replaces them); interaction lives in the page
- Styles are declared once through `styles`: injected as-is in shadow mode (`:host` works), scoped to
  the tag name via `scope_css` in light mode
- Light DOM isolation is specificity-based: it does not override `!important` from the page, and page
  rules that match directly still apply. Shadow DOM isolation is structural

## Generator and CI

- CLI output is committed: CI compiles it and checks that the current CLI output equals the committed
  file (drift check)
- The generator emits already-formatted code, so `moon fmt` does not change it
- Gates: `moon check --deny-warn --target all`, tests on four backends, interface drift check
  (`moon info` then verify `.mbti`), generator drift check, build-artifact verification

## Known limitations

- No per-element diff; tag-name validation accepts an ASCII subset; `::slotted()` /
  `:host-context()` are not rewritten; no threads / async support (MoonBit has no OS threads, and
  async is complete on native only)

## Coverage

Library 96.5% (688/713), whole repo 83.9% (704/839). The uncovered lines are mainly of three kinds:
defensive branches (e.g. `String::get_char` cannot return `None` for a valid index), line-attribution
artifacts caused by inlining, and the CLI entry point and demo integration paths, which are covered
by artifact verification, the drift checks and CI compilation.