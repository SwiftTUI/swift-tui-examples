# Terminal Workspace

> A first-class terminal multiplexer surface — tabbed, split-pane shell sessions with active-pane chrome, a command palette, and persisted layout — showing how a full workspace UI is composed and survives restarts. Runs in the terminal.

## Run

```bash
swiftly run swift run --package-path terminal-workspace terminal-workspace
```

## Demonstrates

- `SwiftTUITerminalWorkspace` — which means a developer gets a ready-made tabbed, split-pane terminal workspace surface rather than hand-building one.
- Retained terminal sessions with visible active-pane chrome and a `Ctrl+K` command palette — directional focus movement, splitting, zoom, and pane lifecycle out of the box.
- Layout and command-metadata persistence to `~/.swift-tui-terminal-workspace.json`, restored on launch.

## Persistence

The example persists layout and command metadata to
`~/.swift-tui-terminal-workspace.json`. It intentionally restores fresh
processes on launch; detach/reattach is future workspace-session work.

## Controls

| Key | Action |
| --- | --- |
| `Ctrl+K` | Command palette |
| `Alt+H/J/K/L` or `Alt+Arrow` | Move focus |
| `Alt+V` | Split the focused pane right |
| `Alt+S` | Split the focused pane down |
| `Alt+T` | Create a new shell tab |
| `Alt+Z` | Zoom or unzoom the focused pane |
| `Alt+X` | Close the focused pane |

## Test

```bash
swiftly run swift test --package-path terminal-workspace
```

The focused test pins the initial dev/ops workspace shape and pane identifiers
so the example remains useful as the workspace product evolves.

## See also

- [DocC reference](https://swifttui.sh/docs/documentation/) — the full `SwiftTUITerminalWorkspace` API surface.
