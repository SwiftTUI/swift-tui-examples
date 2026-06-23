# Terminal Runner

> A minimal SwiftTUI app launched through a hand-written `TerminalRunner` entry point — showing how to own preflight checks and runtime configuration before the interactive UI starts, instead of leaning on the convenience `SwiftTUI`/WebHost surface. Its canonical host is the terminal.

## Run

```bash
swiftly run swift run --package-path terminal-runner terminal-runner
```

This example deliberately rejects browser hosting — passing `--web` exits before launch:

```bash
swiftly run swift run --package-path terminal-runner terminal-runner --web
```

## Demonstrates

- `SwiftTUICLI` — which means you get the terminal `TerminalRunner` APIs directly, without the WebHost convenience layer that `SwiftTUI` bundles in.
- A custom `static main() async throws` — which means launch policy (here, the `--web` rejection) runs before the framework parses terminal scene commands.
- `RuntimeConfiguration.detect(environment:isStdoutTTY:)` fed into `TerminalRunner.run(_:configuration:)` — which means the app boots from an explicit, environment- and TTY-aware configuration rather than implicit defaults.

## What to copy

- Import `SwiftTUICLI` when you want terminal runner APIs without the WebHost
  convenience surface.
- Implement a custom `static main()` when launch policy must run before the
  framework parses terminal scene commands.
- Build a `RuntimeConfiguration` from environment and TTY status, then call
  `TerminalRunner.run(Self.self, configuration:)`.

The deliberate `--web` rejection is the teaching beat: a `TerminalRunner`-based
launcher is terminal-only by design. Use `WebHostExample` when the goal is the
smallest app that accepts `--web`.

## Test

```bash
swiftly run swift test --package-path terminal-runner
```

## See also

- [`WebHostExample`](../WebHostExample/) — the sibling that accepts `--web` and hosts in the browser.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/)
