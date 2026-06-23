# File Previewer

A Miller-column file browser that previews the selected file by launching the right external tool inside an embedded terminal — open it on any directory and arrow through your tree with live previews. Runs in the terminal (with embedded child processes).

## Run

```bash
swiftly run swift run --package-path file-previewer FilePreviewerApp
```

Run it from the directory you want to browse — the app opens on the current working directory.

## Demonstrates

- `SwiftTUITerminal` embedding via `TerminalProcessSession` — which means you can host a live child process (a previewer) inside a SwiftTUI view.
- A Miller-column layout with deterministic width allocation — multi-pane directory navigation that lays out predictably.
- Preview command routing by file extension — the right viewer fires per file type without hardcoding a single tool.
- Navigation state, directory selection, and the active terminal process all live inside a normal SwiftTUI view tree.

## Preview commands

The app picks a preview command by file extension:

| Extension | Command |
| --- | --- |
| `md` | `glow -s dark` |
| `json` | `jq -C .` |
| `yaml`, `yml`, `toml`, `swift` | `bat --color=always` |
| `png`, `jpg`, `jpeg`, `gif` | `chafa --symbols=block` |
| `zip` | `unzip -l` |
| `tar` | `tar -tvf` |
| everything else | `bat --color=always` |

Those tools are optional runtime dependencies of the example, not repo build
requirements.

## Controls

| Key | Action |
| --- | --- |
| `Up` / `Down` | Move selection in the active column |
| `Right` / `Return` | Enter a directory or preview a file |
| `Left` | Move back to the parent column |

## Test

```bash
swiftly run swift test --package-path file-previewer
```

The tests cover preview-command lookup, Miller-column width allocation,
directory-listing caching, preview-session replacement, and large-column lazy
rendering.

## See also

- A sibling embedded-process example in the [examples roster](../README.md).
- DocC reference: <https://swifttui.sh/docs/documentation/>
