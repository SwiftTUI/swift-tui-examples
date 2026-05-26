# gifeditor keybindings

Focused editor commands use bare keys where they map to ordinary pixel-editor
actions.

The bindings avoid terminal-ambiguous chords such as `Ctrl+Shift+letter`,
`Ctrl+digit`, `Ctrl+[` / `Ctrl+]`, and `Alt+[`, because the current terminal
input path does not receive those as distinct key presses. Press `?` in the
editor to open the same shortcut reference in-app.

## Tools

| Shortcut      | Tool                                    |
| ------------- | --------------------------------------- |
| `p`           | **P**en - paint the primary color       |
| `e`           | **E**raser - clear to transparent       |
| `b`           | **B**ucket fill (4-connected)           |
| `g`           | **G**radient between primary/secondary  |
| `m`           | **M**arquee - rectangular selection     |
| `i`           | Eyedropper - pick color from cursor     |
| `x`           | Swap primary and secondary color        |
| `Space`       | Apply the current tool at the cursor    |
| `Enter`       | Confirm marquee (commit selection rect) |
| `Escape`      | Clear selection                         |
| `?`           | Open keyboard help                      |

The canvas also supports direct pointer editing. Drag with **Pen** or
**Eraser** to paint connected strokes, drag with **Marquee** to select a
rectangle, drag with **Gradient** to apply a gradient between the drag endpoints,
and click with **Fill** or **Eyedropper** to target a single pixel. Hosts that
report terminal-pixel pointer locations can address the top and bottom half of a
cell independently; cell-only hosts fall back to the top half of each terminal
cell.

## Cursor

| Shortcut          | Action                  |
| ----------------- | ----------------------- |
| `Left/Right/Up/Down` | Move cursor by 1 pixel |
| `Ctrl+Left/Right/Up/Down` | Move cursor by 8 pixels |
| `h/j/k/l`         | Vi-style 1-pixel movement |

## Frames / Timeline

| Shortcut          | Action                                   |
| ----------------- | ---------------------------------------- |
| `Alt+,`           | Previous frame                           |
| `Alt+.`           | Next frame                               |
| `Ctrl+N`          | New blank frame after current            |
| `Ctrl+D`          | Duplicate current frame after current    |
| `Alt+D`           | Delete current frame                     |
| `Alt+-`           | Decrease current frame delay (10 cs)     |
| `Alt+=`           | Increase current frame delay (10 cs)     |
| `Alt+0`           | Reset all frame delays to current value  |

## Layers

| Shortcut          | Action                         |
| ----------------- | ------------------------------ |
| `Alt+N`           | New empty layer above current  |
| `Alt+J`           | Select layer below             |
| `Alt+K`           | Select layer above             |
| `Alt+H`           | Toggle current layer visibility |
| `Alt+X`           | Delete current layer           |

## Clipboard

| Shortcut          | Action                                  |
| ----------------- | --------------------------------------- |
| `Ctrl+C`          | Copy selection (or whole layer if none) |
| `Ctrl+V`          | Paste at cursor                         |

## History

| Shortcut          | Action                  |
| ----------------- | ----------------------- |
| `Ctrl+Z`          | Undo last document edit |
| `Ctrl+Y`          | Redo last undone edit   |

## Palette / Colors

| Shortcut          | Action                              |
| ----------------- | ----------------------------------- |
| `1`..`9`          | Pick palette slot 1..9 as primary   |
| `Alt+1`..`Alt+9`  | Pick palette slot 1..9 as secondary |

## File / App

| Shortcut          | Action                                 |
| ----------------- | -------------------------------------- |
| `Ctrl+S`          | Save                                   |
| `Alt+S`           | Save As (writes `./untitled.gif`)      |
| `Ctrl+R`          | Resize canvas (cycles 16/24/32/48/64) |
| `Ctrl+Q`          | Quit                                   |
| `?`               | Open keyboard help                     |
