import GIFEditorCore
import SwiftTUI

/// Public root view of the editor. Owns one `EditorViewModel` for the
/// document's lifetime; everything below it renders from that model
/// and forwards user input back through it.
///
/// The editor stacks a menu bar and a full-width tool-options bar over a
/// 3-region body (tool dock / canvas / right inspector), then a timeline
/// strip and a status strip:
///
/// ```
/// ┌───────────────────────────────────┐
/// │ menu bar                          │
/// ├───────────────────────────────────┤
/// │ tool options bar                  │
/// ├──┬───────────────────────┬────────┤
/// │T │                       │ Color  │
/// │o │       canvas          │ Palette│
/// │l │                       │ Layers │
/// ├──┴───────────────────────┴────────┤
/// │ timeline                          │
/// ├───────────────────────────────────┤
/// │ status                            │
/// └───────────────────────────────────┘
/// ```
///
/// The options bar is full-width top chrome — not nested in the right
/// inspector — so its tool-contextual controls never widen the side
/// column or reflow the canvas when the active tool changes.
public struct EditorView: View {
  // The view-model is a reference type, so we just hold it as an
  // @State (the Reference Box pattern). Mutating @MainActor methods on
  // it advance state in-place; we still mark the @State so the
  // framework treats this view as having local-owned state.
  @State private var model: EditorViewModel
  @State private var revision: Int = 0
  @State private var showsToolDock = true
  @State private var showsRightPanel = true
  @State private var showsTimeline = true
  @State private var pixelGridMode: CanvasPixelGridMode = .verticalHalfBlock
  @State private var isResizeSheetPresented = false
  @State private var isSaveSheetPresented = false
  @State private var savePathText = ""
  @State private var overwriteSaveConfirmed = false
  @State private var savePreviewDocument: GIFDocument?
  @State private var savePreviewRequestID = 0
  @State private var openMenu: MenuBarMenu?

  /// Fixed width of the right inspector column. Pinning it (rather than
  /// `.fixedSize`) keeps the canvas the sole flexible child of the body
  /// row, so reclaimed horizontal space flows to the canvas instead of
  /// pooling as dead margin to the right of the panel.
  private static let rightPanelWidth = 28

  public init(document: GIFDocument) {
    _model = State(initialValue: EditorViewModel(document: document))
  }

