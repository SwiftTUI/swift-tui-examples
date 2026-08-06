# GIF Editor

This terminal-native app edits animated GIFs one frame at a time. One GIF pixel
maps to one terminal half-cell on the color canvas. You can use the keyboard or
pointer tools. The app reads and writes GIF89a files. It runs in the terminal
and through a local WebHost with `--web`.

## Run

```bash
swiftly run swift run --package-path gifeditor gifeditor
```

```bash
swiftly run swift run --package-path gifeditor gifeditor gifeditor/nyan.gif   # edit a real GIF instead of a fresh 32x32 document
```

Press `?` to open the keyboard overlay. The same table generates
[docs/KEYBINDINGS.md](docs/KEYBINDINGS.md). Press `Ctrl+Q` to quit. If the
document has unsaved work, the app asks for a decision.

## Demonstrates

- A `SwiftTUI` Canvas renders one GIF pixel in each terminal half-cell. It maps
  sub-cell pointer locations to GIF pixels for direct painting.
- `SwiftTUIWebHostCLI` hosts the terminal app in a local browser session. One
  executable serves both surfaces without a separate web build.
- One 80×24 screen contains sheets, a menu bar, a scrolling overlay, and an
  unsaved-changes guard.
- The document is a pure value type with bounded undo and redo. The vendored
  `EditorGIF` bridge encodes and decodes GIF89a data. Tests can make sure that
  canvas behavior and round-trip fidelity are correct without a UI.
- One command surface has two modes. Without a subcommand, the executable opens
  the editor. `info`, `optimize`, and `export` run without a UI on the same
  model code.

## Target boundaries

This is an advanced application and regression sample, not starter tutorial
code. Copy selected target boundaries and host patterns. Do not copy the
complete editor as a tutorial. The target split supports additional platforms
without a restructure:

| Target          | Role                                              | Depends on                        |
| --------------- | ------------------------------------------------- | --------------------------------- |
| `EditorGIF`     | Vendored GIF89a encoder / decoder                 | —                                 |
| `GIFEditorCore` | Pure model, tools, encoders, project format       | `EditorGIF`, Foundation           |
| `GIFEditorUI`   | Terminal `View` tree + view model                 | `SwiftTUI`, `GIFEditorCore`       |
| `GIFEditor`     | Composition root and the headless subcommands     | `GIFEditorUI`, `SwiftTUI`         |
| `GIFEditorApp`  | The `gifeditor` executable, terminal or WebHost   | `GIFEditor`, `SwiftTUIWebHostCLI` |

A SwiftUI or UIKit port can reuse `GIFEditorCore`. It can add a parallel
`GIFEditorUI_SwiftUI` target next to `GIFEditorUI`.

## Editing model

- The document has a fixed-size **indexed-color frame buffer**. Each pixel is a
  `UInt8?`, where `nil` means transparent. A shared palette has 256 slots. Slot
  0 is the reserved transparency sentinel.
- Each frame is a stack of **layers** painted from bottom to top. Transparent
  pixels show painted pixels on lower layers of the same frame.
- The tools are pen, eraser, bucket fill, gradient, marquee, move, eyedropper,
  rectangle, and ellipse. Rectangle and ellipse shapes span two corners.
  Selections clip applicable tools. Mirror-X mode copies pen and eraser strokes
  across the vertical center line of the canvas.
- Transforms flip and quarter-turn either the selection or the whole layer.
- You can add, remove, sort, and compact palette entries. You can also import a
  Lospec `.hex` or GIMP `.gpl` file. Each reorder renumbers the artwork in one
  undoable edit. Thus, colors do not change. Slot 0 never moves.
- The timeline owns frame order, frame delay, frame disposal, and loop count.
  Onion skin shows neighboring frames over the canvas without changing the
  document.
- The canvas zooms and pans independently of the document. Zoom is a view state
  and is not saved.
- A bounded undo and redo stack records document edits. One pointer stroke or
  pointer-applied gradient creates one history entry.

## Files

- **`.halfcell` is the project format.** It is a versioned JSON envelope for the
  complete document. The document includes layers and palette order. `Save` writes this
  format. It is the only lossless representation.
- **GIF is an export.** `Export GIF…` flattens all layers. When you reopen the
  GIF, each frame has one opaque layer. If a document came from a GIF, `Save`
  opens `Save As…`. It does not flatten the document without notice.
- The exporter limits the global color table to colors that the document uses.
  After the first frame, it writes the changed rectangle with `.keep` disposal.
  An authored disposal overrides this behavior. The exporter writes that
  disposal at full-canvas size.
- The reader detects content instead of relying on the file extension. Thus,
  it can open a project without an extension or a renamed GIF. The decoder
  treats a project file as untrusted input. It restores each invariant that the
  renderer requires. It reports a damaged file instead of stopping with a
  trap.
- The app automatically saves unsaved work to a state directory. At the next
  launch, it offers to restore that work. `New`, `Open`, and quit use the same
  unsaved-changes guard.

## Headless subcommands

The editor is the root command, so the verbs sit beside it rather than under a group:

```bash
gifeditor info nyan.gif                        # what is in this file (add --json)
gifeditor optimize in.gif -o out.gif           # re-encode and report the size change
gifeditor export in.gif --spritesheet -o sheet # PNG grid plus a JSON frame map
gifeditor export in.gif --frames -o ./out      # one zero-padded PNG per frame
gifeditor export in.gif --apng -o out.png      # a single animated PNG
```

All subcommands read both formats. They use the same `GIFEditorCore` code as the
editor.

## What to copy

- For reusable app code, copy the split between `GIFEditorCore` model code and
  `GIFEditorUI` view code.
- For optional local browser hosting, copy the small executable that depends on
  `SwiftTUIWebHostCLI`.
- For an app that is also a CLI, copy `GIFEditorApp.main()`. A root command with
  a positional argument hides its subcommands. The source comment explains the
  one-level-up solution.
- For testable canvas behavior, copy the value-type document model and focused
  model and UI tests. The menu, key bindings, and editor commands are app code.
  SwiftTUI does not require this structure.

## Controls

Press `?` to open the keyboard overlay. Use `↑↓`, `PgUp`/`PgDn`, or
`Home`/`End` to scroll it. [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md) contains
the same table. `Scripts/generate-keybindings-doc.sh` generates it from
`KeyBindingCatalog`. A test fails if the tables differ.

## Test

```bash
swiftly run swift test --package-path gifeditor
```

The suite covers these contracts:

- The `swift-gif` encoder bridge produces output that the decoder reads back
  pixel for pixel. Tests use hand-built documents and a `nyan.gif` round trip.
  Delta and full-frame encodings produce the same pixels.
- Pen, fill, gradient, shape, transform, marquee, clipboard, and palette edits
  leave the model in the expected states.
- The project format completes a round trip. The decoder rejects a corpus of
  malformed files without a trap.
- The terminal UI renders the editor canvas as a half-block color grid. It maps
  sub-cell pointer locations to GIF pixels.
- Real key presses through a real run loop reach the editor, sheets, and
  keyboard overlay.

## See also

- [`swift-tui-counter-demo`](https://github.com/SwiftTUI/swift-tui-counter-demo/tree/main/WebExample) — the dedicated browser/WASI deployment demo (own repo).
- DocC reference: <https://swifttui.sh/docs/documentation/>
