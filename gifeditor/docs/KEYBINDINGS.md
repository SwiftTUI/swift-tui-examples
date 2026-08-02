# gifeditor keybindings

<!-- Generated from Sources/GIFEditorUI/KeyBindingCatalog.swift by Scripts/generate-keybindings-doc.sh. Do not edit by hand. -->

Focused editor commands use bare keys for standard pixel-editor actions.
Press `?` to open this table in the editor.

The bindings avoid terminal-ambiguous chords such as `Ctrl+Shift+letter`,
`Ctrl+digit`, `Ctrl+[` / `Ctrl+]`, and `Alt+[`.
The terminal input path does not receive these as distinct key presses.

## Tools

| Shortcut        | Action                                                    |
| --------------- | --------------------------------------------------------- |
| `p`             | Pen — paint the primary color                             |
| `e`             | Eraser — clear to transparent                             |
| `b`             | Bucket fill (4-connected)                                 |
| `g`             | Gradient between primary and secondary                    |
| `m`             | Marquee — rectangular selection                           |
| `v`             | Select / move pixels                                      |
| `i`             | Eyedropper — pick the color under the cursor              |
| `r`             | Rectangle — span it from two corners                      |
| `c`             | Ellipse — inscribed in the same two corners               |
| `x`             | Swap primary and secondary color                          |
| `[`             | Decrease brush size                                       |
| `]`             | Increase brush size                                       |
| `f`             | Filled shapes on / off                                    |
| `s`             | Mirror-X symmetry for pen and eraser strokes              |
| `Space / Enter` | Apply the current tool at the cursor (complete a marquee) |
| `Esc`           | Clear selection                                           |

The canvas supports direct pointer editing. Drag with **Pen** or **Eraser** to
paint a connected stroke. Drag with **Marquee** to select a rectangle. Drag
with **Gradient**, **Rectangle**, or **Ellipse** to span the drag endpoints.
Click with **Fill** or **Eyedropper** to select one pixel. Some hosts report
pointer locations in terminal pixels. These hosts can address each half of a
cell independently. A cell-only host uses the top half of each terminal cell.

**Rectangle**, **Ellipse**, and **Gradient** set an anchor on the first press.
They paint on the second press. Both drag directions span the same cells. The
brush size sets the outline thickness. Press `f` to fill the shape. An active
marquee clips shapes and fills.

**Mirror-X** modifies drawing and is not a tool. When it is on, each pen and
eraser stroke is painted twice. The second stroke is reflected across the
vertical center line of the canvas. The canvas sets the reflection axis. A
marquee does not move this axis.

## Transform

| Shortcut | Action                                         |
| -------- | ---------------------------------------------- |
| `H`      | Flip the selection (or the layer) left ↔ right |
| `V`      | Flip the selection (or the layer) top ↔ bottom |
| `R`      | Rotate a quarter turn clockwise                |
| `L`      | Rotate a quarter turn counter-clockwise        |

Flip, rotate, cut, and `Ctrl+C` use the same selection rule. If a marquee
exists, they use its selection. Otherwise, they use the complete current layer.

A quarter turn maps a `w × h` selection to an `h × w` selection. The canvas
size does not change. The marquee moves with its pixels, so the pixels are not
clipped to the old selection. The rotated region keeps its old top-left corner.
If the region crosses an edge, the app moves it back onto the canvas. This
corner-pinned rule prevents half-cell rounding drift for odd dimensions. Four
turns restore the region. Clockwise and counterclockwise turns are inverse
operations. If a rotated selection cannot fit, the app rotates it around the
center and clips the edges. A non-square canvas uses this path for a
whole-canvas turn. Undo restores clipped pixels.

## Cursor

| Shortcut | Action                     |
| -------- | -------------------------- |
| `← / h`  | Move cursor left 1 pixel   |
| `→ / l`  | Move cursor right 1 pixel  |
| `↑ / k`  | Move cursor up 1 pixel     |
| `↓ / j`  | Move cursor down 1 pixel   |
| `Ctrl+←` | Jump cursor left 8 pixels  |
| `Ctrl+→` | Jump cursor right 8 pixels |
| `Ctrl+↑` | Jump cursor up 8 pixels    |
| `Ctrl+↓` | Jump cursor down 8 pixels  |

## Zoom / Pan

| Shortcut | Action                               |
| -------- | ------------------------------------ |
| `-`      | Zoom out one step                    |
| `=`      | Zoom in one step (1× / 2× / 4×)      |
| `0`      | Fit the whole canvas to the window   |
| `Alt+←`  | Pan the viewport left half a screen  |
| `Alt+→`  | Pan the viewport right half a screen |
| `Alt+↑`  | Pan the viewport up half a screen    |
| `Alt+↓`  | Pan the viewport down half a screen  |

Each cursor move keeps the cursor inside the visible rectangle. Thus, keyboard
drawing cannot move off-screen. Panning does not follow the cursor. It lets you
view a different part of the canvas.

Bare digits select colors. `Alt`-digits change frame timing. The two adjacent
symbols change the view scale.

## Frames / Timeline

