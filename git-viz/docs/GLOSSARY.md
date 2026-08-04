# git-viz glossary

Shared vocabulary for git-viz design work. Each term describes current code.

- **Git invocation** — `GitRunning.run(_:in:)` connects an argument array to Git
  output. The seam is below argument construction. `GitRepo` owns each argument
  array and each argv-to-parser pairing. Only command execution crosses this
  seam. `ProcessGitRunner` starts the binary. `RecordedGitRunner` replays
  captured bytes.
  _Avoid_: git client, process wrapper.
- **Recorded run** — This run replays Git output for an *exact* argument array.
  Exact matching is an invariant. A missing recording causes a visible failure
  instead of an empty result. Thus, a changed flag causes a test failure. This
  class includes incorrect `--reverse` behavior and missing `-z` output.
- **Argv-to-parser pairing** — This relation connects a command line to its
  output parser. The pure parsers already had tests. The relation had no test
  surface before the Git invocation seam. `GitParsers.logFormat` and
  `tagFormat` define the output format. The `-z`, `--numstat`, and `--reverse`
  flags previously changed without a test failure.
- **Honored option surface** — A subcommand declares only the option groups that
  it reads. Thus, its behavior agrees with `--help`. The option types are
  `RepositoryOptions`, `ScanLimitOptions`, `DateWindowOptions`, and
  `RankingOptions`. Each subcommand selects the applicable types. One flat
  group previously let `releases` advertise an unused `--top` option. An
  undeclared option now causes a parse error.
  _Avoid_: global options, shared flags.
- **Definitional window** — This fixed date range defines the meaning of a
  chart. `activity` and `health` use a calendar year. `pulse` uses five weeks.
  `recent-vs-all` uses 30-days-versus-all-time. These subcommands reject
  `--since` and `--until`.
  A different window changes the chart meaning. In contrast, a scan bound only
  limits the amount of history that the command reads.
