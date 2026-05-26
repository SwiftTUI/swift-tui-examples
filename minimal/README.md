# minimal

Smallest checked-in one-shot rendering example.

Unlike the app examples, this one does not use `App`, `Scene`, `RunLoop`,
`TerminalRunner`, or SwiftTUI argument parsing. It prints one view tree through
`RenderOnce.print(...)` and exits.

## Demonstrates

- Snapshot rendering without an interactive runtime.
- The canonical one-shot output helper for report-like CLI commands.
- Width selection and terminal capability/color/glyph policy handled by
  `SwiftTUICLI`.

## Run

```bash
swiftly run swift run --package-path minimal minimal
```

This example has no test target. Use it as a compact reference for one-shot
rendering and documentation snippets. Use lower-level `DefaultRenderer` /
`TerminalSurfaceRenderer` directly only when you need renderer internals rather
than a copyable app-authoring path.
