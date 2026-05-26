# terminal-runner

Small terminal-only `SwiftTUICLI` example that uses `TerminalRunner` directly
instead of the convenience `SwiftTUI` import or WebHost runner.

Use this when you need a custom launcher that owns preflight checks, argument
policy, or explicit runtime configuration before the interactive SwiftTUI app
starts.

## Run

```bash
cd terminal-runner
swiftly run swift run terminal-runner
```

This example deliberately rejects browser hosting:

```bash
swiftly run swift run terminal-runner --web
```

Use `WebHostExample` when the goal is the smallest app that accepts `--web`.

## What to copy

- Import `SwiftTUICLI` when you want terminal runner APIs without the WebHost
  convenience surface.
- Implement a custom `static main()` when launch policy must run before the
  framework parses terminal scene commands.
- Build a `RuntimeConfiguration` from environment and TTY status, then call
  `TerminalRunner.run(Self.self, configuration:)`.
