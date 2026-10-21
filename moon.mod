// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "chen333w/moon-element"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/chen333w/moon-element"

license = "Apache-2.0"

keywords = [ "web-components", "custom-elements", "dom", "html", "frontend" ]

// This module is a browser-facing library: the default backend is `js` so that
// `moon check` / `moon build` exercise the real target. Pure-logic packages
// stay target-agnostic and are covered by `moon test --target all`.

preferred_target = "js"

description = "Standard Web Components runtime for MoonBit: define custom elements that work in any page or framework."
