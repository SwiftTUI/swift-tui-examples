# Gallery

> The flagship component workbench for the public `SwiftTUI` surface: a tabbed terminal workspace that exercises chrome, editing, charts, animated images, and terminal-native presentation in one place, so you can see what the framework ships before you build with it. Its canonical host is the terminal (plus a localhost WebHost via `--web`).

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
| Animations | Five pages (Basics, Transitions, Matched, Keyframes, Transactions) of numbered sections; each section states what to expect and prints the value it animates. `--animations-page <key>` opens a page directly |
| File Drop | File-drop authoring surface |
| Pointer Lab | SpatialTapGesture, DragGesture, long press, contentShape, and named coordinate spaces |
| Focus Context | FocusedValue, FocusedBinding, and toolbar/status consumers of focused child state |
| Progress | Generic task-progress pane with spinner, shimmering title, subtask list, and hidden-item summary |

## Controls

| Key | Action |
| --- | --- |
| `Ctrl+K` | Open the command palette |
| `--tab <key>` | Launch directly on a named tab (CLI flag) |
| `--animations-page <key>` | Launch the Animations tab on a page: `basics`, `transitions`, `matched`, `keyframes`, or `transactions` (CLI flag) |

The gallery exercises the same command and presentation surfaces that apps use.

### Animations

Open a page directly, for example the PhaseAnimator loop on Keyframes:

```bash
swiftly run swift run --package-path gallery gallery-demo --tab animations --animations-page keyframes
```

Every section prints an `expect:` line (what you should see and roughly how
long it takes) and a `state:` line (the value the animation drives), so
"did it animate?" and "did it end where it should?" are answerable from the
screen. Section numbers are stable across pages; cite them in bug reports.

The pages and their sections:

- **Basics**: 1 foreground color, 3 frame, 4 offset, 5 position, 9 completion
  callback.
- **Transitions**: 2 insertion and removal transitions.
- **Matched**: 6 `matchedGeometryEffect` with `properties` and `anchor`
  pickers (section 13, co-present adoption, is skipped; that stage was
  deferred).
- **Keyframes**: 7 `PhaseAnimator` loop (the tab's one always-on loop), 8
  `PhaseAnimator(trigger:)`, 10 `KeyframeAnimator(trigger:)`, 11
  `KeyframeAnimator(repeating:)` (stopped until you press start), 12 a static
  `KeyframeTimeline` curve strip.
- **Transactions**: 14 `withTransaction(\.disablesAnimations, true)`, 15
  `.transaction(value:)`, 16 `.animation(_:body:)` and `.transaction(_:body:)`,
  17 `Transaction.addAnimationCompletion`, 18 `tracksVelocity` fling (drag the
  `◆` with the pointer), 19 `Animation.logicallyComplete(after:)`, 20
  `Binding.animation`.

Set `SWIFTTUI_REDUCE_MOTION=1` to see the static end states without the
interpolation. For a still image, build the gallery first, then run
`Scripts/screenshot_gallery.sh out.png animations` from the repository root
(macOS with kitty; see the script header for permissions).

For a reviewable recording with no terminal involved, run the gated runtime
suite with a frame-strip directory. Each section's test then writes
`<section>.txt`: one block per presented frame with its timestamp and the
section's `state:` line, diffable in any editor:

```bash
GALLERY_RUNTIME_TESTS=1 GALLERY_FRAME_STRIP_DIR=/tmp/gallery-strips \
  swiftly run swift test --package-path gallery --filter AnimationSectionRuntimeTests
```

The rest state of every page (at 96x60 and 80x24) and the section 12 curve
strips are snapshot fixtures under `Tests/GalleryDemoViewsTests/Fixtures/AnimationsTab/`.
After an intentional layout change, refresh them with
`GALLERY_UPDATE_FIXTURES=1 swiftly run swift test --package-path gallery --filter AnimationsTabPagesTests`
and review the diff.

## Test

```bash
swiftly run swift test --package-path gallery
```

The test target covers tab selection, palette composition, text input, and
animation regressions. It also covers WebHost package composition and behavior
of individual tabs.

## See also

- [`terminal-workspace`](../terminal-workspace/README.md): a focused command-palette terminal workspace, narrower than the full gallery.
- [SwiftTUI DocC reference](https://swifttui.sh/docs/documentation/): the public API surface the gallery exercises.
