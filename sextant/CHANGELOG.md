# Changelog

All notable Sextant changes are recorded here.

## Unreleased

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
- The active column's header and its selected row are drawn as accent bars, and
  the title is now a single `∢` glyph on an accent background.

## 0.1.0

- Added a bounded Miller-column browser with keyboard and pointer navigation.
- Added guaranteed built-in text, hexadecimal, metadata, and directory previews.
- Added optional generation-safe external previews hosted in a real PTY.
- Added local filtering, recursive filename search, path jump, bookmarks,
  recents, watching, configuration, safe workflow handoffs, and completions.
- Added typed filesystem failures, bounded caching, responsive layouts, and
  real-terminal lifecycle coverage.
