#!/usr/bin/env python3
"""Checks the headless layout CLI: geometry, wrapping, determinism and SVG output.

Run from the repository root after `moon build`-time deps are available:

    python3 examples/dashboard/verify_layout.py
"""

import json
import subprocess
import sys
import xml.dom.minidom

results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok)))
    mark = "ok  " if ok else "FAIL"
    print(f"  {mark} {name}" + (f"  [{detail}]" if detail and not ok else ""))


def run(*args):
    proc = subprocess.run(
        ["moon", "run", "cmd/main", "--", "layout", *args],
        capture_output=True,
        text=True,
    )
    return proc


def near(a, b, eps=0.02):
    return abs(a - b) <= eps


# 640 wide page: nav spans the padded content box, three cards split one row.
proc = run("--width", "640")
check("the CLI exits successfully", proc.returncode == 0, proc.stderr[-200:])
doc = json.loads(proc.stdout)
root = doc["rect"]
check("root border box is the requested width", near(root[2], 640.0), str(root))
sections = doc["children"]
check("root has nav, cards and footer", len(sections) == 3, str(len(sections)))
nav = sections[0]["rect"]
check("nav sits inside the page padding", near(nav[0], 16.0) and near(nav[2], 608.0), str(nav))

cards = sections[1]["children"]
check("three cards", len(cards) == 3, str(len(cards)))
widths = [c["rect"][2] for c in cards]
check("cards split the row evenly", all(near(w, widths[0]) for w in widths), str(widths))
check("cards leave a 12px gap", near(cards[1]["rect"][0] - cards[0]["rect"][0] - widths[0], 12.0), str(cards[1]["rect"]))
check("cards share one row", near(cards[0]["rect"][1], cards[2]["rect"][1]), str([c["rect"][1] for c in cards]))

def texts(node, out):
    if node.get("tag") == "#text":
        out.append(node.get("text"))
    for child in node.get("children", []):
        texts(child, out)
    return out

labels = texts(doc, [])
check("text runs carry their content", "Moon Dashboard" in labels and "Latency" in labels, str(labels[:4]))

# Narrow page: the cards must wrap instead of shrinking below their basis.
narrow = json.loads(run("--width", "300").stdout)
narrow_cards = narrow["children"][1]["children"]
check("cards wrap on a narrow page", narrow_cards[2]["rect"][1] > narrow_cards[0]["rect"][1] + 1.0,
      str([c["rect"][1] for c in narrow_cards]))
check("wrapped cards stay inside the page", all(c["rect"][2] <= 268.02 for c in narrow_cards), str([c["rect"][2] for c in narrow_cards]))

# Determinism: the same input must produce byte-identical output.
check("layout output is deterministic", run("--width", "640").stdout == proc.stdout)

# SVG: well-formed XML with the geometry embedded.
svg = run("--format", "svg")
check("svg mode exits successfully", svg.returncode == 0, svg.stderr[-200:])
try:
    dom = xml.dom.minidom.parseString(svg.stdout)
    parsed = True
except Exception as exc:  # noqa: BLE001 - the point is to report the parse error
    parsed = False
    dom = None
    check("svg is well-formed xml", False, str(exc))
if parsed:
    check("svg is well-formed xml", True)
    root_el = dom.documentElement
    check("svg declares its size", root_el.tagName == "svg" and root_el.getAttribute("width") == "641.00", root_el.toxml()[:80])
    check("svg has rect and text nodes",
          len(dom.getElementsByTagName("rect")) >= 10 and len(dom.getElementsByTagName("text")) >= 5,
          f'{len(dom.getElementsByTagName("rect"))} rects')

# Misuse must fail loudly instead of printing a wrong document.
bad = run("--width", "abc")
check("a bad width is rejected", bad.returncode != 0 or "Error" in bad.stdout + bad.stderr)
bad_format = run("--format", "png")
check("a bad format is rejected", bad_format.returncode != 0 or "Error" in bad_format.stdout + bad_format.stderr)

passed = sum(1 for _, ok in results if ok)
failed = len(results) - passed
print(f"\npassed {passed}, failed {failed}")
sys.exit(0 if failed == 0 else 1)
