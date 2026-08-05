import SwiftTUI

/// The `?` overlay: every shortcut the editor answers to, rendered
/// straight from `KeyBindingCatalog`.
///
/// It holds no table of its own. That is the entire design — the help
/// screen this replaces was a second hand-written copy of the shortcut
/// list, and it had already drifted from both the bindings and
/// `docs/KEYBINDINGS.md` before it was deleted. Rendering the catalog
/// means the overlay is wrong only if the bindings are wrong.
///
/// A standalone binary cannot assume the repo's `docs/` directory is on
/// disk beside it, so this is the copy that ships. It is a reference
/// *card*: rows are clipped to one line each, and the handful of labels
/// long enough to be truncated read in full in `docs/KEYBINDINGS.md`.
struct KeyBindingHelpView: View {
  let onClose: @MainActor @Sendable () -> Void

  /// Height of the scrolling region. Sized so the title, the footer and
  /// the sheet's own chrome still fit an 80×24 terminal, which is the
  /// smallest surface the editor targets.
  ///
  /// Twelve sections and seventy-odd rows do not fit in thirteen, and
  /// they never will — the fold is permanent, so what matters is that
  /// everything below it is *reachable*. See ``scrolled(from:by:)``.
  private static let visibleRows = 13

  /// Width of the shortcut column, taken from the widest chord in the
  /// catalog so the action column lines up without a per-row measure.
  private static let shortcutWidth =
    KeyBindingCatalog.entries
    .map(\.display.count)
    .max() ?? 0

  /// The footer's scroll legend. Kept to one short line: the sheet is
  /// already as wide as its widest catalog row, and the footer must not
  /// be what decides its width.
  private static let scrollLegend = "↑↓ · PgUp/PgDn · Home/End"

  /// Rows the list renders: a title, its entries, and a blank spacer per
  /// section.
  ///
  /// This is an exact count, not an estimate, and the `.lineLimit(1)` on
  /// each row in ``sectionView(_:)`` is what makes it one: the longest
  /// label is 79 columns against a text column of about 60, so without
  /// the clip a handful of rows would wrap and every arithmetic below
  /// would be short by however many wrapped. `End` would then stop a
  /// section shy of the end, which is the failure this whole item is
  /// about. Clipping also keeps the card scannable, and the full text of
  /// a truncated row is one `docs/KEYBINDINGS.md` away.
  private static let contentRows: Int = KeyBindingCatalog.populatedSections.reduce(into: 0) {
    total, section in
    total += 2 + KeyBindingCatalog.entries(in: section).count
  }

  /// The offset at which the last row sits on the last line.
  private static var maximumScroll: Int { max(0, contentRows - visibleRows) }

  @State private var scroll = ScrollCellOffset.zero
  /// Focus starts on the list rather than on the sheet's close button.
  ///
  /// This is the whole fix, and it is not cosmetic. Key presses bubble
  /// from the *focused* node upward, and the sheet's own chrome button is
  /// a sibling of this content, not a descendant — so with focus left
  /// where the sheet puts it, neither the scroll view's built-in arrow
  /// handling nor the handler below is on the path a key travels, and
  /// every row past the thirteenth is unreachable.
  @FocusState private var listIsFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView(.vertical, position: $scroll) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(KeyBindingCatalog.populatedSections, id: \.rawValue) { section in
            sectionView(section)
          }
        }
      }
      .frame(height: Self.visibleRows)
      .focusable()
      .focused($listIsFocused)
      Divider()
      HStack(spacing: 1) {
        Text(Self.scrollLegend).foregroundStyle(.separator)
        Spacer(minLength: 1)
        Button("Close", action: onClose)
          .systemHint("Esc")
      }
    }
    .padding(1)
    // The focus request has to be imperative: a sheet seats focus on its
    // own chrome button as it opens, and neither that seating nor
    // `.defaultFocus` can be out-voted from inside the content during the
    // same resolve. Asking for it here lands it on the following frame —
    // a millisecond after `?`, and long before a hand reaches the next
    // key.
    .task { listIsFocused = true }
    // Above the scroll view rather than on it, so the handler is on the
    // bubble path from whatever inside the sheet holds focus, and so it
    // covers the keys the scroll view's own handling does not (`PgUp` and
    // `PgDn`).
    .onKeyPress(.any) { press in
      guard press.modifiers.isEmpty,
        let next = Self.scrolled(from: scroll, by: press.key)
      else {
        return .ignored
      }
      scroll = next
      // Handled even when the offset did not change. Letting an exhausted
      // `↓` fall through would hand it to the editor root behind the
      // sheet, which moves the canvas cursor under an overlay the author
      // is still reading.
      return .handled
    }
  }

  /// Where a bare key scrolls to, or `nil` when the key is not one of
  /// ours.
  ///
  /// A page is the viewport height rather than a rounder number so that
  /// `PgDn` twice shows every row exactly once, with no skipped band and
  /// no re-read.
  private static func scrolled(
    from position: ScrollCellOffset,
    by key: KeyEvent
  ) -> ScrollCellOffset? {
    let delta: Int
    switch key {
    case .arrowUp: delta = -1
    case .arrowDown: delta = 1
    case .pageUp: delta = -visibleRows
    case .pageDown: delta = visibleRows
    case .home: return ScrollCellOffset(x: position.x, y: 0)
    case .end: return ScrollCellOffset(x: position.x, y: maximumScroll)
    default: return nil
    }
    return ScrollCellOffset(
      x: position.x,
      y: min(max(0, position.y + delta), maximumScroll)
    )
  }

  @ViewBuilder
  private func sectionView(_ section: KeyBindingSection) -> some View {
    Text(section.title).foregroundStyle(.tint)
    ForEach(KeyBindingCatalog.entries(in: section), id: \.command) { entry in
      HStack(spacing: 1) {
        Text(Self.paddedShortcut(entry.display))
          .foregroundStyle(.muted)
        Text(entry.label)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 0)
      }
    }
    Text(" ")
  }

  private static func paddedShortcut(_ display: String) -> String {
    display + String(repeating: " ", count: max(0, shortcutWidth - display.count))
  }
}

/// Carries the `?` overlay on a view node of its own.
///
/// Same constraint as `FilePresentationHost`, and worth restating because
/// it is the reason this is a separate type rather than one more
/// `.sheet` on `EditorView`'s root: the root's modifier chain is already
/// ~40 nested `ModifiedContent` layers deep once the keybinding chains
/// expand, resolution recurses once per layer, and hanging further
/// presentations there overflows the resolve stack and takes the whole
/// editor down. Presentations are portal-based — they hoist to the
/// terminal surface from wherever they are attached — so a zero-size
/// sibling costs nothing at render time and buys the depth back.
struct KeyBindingHelpHost: View {
  @Binding var isPresented: Bool

  var body: some View {
    Text("")
      .frame(width: 0, height: 0)
      .sheet("Keyboard shortcuts", isPresented: $isPresented) {
        KeyBindingHelpView(onClose: { isPresented = false })
      }
  }
}
