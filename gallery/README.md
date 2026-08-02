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

Pass `--tab <key>` to open a specific tab for screenshots or manual checks. For
example, pass `--tab images`. Run `gallery-demo --help` for all tab keys.

## Demonstrates

- `SwiftTUI` provides the full app surface. The example uses automatic controls,
  tabbed panes, sidebar navigation, multiline editing, focus, alerts, sheets,
  and popovers.
- `SwiftTUICharts` comes from the separate
  [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package. The
  example renders its charts and `SwiftTUIAnimatedImage` playback in terminal
  cells.
- The `Ctrl+K` command palette demonstrates a workspace pattern. It uses the
  same command and presentation surfaces that apps use.

## Tabs

This example is a full-screen component workbench. It uses tabbed panes,
sidebar navigation, and preview regions. Its local components demonstrate a
terminal workspace with a command palette.

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
| Navigation & Collections | NavigationStack, navigationDestination, OutlineGroup, lazy stacks, list selection, and table selection |
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

The gallery exercises the same command and presentation surfaces that apps use.

## Test

```bash
swiftly run swift test --package-path gallery
```

The test target covers tab selection, palette composition, text input, and
animation regressions. It also covers WebHost package composition and behavior
of individual tabs.

## See also

- [`terminal-workspace`](../terminal-workspace/README.md) — a focused command-palette terminal workspace, narrower than the full gallery.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/) — the public API surface the gallery exercises.
