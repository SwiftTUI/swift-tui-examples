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
/// disk beside it, so this is the copy that ships.
struct KeyBindingHelpView: View {
  let onClose: @MainActor @Sendable () -> Void

  /// Height of the scrolling region. Sized so the title, the footer and
  /// the sheet's own chrome still fit an 80×24 terminal, which is the
  /// smallest surface the editor targets.
  private static let visibleRows = 13

  /// Width of the shortcut column, taken from the widest chord in the
  /// catalog so the action column lines up without a per-row measure.
  private static let shortcutWidth =
    KeyBindingCatalog.entries
    .map(\.display.count)
    .max() ?? 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(KeyBindingCatalog.populatedSections, id: \.rawValue) { section in
            sectionView(section)
          }
        }
      }
      .frame(height: Self.visibleRows)
      Divider()
      HStack(spacing: 1) {
        Text("↑ / ↓ scrolls").foregroundStyle(.separator)
        Spacer(minLength: 1)
        Button("Close", action: onClose)
          .systemHint("Esc")
      }
    }
    .padding(1)
  }

  @ViewBuilder
  private func sectionView(_ section: KeyBindingSection) -> some View {
    Text(section.title).foregroundStyle(.tint)
    ForEach(KeyBindingCatalog.entries(in: section), id: \.command) { entry in
      HStack(spacing: 1) {
        Text(Self.paddedShortcut(entry.display))
          .foregroundStyle(.muted)
        Text(entry.label)
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
