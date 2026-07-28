import Foundation
import GIFEditorCore
import SwiftTUI

/// Top-row menu bar — File / Edit / Layer / Select / Frame / View.
/// Each dropdown opens from the editor-root overlay so opening or
/// closing a menu does not reflow the canvas, panels, or timeline.
/// Every menu item is a clickable `Button` that calls the same model
/// method as its keybinding.
///
/// Menu items without a backing model method or keybinding (e.g.
/// "New", "Open…", "About gifeditor") are intentionally absent —
/// skipping them keeps every visible item live (no grayed-out rows on
/// day one) and avoids advertising features that don't exist yet.
struct MenuBarView: View {
  @Binding var openMenu: MenuBarMenu?
  let model: EditingSession
  var documentTitle: String = "untitled"
  @Binding var showsToolDock: Bool
  @Binding var showsRightPanel: Bool
  @Binding var showsTimeline: Bool
  @Binding var pixelGridMode: CanvasPixelGridMode
  @Binding var isResizeSheetPresented: Bool
  let refresh: @MainActor @Sendable () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 2) {
      menuTrigger(.file)
      menuTrigger(.edit)
      menuTrigger(.layer)
      menuTrigger(.select)
      menuTrigger(.frame)
      menuTrigger(.view)
      Spacer(minLength: 1)
      Text(documentLabel).foregroundStyle(.muted)
      Text(model.isDirty ? "●" : "✓")
        .foregroundStyle(model.isDirty ? .warning : .success)
    }
    .frame(height: 1, alignment: .topLeading)
    .padding(.horizontal, 1)
  }

  // MARK: - Menus

  private func menuTrigger(_ menu: MenuBarMenu) -> some View {
    Button(menu.triggerTitle(isOpen: openMenu == menu)) {
      openMenu = openMenu == menu ? nil : menu
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: true)
  }

  private var documentLabel: String {
    documentTitle
  }
}

struct MenuBarDropdownView: View {
  let menu: MenuBarMenu
  @Binding var openMenu: MenuBarMenu?
  let model: EditingSession
  var recentDocuments: [URL] = []
  @Binding var showsToolDock: Bool
  @Binding var showsRightPanel: Bool
  @Binding var showsTimeline: Bool
  @Binding var pixelGridMode: CanvasPixelGridMode
  @Binding var isResizeSheetPresented: Bool
  /// The onion-skin settings the View menu toggles.
  ///
  /// Spelled as a defaulted `Binding` rather than a `@Binding` property for
  /// the same reason `fileActions` is defaulted: the dropdown-layout tests
  /// build this view to check rows and offsets, and should not have to invent
  /// state for a control they are not exercising.
  var onionSkin: Binding<OnionSkinSettings> = .constant(OnionSkinSettings())
  /// Defaulted so a caller with no file verbs to run — the menu-bar
  /// render tests, which exercise dropdown layout rather than behavior —
  /// can build the dropdown without wiring six closures.
  var fileActions: FileMenuActions = .inert
  /// Defaulted so a caller with no palette sheet to open — the menu-bar
  /// render tests, which exercise dropdown layout rather than behavior —
  /// can build the dropdown without one.
  var presentPaletteSheet: @MainActor @Sendable () -> Void = {}
  /// Defaulted for the same reason `presentPaletteSheet` is — the
  /// dropdown-layout tests build this view without any presentations to
  /// raise.
  var presentKeyboardHelp: @MainActor @Sendable () -> Void = {}
  let refresh: @MainActor @Sendable () -> Void

