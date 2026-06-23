# Argparse

A focused command-line integration example showing how a SwiftTUI `App` owns its own consumer flags while exposing the framework's standard runtime options — small enough that the argument-parsing shape is easy to copy. Runs in the terminal (CLI).

## Run

```bash
swiftly run swift run --package-path argparse argparse-demo --help
```

```bash
swiftly run swift run --package-path argparse argparse-demo                          # launch with defaults
swiftly run swift run --package-path argparse argparse-demo --widgets 8 --show-ids   # consumer flags
```

## Demonstrates

- `SwiftTUI.App` command conformance through `import SwiftTUI` — which means an app type doubles as a Swift Argument Parser command with no extra boilerplate.
- Consumer-defined flags such as `--widgets` and `--show-ids` coexist with the framework's options — your app keeps its own argument surface.
- Standard SwiftTUI flags (`--no-color`, `--ascii`, `--reduce-motion`, `--debug`, `--json`, and accessibility options) are exposed automatically via `SwiftTUIOptions`.
- The built-in completions subcommand from Swift Argument Parser ships for free — shell completions without hand-writing them.

## Test

No test target. This example is covered by the root command-surface tests and by the source-level shape documented in the root README.

## See also

- [Swift Argument Parser](https://github.com/apple/swift-argument-parser) — the command/flag engine `SwiftTUI.App` conforms to.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/) — `SwiftTUIOptions` and the rest of the public runtime surface.
