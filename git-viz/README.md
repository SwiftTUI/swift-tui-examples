# GitViz

> Renders a git repository as a deck of terminal charts — heatmaps, sparklines, line charts, gauges — so you can read a repo's history at a glance. A non-interactive CLI that prints to the terminal.

## Run

```bash
swiftly run swift run --package-path git-viz git-viz dashboard --path .
```

```bash
swiftly run swift run --package-path git-viz git-viz info      # repo summary
swiftly run swift run --package-path git-viz git-viz activity  # GitHub-style calendar heatmap
swiftly run swift run --package-path git-viz git-viz deltas    # insertions / deletions line chart
```

Every subcommand inherits the framework's `--no-color`, `--ascii`,
`--reduce-motion`, and `--plain` flags from `SwiftTUIOptions`. Each subcommand
also accepts `--width`.

Each subcommand declares only the options that it uses. Thus, `--help` lists
only effective options. An unsupported option produces an error.

| Option group | Options | Applies to |
| --- | --- | --- |
| `RepositoryOptions` | `--path` | every subcommand except `index`, which opens no repository |
| `ScanLimitOptions` | `--max-commits` | the subcommands that walk commits |
| `DateWindowOptions` | `--since`, `--until` | the subcommands that pass a window through to git |
| `RankingOptions` | `--top` | the four subcommands that rank something |

`activity`, `health`, `pulse`, and `recent-vs-all` do not accept `--since` or
`--until`. Each command has a fixed window that defines the chart. The windows
are a calendar year, one year, five weeks, and 30 days versus all time.

`--since` and `--until` accept a `YYYY-MM-DD` calendar day. Argument parsing
makes sure that the value has this format. An incorrect value stops the command
instead of increasing the date window.

## Demonstrates

- `SwiftTUICharts` comes from the separate
  [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package. It
  provides heatmaps, sparklines, charts, gauges, and timelines. At least one
  subcommand uses each chart type in the module.
- `SwiftTUICLI` parses arguments for one executable with multiple named
  subcommands. Each subcommand shares the `SwiftTUIOptions` flags.
- Each subcommand renders one chart and exits without an interactive loop.
  Thus, pipes and scripts can use the output.
- `GitRunning` separates the creation of a git command from its execution.
  Tests can examine the exact `argv` and replay recorded output without a git
  process. They do not start `git`.

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
swiftly run swift test --package-path git-viz
```

Tests use bytes from a real `git` process instead of hand-written samples. To
update the recordings, run:

```bash
git-viz/Scripts/record_git_fixtures.sh
```

The script builds a temporary repository with inputs that can break parsers. It
includes a merge without a numstat block and a rename with a three-token NUL
entry under `-z`. It also includes a Unicode subject and both tag types. Then
the script runs the exact `argv` from `GitRepo`. Fixed commit dates produce
byte-identical fixtures. A diff indicates a change in the git output format.
The provenance record is in
[`Tests/GitVizTests/Fixtures/PROVENANCE.md`](Tests/GitVizTests/Fixtures/PROVENANCE.md).

## See also

- [`SwiftTUICharts` reference](https://swifttui.sh/docs/charts/documentation/swifttuicharts/) — the chart primitives this example exercises (from the separate [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package).
- A sibling example in this repo's [README roster](../README.md).
