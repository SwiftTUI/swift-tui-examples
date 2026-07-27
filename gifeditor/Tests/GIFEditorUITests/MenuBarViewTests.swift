import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor menu bar")
struct MenuBarViewTests {
  @Test("open dropdown paints above editor content rows")
  func openDropdownPaintsAboveEditorContentRows() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 4, height: 4))
    )
    let openMenu = Binding<MenuBarMenu?>.constant(.file)
    let rendered = render(
      ZStack(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: 0) {
          MenuBarView(
            openMenu: openMenu,
            model: model,
            showsToolDock: .constant(true),
            showsRightPanel: .constant(true),
            showsTimeline: .constant(true),
            pixelGridMode: .constant(.verticalHalfBlock),
            isResizeSheetPresented: .constant(false),
            refresh: {}
          )
          Text("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
          Text("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
          Text("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
          Text("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
        }

        MenuBarDropdownView(
          menu: .file,
          openMenu: openMenu,
          model: model,
          showsToolDock: .constant(true),
          showsRightPanel: .constant(true),
          showsTimeline: .constant(true),
          pixelGridMode: .constant(.verticalHalfBlock),
          isResizeSheetPresented: .constant(false),
          refresh: {}
        )
        .offset(x: MenuBarMenu.file.dropdownOffset + 1, y: 1)
      },
      width: 44,
      height: 14
    )

    let text = rendered.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.rasterSurface.lines[1].contains("New…"))
    #expect(text.contains("Open…"))
    #expect(text.contains("Resize Canvas"))
  }

  /// `Save`, `Save As…` and `Export GIF…` are three rows, not one.
  ///
  /// They were one "Save…" row before the project format existed, and
  /// collapsing them is exactly what let the editor write a flattened
  /// GIF over a layered document under a verb that promises the
  /// opposite. The menu is where an author learns the three are
  /// different, so the separation is worth pinning.
  @Test("the File menu separates Save, Save As and Export GIF")
  func fileMenuSeparatesSaveVerbs() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 4, height: 4))
    )
    let rendered = render(
      MenuBarDropdownView(
        menu: .file,
        openMenu: .constant(.file),
        model: model,
        showsToolDock: .constant(true),
        showsRightPanel: .constant(true),
        showsTimeline: .constant(true),
        pixelGridMode: .constant(.verticalHalfBlock),
        isResizeSheetPresented: .constant(false),
        refresh: {}
      ),
      width: 44,
      height: 14
    )

    let text = rendered.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("Save As…"))
    #expect(text.contains("Export GIF…"))
    // `Save` on its own row, which "Save As…" would satisfy vacuously.
    #expect(rendered.rasterSurface.lines.contains { $0.trimmed() == "Save" })
  }
}

extension String {
  fileprivate func trimmed() -> String {
    trimmingCharacters(in: .whitespaces)
  }
}

@MainActor
private func render(
  _ view: some View,
  width: Int,
  height: Int,
  id: String = "\(#fileID).\(#function)"
) -> RenderSnapshot {
  var env = EnvironmentValues()
  env.terminalSize = CellSize(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: ["gifeditor.menu.tests.\(id)"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}
