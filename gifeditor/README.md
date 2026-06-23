# GIF Editor

A terminal-native, frame-by-frame animated-GIF editor: paint on a color canvas where one GIF pixel maps to one terminal half-cell, wield a pen / eraser / fill / gradient / marquee toolbox by keyboard or pointer, and read and write real GIF89a files — all in the terminal (and over a localhost WebHost via `--web`).

## Run

```bash
swiftly run swift run --package-path gifeditor gifeditor
```

```bash
swiftly run swift run --package-path gifeditor gifeditor gifeditor/nyan.gif   # edit a real GIF instead of a fresh 32x32 document
```

After making edits, press `Ctrl+S` or `Alt+S` to open the save sheet. The sheet previews the encoded GIF that will be written, lets you adjust the destination path, and requires explicit confirmation before overwriting an existing file.

## Demonstrates

- `SwiftTUI` Canvas — which means a half-block color grid renders one GIF pixel per terminal half-cell, with sub-cell pointer locations mapped onto GIF pixels for direct painting.
- `SwiftTUIWebHostCLI` — the same terminal app hosts itself over a localhost browser session, so one executable serves both surfaces without a separate web build.
- A pure value-type document model with bounded undo / redo and a vendored GIF89a encoder/decoder bridge (`EditorGIF`) — which means canvas behavior and round-trip fidelity are testable without any UI.

## Target boundaries

This is an advanced application and regression sample, not starter tutorial code. Copy the target boundaries and host pattern selectively rather than the whole editor. The example is intentionally split across four targets so it can grow into a multi-platform app later without restructuring:

| Target           | Role                                            | Depends on                       |
| ---------------- | ----------------------------------------------- | -------------------------------- |
| `GIFEditorCore`  | Pure model + GIF encoder/decoder bridge         | `EditorGIF`, Foundation          |
| `GIFEditorUI`    | Terminal `View` tree + view model               | `SwiftTUI`, `GIFEditorCore`      |
| `GIFEditor`      | Composition root (entry point factory)          | `GIFEditorUI`, `SwiftTUI`        |
| `gifeditor`      | Executable that hosts the terminal/WebHost app  | `GIFEditor`, `SwiftTUIWebHostCLI` |

A future SwiftUI / UIKit port would reuse `GIFEditorCore` verbatim and add a parallel `GIFEditorUI_SwiftUI` target alongside `GIFEditorUI`.

## Editing model

* The document carries a fixed-size **indexed-color frame buffer** (`UInt8?` per pixel — `nil` means transparent) plus a shared **256-slot palette**.
* Every frame is a stack of **layers** painted bottom-to-top. The bottom layer's transparent pixels show the canvas's background color; higher layers' transparent pixels show whatever painted below them on the same frame.
* Document edits are captured in a bounded undo / redo stack. Pointer strokes and pointer-applied gradients are grouped as single history entries.
* The exporter flattens layers per frame, then writes a GIF89a file using a single global color table. Each frame is written with `.background` disposal so frames fully replace their predecessors — easy to reason about and matches the editor's "fully painted frame" mental model.

## What to copy

- For reusable app code, copy the split between pure model code (`GIFEditorCore`) and SwiftTUI-specific view code (`GIFEditorUI`).
- For a terminal app with optional localhost browser hosting, copy the thin executable shape that depends on `SwiftTUIWebHostCLI`.
- For testable canvas behavior, copy the value-type document model and focused model/UI tests. The menu layout, keybindings, and editor-specific command set are application code, not required SwiftTUI structure.

## Controls

The README keeps the copyable architecture and target-boundary guidance up front; the full shortcut table is editor-specific reference material. Read [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md) for the complete shortcut table.

## Test

```bash
swiftly run swift test --package-path gifeditor
```

The suite verifies:

* The `swift-gif` encoder bridge produces output the decoder can read back pixel-for-pixel for a hand-built document and a round-trip of `nyan.gif`.
* Document edits (pen, fill, gradient, marquee copy/paste) leave the model in expected states.
* The terminal UI renders the editor canvas through a Canvas-backed half-block color grid and maps sub-cell pointer locations onto GIF pixels.

## See also

- [`webexample`](../WebExample/README.md) — the dedicated browser/WASI deployment example.
- DocC reference: <https://swifttui.sh/docs/documentation/>
