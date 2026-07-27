# gifeditor keybindings

<!-- Generated from Sources/GIFEditorUI/KeyBindingCatalog.swift by Scripts/generate-keybindings-doc.sh. Do not edit by hand. -->

Focused editor commands use bare keys where they map to ordinary pixel-editor
actions. Press `?` in the editor for the same table without leaving the
terminal.

The bindings avoid terminal-ambiguous chords such as `Ctrl+Shift+letter`,
`Ctrl+digit`, `Ctrl+[` / `Ctrl+]`, and `Alt+[`, because the current terminal
input path does not receive those as distinct key presses.

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
| `Space / Enter` | Apply the current tool at the cursor (confirms a marquee) |
| `Esc`           | Clear selection                                           |

The canvas also supports direct pointer editing. Drag with **Pen** or
**Eraser** to paint connected strokes, drag with **Marquee** to select a
rectangle, drag with **Gradient**, **Rectangle** or **Ellipse** to span the
shape between the drag endpoints, and click with **Fill** or **Eyedropper** to
target a single pixel. Hosts that report terminal-pixel pointer locations can
address the top and bottom half of a cell independently; cell-only hosts fall
back to the top half of each terminal cell.

**Rectangle** and **Ellipse** anchor on the first press and paint on the
second, exactly as the gradient does, and either drag order spans the same
cells. The brush size is the outline's thickness until `f` fills them, and an
active marquee clips them the way it clips a fill.

**Mirror-X** is a modifier on drawing rather than a tool: while it is on, every
pen and eraser stroke is laid twice, once as drawn and once reflected across
the canvas's vertical centre line. The axis is the canvas, not the selection,
so moving a marquee cannot move the line a drawing was made symmetric about.

## Transform

| Shortcut | Action                                         |
| -------- | ---------------------------------------------- |
| `H`      | Flip the selection (or the layer) left ↔ right |
| `V`      | Flip the selection (or the layer) top ↔ bottom |
| `R`      | Rotate a quarter turn clockwise                |
| `L`      | Rotate a quarter turn counter-clockwise        |

Flip, rotate and cut act on the marquee selection when there is one and on the
whole current layer when there is not — the same rule `Ctrl+C` follows, so all
four verbs answer "what if nothing is selected?" the same way.

A quarter turn needs an `h × w` region to land a `w × h` one in, which a
fixed-size canvas does not have. The rule is uniform rather than special-cased:
rotate about the region's centre and clip. A square region therefore turns
losslessly and four turns are the identity, while a non-square one drops
whatever turns past its edge — undo is what brings those pixels back.

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

Every cursor move keeps the cursor inside the visible rect, so keyboard drawing
can't walk off-screen. Panning is the one action that deliberately does *not*
follow the cursor — looking somewhere the cursor is not is its entire purpose.

The digit row stays consistent: bare digits pick colors, `Alt`-digits touch
frame timing, and the two symbols beside them scale the view.

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

The `,` / `.` key pair is the timeline's: `Alt` walks the selection between
frames, the shifted spellings `<` / `>` move the current frame one slot, and
the bare keys send it all the way to either end.

The loop count is the *exported file's*, not the editor's preview: it is what
the GIF's `NETSCAPE2.0` block will declare. The format spells "forever" as
zero, which is why `)` — the shifted `0` — is what toggles it, and why the
readout says the word rather than the digit.

## Onion Skin

| Shortcut | Action                                                      |
| -------- | ----------------------------------------------------------- |
| `o`      | Toggle onion skin                                           |
| `O`      | Cycle which neighbours are ghosted (both / previous / next) |
| `{`      | One fewer ghost frame per side                              |
| `}`      | One more ghost frame per side (max 3)                       |

Onion skin ghosts the neighbouring frames *underneath* the current one, so the
frame you are drawing is never altered — ghosts show through only where it is
transparent. Earlier frames are tinted cool and later ones warm, and each
further ghost is fainter, so both direction and distance stay readable in a
terminal's palette where dimming alone would not be.

Ghosting does not wrap: at the first frame there is nothing before it and at
the last nothing after. Wrapping would draw the first frame against content the
whole animation away at exactly the intensity a real neighbour gets, with no
way to tell the two apart.

Onion skin is display only. It never reaches the eyedropper, the exported GIF
or the saved project, and toggling it does not mark the document dirty.
Changing the ghost count or the ghosted side turns it on, because neither key
has any other visible effect.

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

The palette editor edits slot colors (hex or R/G/B), adds and removes slots,
sorts by brightness, compacts duplicates, and imports Lospec `.hex` / GIMP
`.gpl` files. Removing, sorting, compacting and importing renumber slots; each
is a single undoable edit that renumbers the artwork with them, so nothing
recolors. Slot 0 is the transparency sentinel and never moves.

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

`Save` writes the layered `.halfcell` project back to its own path, and falls
through to `Save As…` when the document came from a GIF — writing a layered
document over an export would flatten every layer under a verb that promises
the opposite. `Export GIF…` is the verb that *does* flatten, and it leaves the
document unsaved. `New…`, `Open…` and quitting all pass through the same
unsaved-changes guard.

The 256-per-axis limit is a New/Resize UI cap, not a format one: the project
format stores arbitrary dimensions and the loader opens any GIF it is given.

## Help

| Shortcut | Action                       |
| -------- | ---------------------------- |
| `?`      | Show this keyboard reference |
