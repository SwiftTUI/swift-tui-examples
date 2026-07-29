# MrkdwnMermaid

A portable, dependency-free terminal Mermaid renderer. It parses a Mermaid
source, lays it out, and returns a grid of semantic cells — it does not depend
on SwiftTUI, Foundation, JavaScript, a browser, or the network.

## Why it lives here

This renderer is **vendored into the `mrkdwn` example on purpose**. It was
originally built to ship as a standalone `SwiftTUI/swift-mermaid` package, but
SwiftTUI is not ready to take on another public library, so the code is owned
outright by this example instead. There is no separate repository, package,
release line, or version to track.

The org gate enforces this: `check_public_dependency_contracts.sh` fails any
public manifest that re-declares the renderer as a package dependency.

If it is ever promoted to its own package again, extract this directory plus
`../../Tests/MrkdwnMermaidTests` and `../../Scripts/mermaid`.

## Licensing

This directory is Apache-2.0, unlike the MIT license covering the rest of
`swift-tui-examples`. It is a clean-room Swift translation of prior
Apache-2.0 work, so both [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE) must travel
with the code. `NOTICE` carries the file-level provenance map (which upstream
source each file was adapted from) and the derivation terms for the generated
Unicode data — do not drop it.

## Layout

| Path | Contents |
| --- | --- |
| `MermaidRenderer.swift` | Entry point: `layoutMetrics`, `measure`, `renderSurface` |
| `MermaidSurface.swift` | Cell/role model returned to the host |
| `MermaidConfiguration.swift` | Glyph mode and ambiguous-width policy |
| `MermaidReport.swift` | Diagnostics and `complete`/`partial` fidelity |
| `Internal/` | Parser, diagram model, and layout |
| `Generated/` | Checked-in Unicode width and bidi-class tables |

[`SYNTAX.md`](SYNTAX.md) documents the supported diagram families.

## Regenerating the Unicode tables

The tables in `Generated/` are checked in and rarely change. To rebuild them:

```bash
Scripts/mermaid/generate_unicode_width.sh          # needs cargo (Rust oracle)
Scripts/mermaid/generate_unicode_bidi.sh           # downloads a pinned UCD file
```

Pass `--check` to either script to diff against the checked-in output instead of
overwriting it. Both are run from the `mrkdwn` package root.

## Tests

`../../Tests/MrkdwnMermaidTests` holds the renderer's own suite, including the
golden fixtures under `Fixtures/`:

```bash
swiftly run swift test --package-path mrkdwn --filter MrkdwnMermaidTests
```
