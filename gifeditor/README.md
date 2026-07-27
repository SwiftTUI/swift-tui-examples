# GIF Editor

A terminal-native, frame-by-frame animated-GIF editor: paint on a color canvas where one GIF pixel maps to one terminal half-cell, wield a keyboard- or pointer-driven toolbox, and read and write real GIF89a files — all in the terminal (and over a localhost WebHost via `--web`).

## Run

```bash
swiftly run swift run --package-path gifeditor gifeditor
```

```bash
swiftly run swift run --package-path gifeditor gifeditor gifeditor/nyan.gif   # edit a real GIF instead of a fresh 32x32 document
```

Press `?` for the keyboard overlay — every shortcut the editor answers to, rendered from the same table that generates [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md). `Ctrl+Q` quits, prompting when there is unsaved work.

## Demonstrates

- `SwiftTUI` Canvas — which means a half-block color grid renders one GIF pixel per terminal half-cell, with sub-cell pointer locations mapped onto GIF pixels for direct painting.
- `SwiftTUIWebHostCLI` — the same terminal app hosts itself over a localhost browser session, so one executable serves both surfaces without a separate web build.
- Sheets, a menu bar, a scrolling overlay and a modal unsaved-changes guard composed into one screen that still fits an 80×24 terminal.
- A pure value-type document model with bounded undo / redo and a vendored GIF89a encoder/decoder bridge (`EditorGIF`) — which means canvas behavior and round-trip fidelity are testable without any UI.
- One command surface serving two modes: with no subcommand the executable is the editor, and `info` / `optimize` / `export` are headless verbs over the same model code.

## Target boundaries

This is an advanced application and regression sample, not starter tutorial code. Copy the target boundaries and host pattern selectively rather than the whole editor. The example is intentionally split so it can grow into a multi-platform app later without restructuring:

| Target          | Role                                              | Depends on                        |
| --------------- | ------------------------------------------------- | --------------------------------- |
| `EditorGIF`     | Vendored GIF89a encoder / decoder                 | —                                 |
| `GIFEditorCore` | Pure model, tools, encoders, project format       | `EditorGIF`, Foundation           |
| `GIFEditorUI`   | Terminal `View` tree + view model                 | `SwiftTUI`, `GIFEditorCore`       |
| `GIFEditor`     | Composition root and the headless subcommands     | `GIFEditorUI`, `SwiftTUI`         |
| `GIFEditorApp`  | The `gifeditor` executable, terminal or WebHost   | `GIFEditor`, `SwiftTUIWebHostCLI` |

A future SwiftUI / UIKit port would reuse `GIFEditorCore` verbatim and add a parallel `GIFEditorUI_SwiftUI` target alongside `GIFEditorUI`.

## Editing model

- The document carries a fixed-size **indexed-color frame buffer** (`UInt8?` per pixel — `nil` means transparent) plus a shared **256-slot palette** whose slot 0 is the reserved transparency sentinel.
- Every frame is a stack of **layers** painted bottom-to-top. A layer's transparent pixels show whatever painted below it on the same frame.
- Tools: pen, eraser, bucket fill, gradient, marquee, move, eyedropper, and rectangle / ellipse shapes that span two corners. Selections clip the tools that respect them; a mirror-X mode lays every pen and eraser stroke twice about the canvas's vertical centre line.
- Transforms flip and quarter-turn either the selection or the whole layer.
- The palette is editable in place — add, remove, sort, compact, and import a Lospec `.hex` or GIMP `.gpl` file — and every reorder renumbers the artwork in the same undoable edit, so nothing recolors. Slot 0 is pinned and never moves.
- The timeline owns frame order, per-frame delay, per-frame disposal and the loop count. Onion skin ghosts neighbouring frames over the canvas without touching the document.
- The canvas zooms and pans independently of the document; zoom is a view concern and is never saved.
- Document edits are captured in a bounded undo / redo stack. Pointer strokes and pointer-applied gradients are grouped as single history entries.

## Files

- **`.halfcell` is the project format** — a versioned JSON envelope around the whole document, layers and palette order included. It is what `Save` writes and the only lossless representation.
- **GIF is an export.** `Export GIF…` flattens every layer, so saving a layered document as GIF and reopening it comes back as one opaque layer per frame. `Save` on a document that came from a GIF therefore falls through to `Save As…` rather than quietly flattening it.
- The exporter trims the global color table to the colors the document actually uses, and writes frames after the first as the changed rectangle under `.keep` disposal — unless the author wrote a disposal of their own, which is honoured verbatim at full-canvas size instead.
- Opening routes on content rather than on the extension, so a project saved without one, or a GIF someone renamed, still reaches the right reader. A project file is treated as untrusted input: every invariant a renderer indexes without asking is re-established on decode, and a damaged file is reported rather than trapped on.
- Unsaved work is autosaved to a state directory and offered back on the next launch; `New`, `Open` and quitting all pass through the same unsaved-changes guard.

## Headless subcommands

The editor is the root command, so the verbs sit beside it rather than under a group:

```bash
gifeditor info nyan.gif                        # what is in this file (add --json)
gifeditor optimize in.gif -o out.gif           # re-encode and report the size change
gifeditor export in.gif --spritesheet -o sheet # PNG grid plus a JSON frame map
gifeditor export in.gif --frames -o ./out      # one zero-padded PNG per frame
gifeditor export in.gif --apng -o out.png      # a single animated PNG
```

All of them read both formats and run the same `GIFEditorCore` code the editor does.

## What to copy

- For reusable app code, copy the split between pure model code (`GIFEditorCore`) and SwiftTUI-specific view code (`GIFEditorUI`).
- For a terminal app with optional localhost browser hosting, copy the thin executable shape that depends on `SwiftTUIWebHostCLI`.
- For an app that is also a CLI, copy `GIFEditorApp.main()` — a root command with a positional argument shadows its own subcommands, and the comment there explains the one-level-up workaround.
- For testable canvas behavior, copy the value-type document model and focused model/UI tests. The menu layout, keybindings, and editor-specific command set are application code, not required SwiftTUI structure.

## Controls

`?` opens the keyboard overlay in the app; `↑↓`, `PgUp`/`PgDn` and `Home`/`End` scroll it. [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md) is the same table on disk, generated from `KeyBindingCatalog` by `Scripts/generate-keybindings-doc.sh` with a test that fails when the two disagree.

## Test

```bash
swiftly run swift test --package-path gifeditor
```

The suite verifies:

- The `swift-gif` encoder bridge produces output the decoder can read back pixel-for-pixel for hand-built documents and a round-trip of `nyan.gif`, including the delta-coded and full-frame codings agreeing on every rendered pixel.
- Document edits (pen, fill, gradient, shapes, transforms, marquee copy/paste, palette edits) leave the model in expected states.
- The project format round-trips, and a corpus of malformed files is rejected rather than trapped on.
- The terminal UI renders the editor canvas through a Canvas-backed half-block color grid and maps sub-cell pointer locations onto GIF pixels.
- Real key presses through a real run loop reach the editor, the sheets and the keyboard overlay.

## See also

- [`webexample`](../WebExample/README.md) — the dedicated browser/WASI deployment example.
- DocC reference: <https://swifttui.sh/docs/documentation/>
