# WebHost Example

> The smallest app that runs unchanged in two places — a normal terminal program, or a browser tab — proving one `SwiftTUI` import is all it takes to reach both. Its canonical host is the terminal by default, or a localhost WebHost when launched with `--web`.

## Run

```bash
swiftly run swift run --package-path WebHostExample WebHostExample --web
```

Drop `--web` to run the same binary as a normal terminal program:

```bash
swiftly run swift run --package-path WebHostExample WebHostExample
```

The normal WebHost flags are available here, including `--port`, `--bind`, `--open`, and `--scene`.

## Demonstrates

- The `SwiftTUI` convenience product's combined terminal/WebHost launcher — which means one import and one binary serve both the terminal and the browser, with no separate host wiring.
- A single `WindowGroup` with an explicit scene identifier — which means the scene is addressable (e.g. via `--scene`) when hosted.
- The default `--web` path without importing lower-level WebHost products — which means the browser runner ships through the public convenience surface, not internal modules.

## Test

```bash
swiftly run swift test --package-path WebHostExample
```

The test pins the intended package boundary: the example imports `SwiftTUI` and does not directly wire the lower-level WebHost runner.

## See also

- [WebExample](../WebExample/README.md) — the browser/WASI deployment example.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/)
