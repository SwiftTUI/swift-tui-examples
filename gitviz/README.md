# GitViz

> Renders a git repository as a deck of terminal charts — heatmaps, sparklines, line charts, gauges — so you can read a repo's history at a glance. A non-interactive CLI that prints to the terminal.

## Run

```bash
swiftly run swift run --package-path gitviz gitviz dashboard --path .
```

```bash
swiftly run swift run --package-path gitviz gitviz info        # repo summary
swiftly run swift run --package-path gitviz gitviz activity     # GitHub-style calendar heatmap
swiftly run swift run --package-path gitviz gitviz deltas       # insertions / deletions line chart
```

All subcommands accept `--path <repo>` to point at a different working tree
and inherit the framework's `--no-color`, `--ascii`, `--reduce-motion`,
`--plain` flags from `SwiftTUIOptions`.

## Demonstrates

- `SwiftTUICharts` (from the separate [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package) — which means a developer gets ready-made terminal chart primitives (heatmaps, sparklines, line/bar/column charts, gauges, timelines) instead of hand-rolling cell drawing. Every chart type in the module is exercised by at least one subcommand.
- `SwiftTUICLI` argument parsing — a single executable fans out into many named subcommands, each with shared `SwiftTUIOptions` flags.
- One-shot terminal rendering — each subcommand prints a chart and exits, with no interactive loop, so the output composes cleanly into pipes and scripts.

## Subcommand roster

| Subcommand | Chart(s) |
|---|---|
| `info` | `Meter` + `ProgressView` + `Timeline` |
| `activity` | `CalendarHeatmap` |
| `cadence` | `HeatStrip` |
| `tempo` | `Sparkline` × top-N authors |
| `deltas` | `LineChart` (2 series, `.line`) |
| `loc` | `LineChart` (1 series, `.area`) |
| `volatility` | `BarChart` |
| `kinds` | `ColumnChart` |
| `kinds-share` | `StackedBarChart` |
| `pulse` | `BulletChart` |
| `recent-vs-all` | `ComparisonChart` |
| `health` | `ThresholdGauge` |
| `concentration` | `Meter` + `StackedBarChart` |
| `releases` | `Timeline` |
| `dag` | plain `Text` rows (pre-laid-out by `GraphLayout`) |
| `dashboard` | everything above |

## Test

```bash
swiftly run swift test --package-path gitviz
```

## See also

- [`SwiftTUICharts` reference](https://swifttui.sh/docs/charts/documentation/swifttuicharts/) — the chart primitives this example exercises (from the separate [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package).
- A sibling example in this repo's [README roster](../README.md).
