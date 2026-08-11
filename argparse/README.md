# Argparse

This focused command-line example shows how a SwiftTUI `App` owns app flags. It
also exposes the standard framework runtime options. The example runs in the
terminal as a CLI.

## Run

```bash
swiftly run swift run --package-path argparse argparse-demo --help
```

```bash
swiftly run swift run --package-path argparse argparse-demo                          # launch with defaults
swiftly run swift run --package-path argparse argparse-demo --widgets 8 --show-ids   # consumer flags
```

## Demonstrates

- `import SwiftTUI` gives `SwiftTUI.App` command conformance. An app type is also
  a Swift Argument Parser command without additional code.
- App flags such as `--widgets` and `--show-ids` work with the framework
  options. The app keeps its own argument surface.
- `SwiftTUIOptions` automatically exposes the standard SwiftTUI flags. These
  include `--no-color`, `--ascii`, `--reduce-motion`, `--debug`, `--json`, and
  accessibility options.
- Swift Argument Parser provides the built-in completions subcommand. You do
  not have to write shell completions.

## Test

The package has no test target. The root command-surface tests cover this example. The root
README describes its source structure.

## See also

- [Swift Argument Parser](https://github.com/apple/swift-argument-parser): the command/flag engine `SwiftTUI.App` conforms to.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/): `SwiftTUIOptions` and the rest of the public runtime surface.