| Shortcut | Action                                                                          |
| -------- | ------------------------------------------------------------------------------- |
| `Alt+,`  | Previous frame                                                                  |
| `Alt+.`  | Next frame                                                                      |
| `Ctrl+N` | New blank frame after current                                                   |
| `Ctrl+D` | Duplicate current frame after current                                           |
| `Alt+D`  | Delete current frame                                                            |
| `<`      | Move current frame one position earlier                                         |
| `>`      | Move current frame one position later                                           |
| `,`      | Move current frame to the start of the timeline                                 |
| `.`      | Move current frame to the end of the timeline                                   |
| `Alt+-`  | Decrease current frame delay (10 cs)                                            |
| `Alt+=`  | Increase current frame delay (10 cs)                                            |
| `Alt+0`  | Set every frame delay to the current one                                        |
| `d`      | Cycle the current frame's disposal (background / keep / previous / unspecified) |
| `_`      | One fewer play of the exported GIF                                              |
| `+`      | One more play of the exported GIF                                               |
| `)`      | Toggle looping forever (the format's zero)                                      |
| `Alt+P`  | Toggle playback                                                                 |

The `,` / `.` key pair controls the timeline. With `Alt`, the keys move the
selection between frames. The shifted `<` / `>` keys move the current frame by
one position. The bare keys move it to an end.

The loop count belongs to the exported file, not the editor preview. It sets
the GIF `NETSCAPE2.0` block. The format uses zero for "forever". Thus, `)`, the
shifted `0`, toggles this value. The readout shows the word instead of the
digit.

## Onion Skin

| Shortcut | Action                                                     |
| -------- | ---------------------------------------------------------- |
| `o`      | Toggle onion skin                                          |
| `O`      | Cycle which neighbors are ghosted (both / previous / next) |
| `{`      | One fewer ghost frame per side                             |
| `}`      | One more ghost frame per side (max 3)                      |

Onion skin shows neighboring frames *under* the current frame. It does not
change the current frame. Ghosts are visible only through transparent pixels.
Earlier frames have a cool tint, and later frames have a warm tint. More
distant ghosts are fainter. Thus, the terminal palette shows direction and
distance.

Ghosting does not wrap. The first frame has no previous ghost. The last frame
has no next ghost. This rule prevents a distant end frame from looking like an
adjacent frame.

Onion skin changes only the display. It does not affect the eyedropper,
exported GIF, or saved project. Toggling it does not mark the document as
changed. A change to the ghost count or side turns onion skin on.

## Layers

| Shortcut | Action                          |
| -------- | ------------------------------- |
| `Alt+N`  | New empty layer above current   |
| `Alt+J`  | Select layer below              |
| `Alt+K`  | Select layer above              |
| `Alt+H`  | Toggle current layer visibility |
| `Alt+X`  | Delete current layer            |

## Clipboard

| Shortcut | Action                                      |
| -------- | ------------------------------------------- |
| `X`      | Cut selection (or the whole layer if none)  |
| `Ctrl+C` | Copy selection (or the whole layer if none) |
| `Ctrl+V` | Paste at cursor                             |

## History

| Shortcut | Action                  |
| -------- | ----------------------- |
| `Ctrl+Z` | Undo last document edit |
| `Ctrl+Y` | Redo last undone edit   |

## Palette / Colors

| Shortcut      | Action                                    |
| ------------- | ----------------------------------------- |
| `1…9`         | Pick palette slot 1–9 as primary          |
| `Alt+1…Alt+9` | Pick palette slot 1–9 as secondary        |
| `Ctrl+P`      | Open the palette editor (Edit → Palette…) |

The palette editor changes slot colors in hex or R/G/B. It adds, removes,
sorts, and compacts slots. It also imports Lospec `.hex` and GIMP `.gpl` files.
Remove, sort, compact, and import operations renumber the slots. Each operation
is one undoable edit. The edit also renumbers the artwork, so its colors do not
change. Slot 0 is the transparency sentinel and never moves.

## File / App

| Shortcut     | Action                                                 |
| ------------ | ------------------------------------------------------ |
| `Ctrl+Alt+N` | New… — start a fresh document at a chosen size         |
| `Ctrl+O`     | Open… — load a GIF or a `.halfcell` project            |
| `Ctrl+S`     | Save the layered project                               |
| `Alt+S`      | Save As… — always prompts for a project path           |
| `Ctrl+E`     | Export GIF… — write a flattened copy                   |
| `Ctrl+R`     | Resize canvas… (presets 16…256, or any width × height) |
| `Ctrl+Q`     | Quit — prompts when there are unsaved changes          |

`Save` writes a layered `.halfcell` project to its current path. If the
document came from a GIF, `Save` opens `Save As…`. Thus, `Save` cannot flatten
a layered document without notice. `Export GIF…` flattens the document and
leaves it unsaved. `New…`, `Open…`, and quit use the same unsaved-changes
guard.

The New and Resize interfaces limit each axis to 256 pixels. The project format
has no such limit. The loader opens GIFs with other dimensions.

## Help

| Shortcut | Action                       |
| -------- | ---------------------------- |
| `?`      | Show this keyboard reference |
