import GIFEditorCore
import SwiftTUI

/// Tool dock pinned to the left edge. Each icon is a `.plain`-styled
/// `Button` that selects the tool when activated; the active tool's icon
/// stays tinted. Below the tool list a divider, then the
/// primary/secondary color cells and a `⇄` swap button that mirrors the
/// keyboard `x` shortcut.
///
/// `.plain` style was chosen so the button chrome stays minimal — no
/// horizontal padding or border. A column is 2 cells wide (a 1-cell
/// focus-rail gutter that the framework reserves on every plain button so
/// focus presentation never overdraws the label, plus the icon glyph
/// itself) and the dock adds 1 cell of slack on either side so an icon
/// sits visually centred whether or not it is the active tool — 4 cells
/// for the single column of ``EditorLayoutDensity/regular``.
///
/// **Under ``EditorLayoutDensity/compact`` the dock is two columns wide.**
/// Nine tools stacked in one column is nine rows, which in a 24-row
/// terminal is more of the editor's height than a tool picker can justify
/// — so the dock buys back five rows with two columns of width, and puts
/// the primary and secondary swatches side by side rather than stacked.
/// It is the fifth and last rung of the compression ladder before the
/// canvas: see ``EditorLayoutDensity``.
struct ToolboxView: View {
  let tool: ActiveTool
  let primaryColor: EditorColor
  let secondaryColor: EditorColor
  let model: EditingSession
  let refresh: @MainActor @Sendable () -> Void
  var density: EditorLayoutDensity = .regular

  var body: some View {
    VStack(alignment: .center, spacing: 0) {
      ForEach(Array(toolRows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 0) {
          ForEach(row, id: \.self) { entry in
            toolButton(entry)
          }
        }
        // A partial last row (nine tools do not divide by two) keeps its
        // icons under the columns above rather than centring the orphan.
        .frame(width: 2 * density.toolDockColumns, alignment: .leading)
      }
      Divider()
      colorSwatches
      swapButton
      Spacer(minLength: 0)
    }
    .padding(0)
    .frame(width: density.toolDockWidth, alignment: .center)
    .border(.separator, set: .single)
  }

  /// The tool icons, chunked into the dock's columns in declaration order —
  /// reading order, so the dock's shape changes with the density but the
  /// order the tools appear in never does.
  private var toolRows: [[ActiveTool]] {
    let tools = ActiveTool.allCases
    let columns = density.toolDockColumns
    return stride(from: 0, to: tools.count, by: columns).map { start in
      Array(tools[start..<min(start + columns, tools.count)])
    }
  }

  /// The active primary and secondary colors, stacked where there is height
  /// to stack them in and side by side where there is not.
  @ViewBuilder
  private var colorSwatches: some View {
    if density.toolDockColumns > 1 {
      HStack(spacing: 1) {
        swatch(primaryColor)
        swatch(secondaryColor)
      }
    } else {
      swatch(primaryColor)
      swatch(secondaryColor)
    }
  }

  private func swatch(_ color: EditorColor) -> some View {
    Rectangle()
      .fill(color.toTerminalColor())
      .frame(width: 1, height: 1)
  }

  private func toolButton(_ entry: ActiveTool) -> some View {
    Button {
      model.dispatch(.selectTool(entry))
      refresh()
    } label: {
      Text(entry.iconGlyph)
        .foregroundStyle(entry == tool ? .tint : .muted)
    }
    .buttonStyle(.plain)
  }

  private var swapButton: some View {
    Button {
      model.dispatch(.swapPrimaryAndSecondary)
      refresh()
    } label: {
      Text("⇄").foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
  }
}
