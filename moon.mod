// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "chen333w/moon-element"

version = "0.2.0"

readme = "README.mbt.md"

repository = "https://github.com/chen333w/moon-element"

license = "Apache-2.0"

keywords = [
  "web-components",
  "custom-elements",
  "dom",
  "html",
  "frontend",
  "layout",
  "flexbox",
  "svg",
]

// This module is a browser-facing library: the default backend is `js` so that
// `moon check` / `moon build` exercise the real target. Pure-logic packages
// stay target-agnostic and are covered by `moon test --target all`.

preferred_target = "js"

description = "Web Components runtime for MoonBit, with an offscreen layout engine: the same view tree renders to custom elements or to geometry and SVG without a browser."
