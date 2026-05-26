# gifeditor

A terminal-native GIF editor built on **swift-tui**. Read and write
animated GIFs, edit them frame-by-frame on a color canvas where one GIF pixel
maps to one terminal half-cell, and use a small toolbox of pen / eraser / fill /
gradient / marquee tools with keyboard or pointer input.

This is an advanced application and regression sample, not starter tutorial
code. Copy the target boundaries and host pattern selectively rather than the
whole editor.

This example is intentionally split across four targets so it can grow into a
multi-platform app later without restructuring:

| Target           | Role                                         | Depends on             |
| ---------------- | -------------------------------------------- | ---------------------- |
| `GIFEditorCore`  | Pure model + GIF encoder/decoder bridge      | `EditorGIF`, Foundation |
| `GIFEditorUI`    | Terminal `View` tree + view model            | `SwiftTUI`, `GIFEditorCore` |
| `GIFEditor`      | Composition root (entry point factory)       | `GIFEditorUI`, `SwiftTUI` |
| `gifeditor`      | Executable that hosts the terminal/WebHost app | `GIFEditor`, `SwiftTUIWebHostCLI` |

A future SwiftUI / UIKit port would reuse `GIFEditorCore` verbatim and add a
parallel `GIFEditorUI_SwiftUI` target alongside `GIFEditorUI`.

## What to copy

- For reusable app code, copy the split between pure model code
  (`GIFEditorCore`) and SwiftTUI-specific view code (`GIFEditorUI`).
- For a terminal app with optional localhost browser hosting, copy the thin
  executable shape that depends on `SwiftTUIWebHostCLI`.
- For testable canvas behavior, copy the value-type document model and focused
  model/UI tests. The menu layout, keybindings, and editor-specific command set
  are application code, not required SwiftTUI structure.

## Run

```bash
cd gifeditor
swiftly run swift run gifeditor                       # launch with a fresh 32x32 document
swiftly run swift run gifeditor ../../nyan.gif        # launch editing a real GIF
```

After making edits, press `Ctrl+S` to save (back to the source path or to
`./untitled.gif` for new documents). Use `Alt+S` to save-as a new path.

## Keybindings

Press `?` in the editor for the in-app shortcut reference, or read
[docs/KEYBINDINGS.md](docs/KEYBINDINGS.md). The README keeps the copyable
architecture and target-boundary guidance up front; the full shortcut table is
editor-specific reference material.

## Editing model

* The document carries a fixed-size **indexed-color frame buffer** (`UInt8?`
  per pixel — `nil` means transparent) plus a shared **256-slot palette**.
* Every frame is a stack of **layers** painted bottom-to-top. The bottom
  layer's transparent pixels show the canvas's background color; higher
  layers' transparent pixels show whatever painted below them on the same
  frame.
* Document edits are captured in a bounded undo / redo stack. Pointer strokes
  and pointer-applied gradients are grouped as single history entries.
* The exporter flattens layers per frame, then writes a GIF89a file using a
  single global color table. Each frame is written with `.background`
  disposal so frames fully replace their predecessors — easy to reason about
  and matches the editor's "fully painted frame" mental model.

## Tests

```bash
cd gifeditor
swiftly run swift test
```

The core test suite verifies:

* The `swift-gif` encoder bridge produces output the decoder can read back
  pixel-for-pixel for a hand-built document and a round-trip of `nyan.gif`.
* Document edits (pen, fill, gradient, marquee copy/paste) leave the model
  in expected states.
* The terminal UI renders the editor canvas through a Canvas-backed half-block
  color grid and maps sub-cell pointer locations onto GIF pixels.
