# Layouts

> A browsable catalog of 56 focused layout demos that show exactly how SwiftTUI measures, places, and proposes — open one and read the rule it isolates. Runs in the terminal.

## Run

```bash
swiftly run swift run --package-path layouts layouts-demo
```

The app launches directly into the full-screen push/pop picker.

## Demonstrates

- `SwiftTUI` measure/place/proposal model — which means you can see each geometry rule (sizing, placement, proposal handling) demonstrated in isolation rather than tangled in a real app.
- `SwiftTUIRuntime` and `SwiftTUICharts` surfaces — overlays, scrolling, shapes, matched geometry, and custom layouts each get a dedicated entry.
- A self-checking catalog — every entry is pinned by a smoke test, and `.behaviour`-tagged layouts add targeted tests for the specific measure/place rule they exist to show.

## Scope

Keep this example focused on layout behavior: measuring, placement, proposal
handling, geometry, overlays, scrolling, shapes, matched geometry, and custom
layouts. Component and workflow demonstrations belong in the gallery so this
catalog stays useful as a focused layout reference.

## Controls

| Key | Action |
| --- | --- |
| `↑` / `↓` | Move selection in the picker |
| `⏎` | Open the selected layout |
| `esc` | Pop back to the picker |
| `⌃C` | Quit |

## Test

```bash
swiftly run swift test --package-path layouts
```

81 tests across 54 suites: 56 parameterised smoke tests (one per
catalog entry), targeted behaviour tests for the `.behaviour` tier,
catalog-integrity invariants, and a picker-shell test that
rasterises every category section.

## Findings

Library divergences and design questions surfaced while implementing the
behaviour tests are documented inline in the behaviour test files.
Behaviour tests pin the *observed* behaviour today; update a test's
comment and open a discussion before changing the library.

## See also

- [`gallery`](../gallery/README.md) — component and workflow demonstrations that complement this layout-only catalog.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/) — the public API surface these layouts exercise.
