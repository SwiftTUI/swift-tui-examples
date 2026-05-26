# Component Gallery

This example app is a full-screen component workbench for the public
`SwiftTUI` surface.

It is designed to feel like a terminal workspace rather than a scrolled
showcase page. The gallery uses tabbed panes, sidebar navigation, and preview
regions to exercise the current automatic chrome, multiline editing,
indeterminate progress, and terminal-native alert presentation. It also mirrors
command-palette-driven terminal workspace patterns through local example
composition.

## Run

```bash
swiftly run swift run --package-path gallery gallery-demo
```

Run the same gallery through the opt-in embedded WebHost runner:

```bash
swiftly run swift run --package-path gallery gallery-demo --web
```

Set `GALLERY_INITIAL_TAB` to land on a specific tab for screenshots or manual
checks, for example `GALLERY_INITIAL_TAB=images`.

## Tabs

| Tab | Coverage |
| --- | --- |
| Counter | Basic state mutation and button input |
| Life | Custom rendering and simulation state |
| Todo | Lists, editing, deletion, and selection |
| Forms & Containers | GroupBox, ControlGroup, DisclosureGroup, Link, picker styles, button styles, text-field styles, disabled state, and accessibility metadata |
| Text Input | Text fields, text editor behavior, focus, and paste |
| Scroll Control | Programmatic scroll movement and bound scroll position |
| Calculator | Click targets and compact control layout |
| Borders & Shapes | Shape drawing, borders, and panel chrome |
| Presentation Lab | alert, confirmationDialog, sheet, toast, popover, popoverTip, and paletteSheet |
| Navigation & Collections | NavigationStack, navigationDestination, OutlineGroup, lazy stacks, list selection, and table selection |
| Images | Image attachments, rendered image placement, and `SwiftTUIAnimatedImage` playback |
| Animations | Runtime invalidation and animated presentation |
| File Drop | File-drop authoring surface |
| Popovers | Anchored popover presentation and palette composition |
| Pointer Lab | SpatialTapGesture, DragGesture, long press, contentShape, and named coordinate spaces |
| Focus Context | FocusedValue, FocusedBinding, and toolbar/status consumers of focused child state |
| Physics | Gesture-driven full-screen toy surface |
| Progress | Generic task-progress pane with spinner, shimmering title, subtask list, and hidden-item summary |

`Ctrl+K` opens the command palette. The gallery intentionally exercises the
same command and presentation surfaces that app authors use.

## Test

```bash
swiftly run swift test --package-path gallery
```

The test target covers tab switching, palette composition, text input,
animation regressions, WebHost package composition, and focused behavior for
individual tabs.