  public var body: some View {
    // `revision` is read here so the framework's @State subscription
    // tracks it; bumping it via the bindings' `refresh` callback
    // forces a body re-evaluation against the (already-mutated)
    // model. A future @Observable adoption can drop this seam.
    _ = revision
    let model = self.model
    let refresh: @MainActor @Sendable () -> Void = { revision &+= 1 }
    let presentSaveSheet: @MainActor @Sendable () -> Void = {
      savePathText = model.defaultSaveURL.path
      overwriteSaveConfirmed = false
      savePreviewDocument = model.document
      savePreviewRequestID &+= 1
      isSaveSheetPresented = true
      openMenu = nil
    }
    // One memoized compositing pass feeds both the canvas (current frame) and
    // every timeline thumbnail. During a stroke only the edited frame
    // recomposites; the rest are served from the model's content-keyed cache.
    let composites = model.compositedFrames()
    let frameColors = composites[model.currentFrameIndex]
    // Skip building thumbnails entirely when the timeline strip is hidden —
    // `showsTimeline` previously gated only the render, not this compute.
    let timelineFrames =
      showsTimeline
      ? composites.indices.map { index in
        TimelineFrame(
          thumbnail: Self.thumbnail(from: composites[index], sourceSize: model.document.size),
          delayCentiseconds: model.document.frames[index].delayCentiseconds
        )
      }
      : []
    let primaryColor = model.document.palette[model.primaryColorIndex]
    let secondaryColor = model.document.palette[model.secondaryColorIndex]

    return ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 0) {
        MenuBarView(
          openMenu: $openMenu,
          model: model,
          showsToolDock: $showsToolDock,
          showsRightPanel: $showsRightPanel,
          showsTimeline: $showsTimeline,
          pixelGridMode: $pixelGridMode,
          isResizeSheetPresented: $isResizeSheetPresented,
          presentSaveSheet: presentSaveSheet,
          refresh: refresh
        )
        ToolOptionsBar(
          model: model,
          refresh: refresh
        )
        HStack(alignment: .top, spacing: 1) {
          if showsToolDock {
            ToolboxView(
              tool: model.tool,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
              model: model,
              refresh: refresh
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .fixedSize(horizontal: true, vertical: false)
          }
          ScrollView {
            InteractiveCanvasView(
              size: model.document.size,
              cells: frameColors,
              model: model,
              refresh: refresh,
              mode: pixelGridMode
            )
            .applyFocusedEditorBindings(
              model: model,
              refresh: refresh
            )
          }
          .border(.separator, set: .single)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          if showsRightPanel {
            VStack(alignment: .leading, spacing: 0) {
              ColorPanelView(
                primaryColor: primaryColor,
                secondaryColor: secondaryColor
              )
              .frame(maxWidth: .infinity, alignment: .leading)
              Divider()
              PaletteView(
                palette: model.document.palette,
                primaryIndex: model.primaryColorIndex,
                secondaryIndex: model.secondaryColorIndex,
                model: model,
                refresh: refresh
              )
              .frame(maxWidth: .infinity, alignment: .leading)
              Divider()
              LayerListView(
                layers: model.currentFrame.layers,
                selectedIndex: model.currentLayerIndex,
                model: model,
                refresh: refresh
              )
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .border(.separator, set: .single)
            .frame(width: Self.rightPanelWidth)
            .frame(maxHeight: .infinity, alignment: .top)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if showsTimeline {
          TimelineView(
            frames: timelineFrames,
            currentFrameIndex: model.currentFrameIndex,
            model: model,
            refresh: refresh
          )
        }
        Divider()
        footer
      }

      if let openMenu {
        MenuBarDropdownView(
          menu: openMenu,
          openMenu: $openMenu,
          model: model,
          showsToolDock: $showsToolDock,
          showsRightPanel: $showsRightPanel,
          showsTimeline: $showsTimeline,
          pixelGridMode: $pixelGridMode,
          isResizeSheetPresented: $isResizeSheetPresented,
          presentSaveSheet: presentSaveSheet,
          refresh: refresh
        )
        .offset(x: openMenu.dropdownOffset + 1, y: 1)
      }
    }
    .panel(id: "gifeditor")
    .applyFocusedEditorBindings(
      model: model,
      refresh: refresh
    )
    .applyCursorBindings(model: model, refresh: refresh)
    .applyFrameBindings(model: model, refresh: refresh)
    .applyLayerBindings(model: model, refresh: refresh)
    .applyClipboardBindings(model: model, refresh: refresh)
    .applyHistoryBindings(model: model, refresh: refresh)
    .applyPaletteBindings(model: model, refresh: refresh)
    .applyFileBindings(
      isResizeSheetPresented: $isResizeSheetPresented,
      presentSaveSheet: presentSaveSheet,
      refresh: refresh
    )
    .applyTerminationHandling(
      model: model,
      presentSaveSheet: presentSaveSheet,
      refresh: refresh
    )
    .sheet("Save GIF", isPresented: $isSaveSheetPresented) {
      SaveGIFPreviewSheetView(
        document: savePreviewDocument ?? model.document,
        requestID: savePreviewRequestID,
        pathText: $savePathText,
        overwriteConfirmed: $overwriteSaveConfirmed,
        onSave: { target, overwriteExisting in
          if model.save(to: target, overwriteExisting: overwriteExisting) {
            isSaveSheetPresented = false
            savePreviewDocument = nil
          }
          refresh()
        },
        onCancel: {
          isSaveSheetPresented = false
          overwriteSaveConfirmed = false
          savePreviewDocument = nil
        }
      )
    }
    .sheet("Resize canvas", isPresented: $isResizeSheetPresented) {
      ResizeCanvasSheetView(
        currentSize: model.document.size,
        onSelect: { size in
          model.resizeCanvas(to: size)
          isResizeSheetPresented = false
          refresh()
        },
        onCancel: {
          isResizeSheetPresented = false
        }
      )
    }
    .task(id: model.isPlaybackActive) { @MainActor in
      await playFrames(model: model, refresh: refresh)
    }
  }

  /// Single-row status strip at the bottom of the editor. Holds the
  /// transient `statusMessage` from the model on the left and the
  /// cursor / layer / brush-size / render-mode readout on the right.
  /// Document identity and dirty state live in the menu bar's
  /// trailing slot instead.
  private var footer: some View {
    HStack(spacing: 2) {
      Text(model.statusMessage.isEmpty ? "Ready" : model.statusMessage)
        .foregroundStyle(.muted)
      Spacer(minLength: 1)
      Text(
        playbackLabel
          + "F\(model.currentFrameIndex + 1)/\(model.document.frames.count)  "
          + "[\(model.cursor.x),\(model.cursor.y)]  "
          + "L\(model.currentLayerIndex + 1)/\(model.currentFrame.layers.count)  "
          + "B\(model.brushSize)  \(gridModeLabel)"
      )
      .foregroundStyle(.separator)
    }
    .padding(.horizontal, 1)
  }

  private var playbackLabel: String {
    model.isPlaybackActive ? "PLAY  " : ""
  }

  @MainActor
  private func playFrames(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) async {
    while model.isPlaybackActive && !Task.isCancelled {
      try? await Task.sleep(for: model.currentPlaybackDelay)
      guard !Task.isCancelled else { return }
      let didAdvance = model.advancePlaybackFrame()
      refresh()
      guard didAdvance else { return }
    }
  }

  /// Short label for the active canvas pixel-grid mode, shown in the
  /// status strip's render-mode readout.
  private var gridModeLabel: String {
    switch pixelGridMode {
    case .verticalHalfBlock: "half-cell"
    case .fullCell: "full-cell"
    }
  }

  /// 6×6 thumbnail sampled nearest-neighbor from an already-composited frame.
  /// Takes the composited colors (rather than a frame index) so the caller can
  /// reuse the model's memoized composites instead of re-flattening per frame.
  private static func thumbnail(
    from composited: [EditorColor?],
    sourceSize: GIFEditorCore.PixelSize
  ) -> TimelineFrame.Thumbnail {
    let thumbWidth = 6
    let thumbHeight = 6
    var out: [EditorColor?] = []
    out.reserveCapacity(thumbWidth * thumbHeight)
    for ty in 0..<thumbHeight {
      for tx in 0..<thumbWidth {
        let sx = (tx * sourceSize.width) / thumbWidth
        let sy = (ty * sourceSize.height) / thumbHeight
        out.append(composited[sy * sourceSize.width + sx])
      }
    }
    return TimelineFrame.Thumbnail(width: thumbWidth, height: thumbHeight, pixels: out)
  }
}
