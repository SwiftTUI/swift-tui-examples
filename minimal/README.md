# Minimal

> The smallest checked-in example: it renders one view tree to stdout and exits, showing the one-shot snapshot path for report-like CLI output. Its canonical host is the terminal (one-shot CLI render).

## Run

```bash
swiftly run swift run --package-path minimal minimal
```

## Demonstrates

- `RenderOnce.print(...)` — which means you can emit a SwiftTUI view tree as terminal output without standing up an interactive runtime.
- Snapshot rendering with no `App`, `Scene`, `RunLoop`, `TerminalRunner`, or argument parsing — the right shape for report-like CLI commands that print once and exit.
- `SwiftTUICLI` width selection plus terminal capability/color/glyph policy — which means correct output is chosen for you instead of hand-managing renderer internals.

## Notes

Use this as a compact reference for one-shot rendering and documentation
snippets. Reach for the lower-level `DefaultRenderer` /
`TerminalSurfaceRenderer` directly only when you need renderer internals rather
than a copyable app-authoring path.

## Test

No test target.

## See also

- [`RenderOnce` reference](https://swifttui.sh/docs/documentation/) — the one-shot output helper this example is built around.
