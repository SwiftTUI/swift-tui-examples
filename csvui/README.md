# csvui

`csvui` is a viewer-first CSV/TSV workbench for the terminal. It indexes the
source bytes once, decodes only the rows needed by the current viewport, and
adds sparse editing, search, filtering, sorting, file watching, and safe
atomic saves around that bounded core.

## Run it

```bash
swiftly run swift run --package-path csvui csvui data.csv
swiftly run swift run --package-path csvui csvui data.tsv --read-only
cat data.csv | swiftly run swift run --package-path csvui csvui -
```

`csvui` requires SwiftTUI `0.8.4` or newer.

The executable requires a TTY for output. Standard-input documents remain
editable in memory; their first save uses Save As because they have no writable
source path. Use `--read-only` to disable mutations. Use `--help` for the
complete CLI:

```text
csvui [FILE] [--delimiter VALUE] [--no-headers] [--read-only]
      [--config PATH | --no-config] [--watch | --no-watch]
csvui --print-default-theme
```

`--delimiter` accepts `comma`, `tab`, `semicolon`, `pipe`, or one printable
single-byte ASCII character other than `"`. A `.csv` or `.tsv` suffix selects
the corresponding delimiter; other inputs use a bounded sample-based guess.

## Keyboard map

The menu bar, `?` keyboard reference, and `:` command palette expose the same
command catalog.

| Keys | Action |
| --- | --- |
| Arrows or `h j k l` | Move one cell |
| Page Up/Down, `Ctrl-B`/`Ctrl-F` | Move one page |
| `g` / `G` | First / last row |
| `0` / `$` | First / last visible column |
| Enter | Open row detail |
| `e` | Edit the selected cell |
| `^` | Rename the selected header |
| `Ctrl-S` | Commit a cell editor or save the document |
| `u` / `Ctrl-R` | Undo / redo |
| `/`, `n`, `N` | Find, next match, previous match |
| `f` / `F` | Filter the current column / all columns |
| `s` | Cycle ascending, descending, and unsorted |
| `[` / `]` / `=` | Decrease, increase, or reset column width |
| `z` / `Z` | Freeze through the current column / clear frozen columns |
| `y` / `Y` | Copy the cell / row |
| `?` / `:` | Keyboard reference / command palette |
| `q` | Quit, with an unsaved-change guard |
| `Ctrl-C` | Request runtime termination |

Escape cancels the current prompt, editor, menu, or confirmation. Text entered
in a focused editor is ordinary content—even `q`, which is a quit command only
in browse mode.

## File and edit safety

- Source files are capped at 256 MiB, 2,000,000 records, 16,384 columns, and
  16 MiB per decoded field. Oversized byte sources fail before terminal
  takeover; invalid UTF-8, NUL bytes, malformed quoting, and structural limits
  produce an in-app diagnostic without replacing the last-good document.
- The decoded-row cache is bounded to 512 rows or 16 MiB. Undo history is
  bounded to 256 entries or 16 MiB. Search stores at most 10,000 matches, and
  filter/sort workspaces are capped at 64 MiB.
- In-place Save is offered only for a direct writable regular file with one
  hard link. It compares both the original identity and bytes immediately
  before replacement, writes a same-directory temporary file, flushes it,
  preserves permissions, and atomically replaces the source.
- Save As publishes a new destination without an overwrite race. Existing
  destinations require explicit confirmation, and symlink or hard-link
  destinations are rejected. If another process changes the source, csvui
  keeps the last-good view and asks whether to reload or save elsewhere.
- File and theme watching are enabled by default for regular-file sessions;
  `--no-watch` disables document watching. Invalid external replacements never
  destroy the current in-memory document.

CSV formula text is displayed and saved as text. `csvui` does not evaluate or
sanitize spreadsheet formulas. Treat exported documents as untrusted when
opening them in software that executes formula-like cells.

## Themes

The default theme path is `$XDG_CONFIG_HOME/csvui/theme.toml`, falling back to
`~/.config/csvui/theme.toml`. A missing implicit file uses the built-in theme;
an explicit missing or invalid `--config` is an error. Theme files must be
UTF-8 TOML no larger than 1 MiB.

```bash
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/csvui"
swiftly run swift run --package-path csvui csvui --print-default-theme \
  > "${XDG_CONFIG_HOME:-$HOME/.config}/csvui/theme.toml"
```

[`default-theme.toml`](default-theme.toml) is the complete checked-in example.

## Development and tests

The committed manifest keeps the public tagged-HTTPS dependency contract.
Pre-tag integration against unreleased framework changes happens in the
SwiftTUI coordination root, not here.

```bash
swiftly run swift test --package-path csvui
CSVUI_REAL_PTY_TESTS=1 swiftly run swift test --package-path csvui
```

The focused suite covers parsing, malformed input, delimiter detection,
bounded caching/history, projections, theming, atomic saves and conflicts,
watcher replacement/coalescing, model lifecycle, view geometry, and a rebuilt
real-PTY edit/quit journey.

## See also

- [API reference](https://swifttui.sh/docs/documentation/) — the SwiftTUI DocC docs.
- [Showcase](https://swifttui.sh/showcase/) — csvui and the other examples on the website.
- [swift-tui](https://github.com/SwiftTUI/swift-tui) — the framework repository.
