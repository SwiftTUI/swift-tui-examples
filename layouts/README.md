# Layouts

> A browsable catalog of 56 focused layout demos that show exactly how SwiftTUI measures, places, and proposes. Open one and read the rule it isolates. Runs in the terminal.

## Run

```bash
swiftly run swift run --package-path layouts layouts-demo
```

The app launches directly into the full-screen push/pop picker.

## Demonstrates

- The `SwiftTUI` measure, place, and proposal model demonstrates each geometry
  rule separately. The rules cover size, placement, and proposal handling.
- The catalog has a separate entry for each `SwiftTUIRuntime` and
  `SwiftTUICharts` surface. Entries cover overlays, scrolling, shapes, matched
  geometry, and custom layouts. The chart product comes from the separate
  [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package.
- Each catalog entry has a smoke test. Layouts tagged with `.behaviour` also
  have focused tests for their measure and place rules.

## Scope

Keep this example focused on layout behavior. Its scope includes measurement,
placement, proposals, geometry, overlays, scrolling, shapes, matched geometry,
and custom layouts. Put component and workflow demonstrations in the gallery.
Thus, this catalog remains a focused layout reference.

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

The package has 81 tests across 54 suites. It has 56 parameterized smoke tests,
one for each catalog entry. Focused behavior tests cover the `.behaviour` tier.
Other tests cover catalog integrity and rasterize each picker category.

## Findings

The behavior test files describe library differences and design questions.
Behavior tests record the current behavior. Before you change the library,
update the test comment and open a discussion.

## See also

- [`gallery`](../gallery/README.md): component and workflow demonstrations that complement this layout-only catalog.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/): the public API surface these layouts exercise.
