# Terminal Workspace

> A first-class terminal multiplexer surface — tabbed, split-pane shell sessions with active-pane chrome, a command palette, and persisted layout — showing how a full workspace UI is composed and survives restarts. Runs in the terminal.

## Run

```bash
swiftly run swift run --package-path terminal-workspace terminal-workspace
```

## Demonstrates

- `SwiftTUITerminalWorkspace` provides a terminal workspace with tabs and split
  panes.
- Retained terminal sessions have visible active-pane controls and a `Ctrl+K`
  command palette. The palette controls focus, splits, zoom, and the pane
  lifecycle.
- The example writes layout and command metadata to
  `~/.swift-tui-terminal-workspace.json`. It restores this data at launch.

## Persistence

The example persists layout and command metadata to
`~/.swift-tui-terminal-workspace.json`. It restores new processes at launch.
It does not support process detach and reattach.

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

The focused test makes sure that the initial development and operations
workspace has the expected structure. It also covers the pane identifiers.

## See also

- [DocC reference](https://swifttui.sh/docs/documentation/) — the full `SwiftTUITerminalWorkspace` API surface.
