# Gallery

> The flagship component workbench for the public `SwiftTUI` surface — a tabbed terminal workspace that exercises chrome, editing, charts, animated images, and terminal-native presentation in one place, so you can see what the framework ships before you build with it. Its canonical host is the terminal (plus a localhost WebHost via `--web`).

## Run

```bash
swiftly run swift run --package-path gallery gallery-demo
```

Run the same gallery through the batteries-included WebHost mode:

```bash
swiftly run swift run --package-path gallery gallery-demo --web
```

Pass `--tab <key>` to land on a specific tab for screenshots or manual checks, for example `--tab images`. Run `gallery-demo --help` for the full list of tab keys.

## Demonstrates

- `SwiftTUI` — which means the full app surface: automatic chrome, tabbed panes, sidebar navigation, multiline editing, focus, and terminal-native alert/sheet/popover presentation.
- `SwiftTUICharts` (from the separate [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package) and `SwiftTUIAnimatedImage` — which means drop-in charting and animated-image playback rendered directly into terminal cells.
- Command-palette-driven workspace patterns (`Ctrl+K`) — which means the same command and presentation surfaces app authors use, composed locally as an example.

## Tabs

This example app is a full-screen component workbench. It is designed to feel like a terminal workspace rather than a scrolled showcase page, using tabbed panes, sidebar navigation, and preview regions, and mirrors command-palette-driven terminal workspace patterns through local example composition.

| Tab | Coverage |
| --- | --- |
| Logo Breaker | Brick-breaker logo game with truecolor logo cells, drag/release, and bouncing ball physics |
| Counter | Basic state mutation and button input |
| Life | Custom rendering and simulation state |
| Todo | Lists, editing, deletion, and selection |
| Forms & Containers | GroupBox, ControlGroup, DisclosureGroup, Link, picker styles, button styles, text-field styles, disabled state, and accessibility metadata |
| Text Input | Text fields, text editor behavior, focus, and paste |
| Scroll Control | Programmatic scroll movement and bound scroll position |
| Calculator | Click targets and compact control layout |
| Borders & Shapes | Shape drawing, borders, and panel chrome |
| Presentation Lab | alert, confirmationDialog, sheet, toast, boolean and item popovers, popoverTip, and paletteSheet |
| Navigation & Collections | Typed NavigationStack paths, navigationDestination, navigationTitle, OutlineGroup, lazy stacks, list selection, and table selection |
| Images | Image attachments, rendered image placement, and `SwiftTUIAnimatedImage` playback |
| Animations | Runtime invalidation and animated presentation |
| File Drop | File-drop authoring surface |
| Pointer Lab | SpatialTapGesture, DragGesture, long press, contentShape, and named coordinate spaces |
| Focus Context | FocusedValue, FocusedBinding, and toolbar/status consumers of focused child state |
| Progress | Generic task-progress pane with spinner, shimmering title, subtask list, and hidden-item summary |

## Controls

| Key | Action |
| --- | --- |
| `Ctrl+K` | Open the command palette |
| `--tab <key>` | Launch directly on a named tab (CLI flag) |

The gallery intentionally exercises the same command and presentation surfaces that app authors use.

## Test

```bash
swiftly run swift test --package-path gallery
```

The test target covers tab switching, palette composition, text input, animation regressions, WebHost package composition, and focused behavior for individual tabs.

## See also

- [`terminal-workspace`](../terminal-workspace/README.md) — a focused command-palette terminal workspace, narrower than the full gallery.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/) — the public API surface the gallery exercises.
