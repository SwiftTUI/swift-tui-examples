# Terminal Runner

> A minimal SwiftTUI app launched through a hand-written `TerminalRunner` entry point — showing how to own preflight checks and runtime configuration before the interactive UI starts, instead of leaning on the convenience `SwiftTUI`/WebHost surface. Its canonical host is the terminal.

## Run

```bash
swiftly run swift run --package-path terminal-runner terminal-runner
```

The example rejects browser hosting. If you pass `--web`, it exits before
launch:

```bash
swiftly run swift run --package-path terminal-runner terminal-runner --web
```

## Demonstrates

- `SwiftTUICLI` provides the terminal `TerminalRunner` APIs without the WebHost
  convenience layer in `SwiftTUI`.
- A custom `static main() async throws` applies the launch policy. In this
  example, it rejects `--web` before the framework parses scene commands.
- `RuntimeConfiguration.detect(environment:isStdoutTTY:)` supplies
  `TerminalRunner.run(_:configuration:)`. Thus, the app starts with an explicit
  configuration based on its environment and TTY state.

## What to copy

- If you need terminal runner APIs without the WebHost convenience surface,
  import `SwiftTUICLI`.
- If launch policy must run before scene-command parsing, implement a custom
  `static main()`.
- Build a `RuntimeConfiguration` from environment and TTY status, then call
  `TerminalRunner.run(Self.self, configuration:)`.

The `--web` rejection demonstrates that a `TerminalRunner` launcher is
terminal-only. Use `WebHostExample` for the smallest app that accepts `--web`.

## Test

```bash
swiftly run swift test --package-path terminal-runner
```

## See also

- [`WebHostExample`](../WebHostExample/) — the sibling that accepts `--web` and hosts in the browser.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/)
