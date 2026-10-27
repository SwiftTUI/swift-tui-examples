# Changelog

All notable Sextant changes are recorded here.

## Unreleased

## 0.19.5 - 2026-10-26

- A symbolic link whose target cannot be resolved no longer makes its whole
  directory unlistable. A link loop, a link into a directory you cannot search,
  or a link through a regular file now lists as a broken link, like a dangling
  one. The rest of the directory lists, and recursive search continues past it
  (STUI-1342).
- Built-in previews validate the whole capped read and keep scalars whole.
  Invalid UTF-8 or a NUL byte after the first 8 KiB selects the hexadecimal
  preview. UTF-8 or UTF-16 text whose multi-byte scalar straddles byte 8192 is
  text, not hex. A text preview cut at 256 KiB ends on a whole scalar instead of
  U+FFFD. A UTF-32 file is binary instead of UTF-16 text full of NULs
  (STUI-1343).
- Preview titles and directory summaries keep emoji ZWJ sequences and
  tag-sequence flags intact. Terminal controls, bidi controls and other
  invisible format characters are still shown as U+FFFD (STUI-1344).
- `VISUAL` and `EDITOR` are split with the POSIX shell's rules. Inside double
  quotes a backslash escapes only `$`, backquote, `"`, `\` and newline, so
  `edit "C:\temp"` keeps its backslash. Backslash-newline is a line
  continuation. Only space, tab and newline separate words, so a no-break space
  stays inside a path (STUI-1344).
- An optional preview tool is found only as an executable regular file in
  `PATH`; a directory with the tool's name is skipped (STUI-1345).
- Recursive search reports "Search limit reached" only when a match was left
  out or the directory budget stopped it (STUI-1345).
- External preview templates that pass inline program text to a common
  interpreter (`sh -c`, `python -c`, `node -e` and similar, also behind
  wrappers such as `env` or `timeout`) are rejected. The README lists exactly
  what is refused (STUI-1345).
- Bookmarks and recents are keyed by the bytes of the path, so the NFC and NFD
  spellings of a name on a byte-preserving filesystem are two bookmarks
  (STUI-1345).
- The overlay and column borders use `border(_:style:)` instead of the
  deprecated `border(_:set:)`. Rendering is unchanged.
- Update the framework and terminal-view dependencies to 0.19.5.

## 0.16.0 - 2026-10-08

- External previews retain terminal capabilities and their shutdown ownership
  through the terminal embedding lifecycle.
- Update the framework and terminal-view dependencies to 0.16.0.

## Earlier changes (included in 0.15.1)

- Fixed the preview panel rendering at half height for external previews. A
  trailing `Spacer` in the pane and the embedded terminal are both flexible, so
  a `VStack` split the available rows evenly between them and a previewer such
  as `bat` painted only half the pane. A built-in preview hid this: `Text` takes
  its full ideal height and is clamped, leaving the `Spacer` nothing.
- Fixed `?`, `G`, `R`, and `Y`, which never dispatched: they were declared with
  a `shift` modifier that terminals do not report for printable keys.
- Fixed the browser occupying a fraction of the terminal. A `Spacer` makes its
  stack flexible on both axes, so the header and status bar were competing with
  the columns for vertical space.
- Separated `→`/`l` (enter the selected directory) from `Return` (preview the
  file, or enter the directory). `→` no longer opens a file preview.
- A directory is no longer shown as a column until it is entered; its contents
  appear in the preview panel as a summary plus a short listing.
- `←`/`h` now climbs above the directory Sextant was launched in. The launch
  root still anchors root-relative path copies and recursive search.
- Moved the filter field into the status bar; it no longer displaces the
  browser.
- The active column's selected row is drawn as an accent bar, and the title is
  now a single `∢` glyph on an accent background. Column headers stay plain —
  the active one is marked by its accent foreground, not by a background.
- Entry rows read in the primary foreground instead of the separator tone; the
  trail column's selected row keeps the accent foreground as its marker.
- Fixed a crash on reaching `/`, which is where holding `←`/`h` always ends up.
  Darwin's `dev_t` is signed and devfs mounts carry negative device numbers, so
  building a filesystem identity for `/dev` trapped on the widening conversion.

## 0.1.0

- Added a bounded Miller-column browser with keyboard and pointer navigation.
- Added guaranteed built-in text, hexadecimal, metadata, and directory previews.
- Added optional generation-safe external previews hosted in a real PTY.
- Added local filtering, recursive filename search, path jump, bookmarks,
  recents, watching, configuration, safe workflow handoffs, and completions.
- Added typed filesystem failures, bounded caching, responsive layouts, and
  real-terminal lifecycle coverage.
