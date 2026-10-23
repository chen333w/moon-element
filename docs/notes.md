# Notes

Measured with `moon 0.1.20261020` on macOS arm64.

## extern "js"

The JS backend can define a class extending `HTMLElement` and register it with the custom element
registry. The registry requires the prototype chain to be rooted in `HTMLElement`, so the class has
to actually extend it rather than just look like one: the probe is
`ctor.prototype instanceof HTMLElement`.

Callbacks have to use plain function types. `FuncRef[() -> Unit]` fails with

```
Error: [4014] Expr Type Mismatch
  has type : () -> Unit
  wanted   : FuncRef[() -> Unit]
```

An external JS value of function type is a plain function; `FuncRef` is for capture-free closures.
The FFI documentation says as much for the JS backend ("JavaScript supports closure, so there's
nothing special to be done here"). The adapter depends on this, because it captures `specs` and
`render_fn` into the callbacks.

Option values do not cross the FFI boundary in this codebase: the representation is not a stable ABI.
Old and new attribute values are passed as a presence `Bool` plus a `String`.

## Loading the bundle

`link: { "js": { "format": "esm" } }` turned out to be a no-op for an executable package: the bundle
is byte-identical with and without it. It exports nothing and requires nothing, so it is a plain
script with a self-executing initialization at the end.

The browser loads it anyway, because `<script type="module" src="...">` accepts a script with no
exports. `examples/demo/moon.pkg` therefore leaves the option out.

`examples/demo/verify.mjs` imports that same file under node and checks 19 behaviors on a small DOM
stub. CI runs it after `moon build --target js --release`.

## Toolchain

`moon check --deny-warn` treats warnings as errors.

Coverage counters go stale when the number of instrumented lines changes. Run `moon clean` before
re-running `moon test --enable-coverage`.

A step name containing `": "` makes a workflow YAML file unparseable, so validate after editing:
`ruby -ryaml -e 'YAML.load_file("...")'`.

`#|` multi-line literals are raw text; they do not interpolate `\{...}`. Generators have to build
strings by concatenation. `const` needs an uppercase identifier, and `FixedArray` has no `push`.