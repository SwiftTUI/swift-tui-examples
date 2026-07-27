import GIFEditorCore
import SwiftTUI

/// Bottom sub-panel of the right column — Photoshop-style layers
/// list. Top of the list is the visually-frontmost layer (matches the
/// painter's-stack order users learn from Photoshop). Each row has a
/// clickable visibility toggle, a name, and a delete button; the row
/// body itself is clickable to select that layer. A `＋` footer adds a
/// new layer above the current.
///
/// All shortcuts continue to work via the keyboard:
/// `Alt+H` toggles current visibility, `Alt+J/K` change selection,
/// `Alt+X` deletes, `Alt+N` adds.
///
/// ## Why the list is bounded
///
/// Every other region of the editor is a fixed number of rows tall, which
/// is what lets ``EditorLayoutFloor/minimumHeight`` be a property of the
/// *layout*. A list that grew a row per layer would make it a property of
/// the open document instead — the editor would fit an 80×24 terminal
/// holding one layer and overflow it holding six, which is the same defect
/// the height floor exists to close, just triggered by the file rather
/// than the window.
///
/// So the list shows at most ``EditorLayoutDensity/visibleLayerRows`` rows,
/// windowed so the selected layer is always one of them, and says so: the
/// heading reads `Layers 4/9` whenever there are layers outside the
/// window. Nothing is hidden silently, and `Alt+J`/`Alt+K` walk the
/// selection through the whole stack with the window following it.
struct LayerListView: View {
  let layers: [EditorLayer]
  let selectedIndex: Int
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void
  var density: EditorLayoutDensity = .regular

  var body: some View {
    let window = Self.visibleWindow(
      count: layers.count,
      selected: selectedIndex,
      rows: density.visibleLayerRows
    )
    // Top of the list is the visually-frontmost layer, so the window is
    // walked backwards.
    let visible = window.reversed().map { VisibleLayer(index: $0, layer: layers[$0]) }
    return VStack(alignment: .leading, spacing: 0) {
      Text(heading(window: window)).foregroundStyle(.muted)
      ForEach(visible, id: \.id) { entry in
        row(
          layer: entry.layer,
          index: entry.index,
          isSelected: entry.index == selectedIndex
        )
      }
      if density.drawsRedundantRules {
        Divider()
      }
      newLayerButton
    }
    .padding(.horizontal, 1)
  }

  /// `Layers` when every layer is on screen, and `Layers n/N` when the
  /// window is holding some of them back — `n` being the selected layer, so
  /// the heading answers "where am I" and "how many are there" in the one
  /// row it was already spending.
  private func heading(window: Range<Int>) -> String {
    guard window.count < layers.count else { return "Layers" }
    return "Layers \(selectedIndex + 1)/\(layers.count)"
  }

  /// The contiguous run of layer indices the list shows.
  ///
  /// Centred on the selection and clamped to the ends, so the selected
  /// layer is always inside the window and the window never runs off the
  /// stack — which is what makes `Alt+J`/`Alt+K` navigation still reach
  /// every layer with only a few rows on screen.
  static func visibleWindow(count: Int, selected: Int, rows: Int) -> Range<Int> {
    let span = min(max(rows, 0), count)
    guard span > 0 else { return 0..<0 }
    let centred = selected - span / 2
    let lower = min(max(centred, 0), count - span)
    return lower..<(lower + span)
  }

  /// One row of the window, carrying the layer's *stack* index rather than
  /// its position on screen — every action in the row addresses the model by
  /// that index, so it has to survive the windowing.
  private struct VisibleLayer {
    let index: Int
    let layer: EditorLayer

    var id: EditorLayer.ID { layer.id }
  }

  private func row(layer: EditorLayer, index: Int, isSelected: Bool) -> some View {
    HStack(spacing: 1) {
      visibilityButton(for: layer, index: index)
      Button {
        model.selectLayer(at: index)
        refresh()
      } label: {
        Text(layer.name)
          .foregroundStyle(
            isSelected
              ? AnyShapeStyle(.tint)
              : AnyShapeStyle(layer.isVisible ? .foreground : .muted)
          )
      }
      .buttonStyle(.plain)
      Spacer(minLength: 1)
      deleteButton(index: index)
    }
  }

  private func visibilityButton(for layer: EditorLayer, index: Int) -> some View {
    Button {
      model.toggleLayerVisibility(at: index)
      refresh()
    } label: {
      Text(layer.isVisible ? "●" : "○")
        .foregroundStyle(layer.isVisible ? .foreground : .muted)
    }
    .buttonStyle(.plain)
  }

  private func deleteButton(index: Int) -> some View {
    Button {
      model.deleteLayer(at: index)
      refresh()
    } label: {
      Text("✕").foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
  }

  private var newLayerButton: some View {
    Button {
      model.addLayer()
      refresh()
    } label: {
      HStack(spacing: 1) {
        Text("＋").foregroundStyle(.tint)
        Text("New layer").foregroundStyle(.muted)
      }
    }
    .buttonStyle(.plain)
  }
}