  /// How many recent documents the File menu lists. The stored list
  /// holds ten; a dropdown that runs off the bottom of an 80×24 terminal
  /// is worse than a short one plus an Open… sheet that shows the rest.
  private static let visibleRecentCount = 5

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      switch menu {
      case .file:
        // `Save` and `Save As…` are separate rows because they are
        // separate verbs: `Save` writes back to a project file and
        // otherwise falls through to this same `Save As…`, and `Export
        // GIF…` is neither — it writes a flattened copy and leaves the
        // document unsaved. Collapsing them into one "Save…" is what let
        // the old build overwrite a GIF with a layered document's
        // shadow.
        menuItem("New…", action: refreshAfter(fileActions.new))
        menuItem("Open…", action: refreshAfter(fileActions.open))
        recentItems
        menuGap
        menuItem("Save", action: refreshAfter(fileActions.save))
        menuItem("Save As…", action: refreshAfter(fileActions.saveAs))
        menuGap
        menuItem("Export GIF…", action: refreshAfter(fileActions.exportGIF))
        menuGap
        menuItem("Resize Canvas…") {
          isResizeSheetPresented = true
          refresh()
        }
      case .edit:
        menuItem("Undo", action: refreshAfter { model.dispatch(.undo) })
          .disabled(!model.canUndo)
        menuItem("Redo", action: refreshAfter { model.dispatch(.redo) })
          .disabled(!model.canRedo)
        menuGap
        menuItem("Cut", action: refreshAfter { model.dispatch(.cutSelection) })
        menuItem("Copy", action: refreshAfter { model.dispatch(.copySelection) })
        menuItem("Paste", action: refreshAfter { model.dispatch(.paste) })
        menuGap
        // The four region rewrites. Under Edit rather than a menu of
        // their own: they act on the selection exactly as Cut and Copy
        // do, and a seventh menu trigger costs columns an 80-wide menu
        // bar does not have.
        menuItem("Flip Horizontal", action: refreshAfter { model.dispatch(.flipHorizontally) })
        menuItem("Flip Vertical", action: refreshAfter { model.dispatch(.flipVertically) })
        menuItem("Rotate Clockwise", action: refreshAfter { model.dispatch(.rotateClockwise) })
        menuItem("Rotate Counter-Clockwise", action: refreshAfter {
          model.dispatch(.rotateCounterClockwise)
        })
        menuGap
        menuItem("Clear Selection", action: refreshAfter { model.dispatch(.clearSelection) })
        menuGap
        menuItem("Palette…") {
          presentPaletteSheet()
          refresh()
        }
      case .layer:
        menuItem("New Layer", action: refreshAfter { model.dispatch(.addLayer) })
        menuItem("Delete Layer", action: refreshAfter { model.dispatch(.deleteCurrentLayer) })
        menuGap
        menuItem("Toggle Visibility", action: refreshAfter {
          model.dispatch(.toggleCurrentLayerVisibility)
        })
        menuItem("Layer Below", action: refreshAfter { model.dispatch(.selectLayerBelow) })
        menuItem("Layer Above", action: refreshAfter { model.dispatch(.selectLayerAbove) })
      case .select:
        menuItem("Select Tool") {
          model.dispatch(.selectTool(.select))
          refresh()
        }
        menuItem("Marquee Tool") {
          model.dispatch(.selectTool(.marquee))
          refresh()
        }
        menuGap
        menuItem("Clear Selection", action: refreshAfter { model.dispatch(.clearSelection) })
        menuItem("Confirm Marquee", action: refreshAfter { model.dispatch(.applyActiveTool) })
      case .frame:
        menuItem("New Frame", action: refreshAfter { model.dispatch(.insertBlankFrame) })
        menuItem("Duplicate Frame", action: refreshAfter { model.dispatch(.duplicateFrame) })
        menuItem("Delete Frame", action: refreshAfter { model.dispatch(.deleteFrame) })
        menuGap
        menuItem("Move Frame Left") {
          model.dispatch(.moveCurrentFrame(-1))
          refresh()
        }
        menuItem("Move Frame Right") {
          model.dispatch(.moveCurrentFrame(1))
          refresh()
        }
        menuItem("Move Frame to Start", action: refreshAfter {
          model.dispatch(.moveFrameToStart)
        })
        menuItem("Move Frame to End", action: refreshAfter { model.dispatch(.moveFrameToEnd) })
        menuGap
        menuItem(model.isPlaybackActive ? "Pause Playback" : "Play Playback") {
          model.dispatch(.togglePlayback)
          refresh()
        }
        menuGap
        menuItem("Previous Frame", action: refreshAfter { model.dispatch(.previousFrame) })
        menuItem("Next Frame", action: refreshAfter { model.dispatch(.nextFrame) })
        menuGap
        menuItem("Increase Delay") {
          model.dispatch(.adjustFrameDelay(10))
          refresh()
        }
        menuItem("Decrease Delay") {
          model.dispatch(.adjustFrameDelay(-10))
          refresh()
        }
        menuItem("Equalize Delays", action: refreshAfter {
          model.dispatch(.setAllFrameDelaysToCurrent)
        })
        menuItem("Reset Delay", action: refreshAfter { model.dispatch(.resetFrameDelay) })
        menuGap
        // Export metadata: what the written GIF will say, rather than what
        // the editor is showing. The disposal row names the mode it will
        // move to, because a row that names the current one reads as a
        // report rather than a verb.
        menuItem(
          "Disposal: \(EditingSession.disposalLabel(model.currentFrame.disposal))",
          action: refreshAfter { model.dispatch(.cycleFrameDisposal) }
        )
        menuItem(
          "Loop: \(EditingSession.loopDescription(model.document.loopCount))",
          action: refreshAfter { model.dispatch(.toggleLoopsForever) }
        )
        menuItem("Play Once") {
          model.dispatch(.setLoopCount(GIFLoader.playsOnce))
          refresh()
        }
      case .view:
        // Visibility toggles — narrow terminals can claim canvas space
        // back by hiding non-essential chrome.
        menuItem(checkmark(showsToolDock) + " Show Tool Dock") {
          showsToolDock.toggle()
          refresh()
        }
        menuItem(checkmark(showsRightPanel) + " Show Right Panel") {
          showsRightPanel.toggle()
          refresh()
        }
        menuItem(checkmark(showsTimeline) + " Show Timeline") {
          showsTimeline.toggle()
          refresh()
        }
        menuGap
        // Pixel grid mode — half-block doubles vertical resolution; full
        // cell makes each pixel a square of one terminal cell.
        menuItem(checkmark(pixelGridMode == .verticalHalfBlock) + " Half-block grid") {
          pixelGridMode = .verticalHalfBlock
          refresh()
        }
        menuItem(checkmark(pixelGridMode == .fullCell) + " Full-cell grid") {
          pixelGridMode = .fullCell
          refresh()
        }
        menuGap
        // Onion skin — the same three controls the `o` / `O` / `{` / `}`
        // keys drive. The two settings rows show their current value
        // rather than a submenu: a dropdown row is one click, so each
        // cycles.
        menuItem(checkmark(onionSkin.wrappedValue.isEnabled) + " Onion Skin") {
          onionSkin.wrappedValue.toggle()
          refresh()
        }
        menuItem("  Ghosted Sides: \(onionSkin.wrappedValue.sides.menuLabel)") {
          onionSkin.wrappedValue.cycleSides()
          refresh()
        }
        menuItem("  Ghost Frames: \(onionSkin.wrappedValue.depth)") {
          onionSkin.wrappedValue.cycleDepth()
          refresh()
        }
        menuGap
        menuItem("Increase Brush Size", action: refreshAfter {
          model.dispatch(.increaseBrushSize)
        })
        menuItem("Decrease Brush Size", action: refreshAfter {
          model.dispatch(.decreaseBrushSize)
        })
        menuItem("Swap Primary/Secondary", action: refreshAfter {
          model.dispatch(.swapPrimaryAndSecondary)
        })
        menuGap
        // Under View rather than behind a seventh menu trigger: `?` is
        // the discoverable route (the first-run hint says so), and a
        // "Help" trigger costs six columns of an 80-column menu bar to
        // hold one row.
        menuItem("Keyboard Shortcuts…") {
          presentKeyboardHelp()
          refresh()
        }
      }
    }
    .background {
      Rectangle().fill(.terminalSurfaceBackground)
    }
    .fixedSize(horizontal: true, vertical: true)
  }

  /// The recent-documents rows, or nothing at all on a first run.
  ///
  /// An empty "Open Recent" section that only ever says "(none)" is
  /// chrome that advertises a feature the author cannot use yet, so the
  /// heading and the rows appear together or not at all.
  @ViewBuilder
  private var recentItems: some View {
    let recents = recentDocuments.prefix(Self.visibleRecentCount)
    if !recents.isEmpty {
      menuGap
      Text("Recent")
        .foregroundStyle(.separator)
        .fixedSize(horizontal: true, vertical: true)
      ForEach(Array(recents), id: \.path) { url in
        menuItem(url.lastPathComponent) {
          fileActions.openRecent(url)
          refresh()
        }
      }
    }
  }

  private func menuItem(
    _ title: String,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    Button(title) {
      action()
      openMenu = nil
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: true)
  }

  private var menuGap: some View {
    Text(" ")
      .foregroundStyle(.separator)
      .fixedSize(horizontal: true, vertical: true)
  }

  // MARK: - Helpers

  /// Wraps a `() -> Void` model action in a closure that also calls
  /// `refresh()` afterward, matching the shape every keybinding uses.
  private func refreshAfter(
    _ action: @escaping @MainActor () -> Void
  ) -> @MainActor @Sendable () -> Void {
    let refresh = self.refresh
    return {
      action()
      refresh()
    }
  }

  /// Renders `✓` when `flag` is true, blank space otherwise. Aligns
  /// menu rows whether checked or not so toggling doesn't shift the
  /// label horizontally.
  private func checkmark(_ flag: Bool) -> String {
    flag ? "✓" : " "
  }
}

enum MenuBarMenu: CaseIterable, Equatable, Sendable {
  case file
  case edit
  case layer
  case select
  case frame
  case view

  var title: String {
    switch self {
    case .file: "File"
    case .edit: "Edit"
    case .layer: "Layer"
    case .select: "Select"
    case .frame: "Frame"
    case .view: "View"
    }
  }

  var triggerWidth: Int {
    title.count + 2
  }

  var dropdownOffset: Int {
    var offset = 0
    for candidate in Self.allCases {
      if candidate == self {
        return offset
      }
      offset += candidate.triggerWidth + 2
    }
    return offset
  }

  func triggerTitle(isOpen: Bool) -> String {
    title + " " + (isOpen ? "▴" : "▾")
  }
}
