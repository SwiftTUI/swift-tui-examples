# WebHost Example

> The smallest app that runs unchanged in two places — a normal terminal program, or a browser tab — proving one `SwiftTUI` import is all it takes to reach both. Its canonical host is the terminal by default, or a localhost WebHost when launched with `--web`.

## Run

```bash
swiftly run swift run --package-path WebHostExample WebHostExample --web
```

Remove `--web` to run the same binary as a terminal program:

```bash
swiftly run swift run --package-path WebHostExample WebHostExample
```

The example accepts the standard WebHost flags: `--port`, `--bind`, `--open`,
and `--scene`.

## Demonstrates

- The `SwiftTUI` convenience product provides a combined terminal and WebHost
  launcher. One import and one binary serve both hosts.
- One `WindowGroup` has an explicit scene identifier. The host can select this
  scene with `--scene`.
- The default `--web` path does not import lower-level WebHost products. The
  browser runner uses the public convenience surface, not internal modules.

## Test

```bash
swiftly run swift test --package-path WebHostExample
```

The test makes sure that the package boundary stays intact. The example imports
`SwiftTUI` and does not connect the lower-level WebHost runner directly.

## See also

- [WebExample](../WebExample/README.md) — the browser/WASI deployment example.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/)
