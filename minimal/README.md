# Minimal

> The smallest checked-in example: it renders one view tree to stdout and exits, showing the one-shot snapshot path for report-like CLI output. Its canonical host is the terminal (one-shot CLI render).

## Run

```bash
swiftly run swift run --package-path minimal minimal
```

## Demonstrates

- `RenderOnce.print(...)` writes a SwiftTUI view tree as terminal output. It
  does not start an interactive runtime.
- Snapshot rendering uses no `App`, `Scene`, `RunLoop`, `TerminalRunner`, or
  argument parser. This structure is for CLI reports that print once and exit.
- `SwiftTUICLI` selects the width, terminal features, colors, and glyph policy.
  The example does not manage renderer internals directly.

## Notes

Use this example as a compact reference for one-shot rendering and
documentation snippets. If you need renderer internals, use `DefaultRenderer`
or `TerminalSurfaceRenderer` instead of this copyable app-authoring path.

## Test

The package has no test target.

## See also

- [`RenderOnce` reference](https://swifttui.sh/docs/documentation/) — the one-shot output helper this example is built around.
