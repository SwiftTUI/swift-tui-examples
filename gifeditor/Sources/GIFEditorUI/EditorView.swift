import Foundation
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
  // Zoom and pan are a view concern, not a document one, so they live here
  // beside `pixelGridMode` rather than in the view model. `canvasCellBudget`
  // is the reference box the `GeometryReader` writes its measurement into;
  // see `CanvasCellBudgetBox` for why the measurement cannot be `@State`.
  @State private var canvasViewport = CanvasViewportState()
  @State private var canvasCellBudget = CanvasCellBudgetBox()
  /// Onion skin is display state for the same reason zoom is — it changes
  /// what this window shows and nothing about the file — so it lives here
  /// beside the viewport and needs no document write at all.
  @State private var onionSkin = OnionSkinSettings()
  @State private var isResizeSheetPresented = false
  @State private var isPaletteSheetPresented = false
  /// The `?` overlay. Presented from `KeyBindingHelpHost` in the `ZStack`
  /// below rather than from the root chain — see the warning at the
  /// bottom of `body`.
  @State private var isKeyboardHelpPresented = false
  @State private var isExportSheetPresented = false
  @State private var exportPathText = ""
  @State private var overwriteExportConfirmed = false
  @State private var exportPreviewDocument: GIFDocument?
  @State private var exportPreviewRequestID = 0
  @State private var isExporting = false
  @State private var openMenu: MenuBarMenu?

  // MARK: - File lifecycle state

  /// Which of New / Open / Save As is up. One optional rather than three
  /// booleans, so "two sheets at once" is not a state this view can
  /// reach.
  @State private var fileSheet: FileSheet?
  @State private var openPathText = ""
  @State private var openErrorMessage: String?
  @State private var isOpening = false
  @State private var projectSavePathText = ""
  @State private var overwriteProjectSaveConfirmed = false
  @State private var saveAsFallThroughReason: String?
  @State private var isSavingProject = false
  /// The verb the unsaved-changes guard is holding, and the one it hands
  /// to the save flow when the author picks `Save…` instead of
  /// `Discard`. Two fields because the guard is dismissed the moment the
  /// save begins, and the intent has to outlive it.
  @State private var isUnsavedChangesPresented = false
  @State private var pendingDocumentAction: PendingDocumentAction?
  @State private var queuedAfterSave: PendingDocumentAction?

  /// Fixed width of the right inspector column. Pinning it (rather than
  /// `.fixedSize`) keeps the canvas the sole flexible child of the body
  /// row, so reclaimed horizontal space flows to the canvas instead of
  /// pooling as dead margin to the right of the panel.
  private static let rightPanelWidth = 28

  /// How often the autosave node snapshots the document. A parameter so
  /// a test can drive the real timer at a millisecond scale instead of
  /// waiting out the production interval.
  private let autosaveInterval: Duration

  /// `autosaveInterval` is optional rather than defaulted to
  /// `AutosaveTicker.defaultInterval` for the same reason
  /// `EditorViewModel`'s `stateDirectory` is: a default argument in a
  /// `public` declaration may only name things at least as visible as
  /// the declaration, and the ticker is internal.
  public init(
    document: GIFDocument,
    initialStatusMessage: String = "",
    stateDirectory: URL? = nil,
    recoveredUnsavedWork: Bool = false,
    autosaveInterval: Duration? = nil
  ) {
    _model = State(
      initialValue: EditorViewModel(
        document: document,
        initialStatusMessage: initialStatusMessage,
        stateDirectory: stateDirectory,
        startsDirty: recoveredUnsavedWork
      )
    )
    self.autosaveInterval = autosaveInterval ?? AutosaveTicker.defaultInterval
  }

  public var body: some View {
    // `revision` is read here so the framework's @State subscription
    // tracks it; bumping it via the bindings' `refresh` callback
    // forces a body re-evaluation against the (already-mutated)
    // model. A future @Observable adoption can drop this seam.
    _ = revision
    let model = self.model
    let refresh: @MainActor @Sendable () -> Void = { revision &+= 1 }
    let presentExportSheet: @MainActor @Sendable () -> Void = {
      exportPathText = model.defaultExportURL.path
      overwriteExportConfirmed = false
      exportPreviewDocument = model.document
      exportPreviewRequestID &+= 1
      isExportSheetPresented = true
      openMenu = nil
    }
    let presentPaletteSheet: @MainActor @Sendable () -> Void = {
      isPaletteSheetPresented = true
      openMenu = nil
    }
    let presentKeyboardHelp: @MainActor @Sendable () -> Void = {
      isKeyboardHelpPresented = true
      openMenu = nil
    }

    // MARK: File verbs
    //
    // Declared in dependency order — each closure captures the ones
    // above it — and every one of them is reachable from both the menu
    // and a keybinding through the single `fileActions` value below.

    let beginOpen: @MainActor @Sendable (URL) -> Void = { url in
      guard !isOpening else { return }
      isOpening = true
      openErrorMessage = nil
      openMenu = nil
      model.announce("Opening \(url.lastPathComponent)…")
      refresh()
      Task { @MainActor in
        let opened = await model.openDocumentOffMain(contentsOf: url)
        isOpening = false
        if opened {
          fileSheet = nil
          openErrorMessage = nil
        } else {
          // Stay up and say why. A sheet that vanishes over a typo
          // makes the author retype the whole path to find out what
          // went wrong.
          openPathText = url.path
          openErrorMessage = model.statusMessage
          fileSheet = .open
        }
        refresh()
      }
    }

    let presentSaveAsSheet: @MainActor @Sendable (String?) -> Void = { reason in
      projectSavePathText = model.defaultProjectSaveURL.path
      overwriteProjectSaveConfirmed = false
      saveAsFallThroughReason = reason
      fileSheet = .saveAs
      openMenu = nil
    }

    let performDocumentAction: @MainActor @Sendable (PendingDocumentAction) -> Void = { action in
      switch action {
      case .new:
        fileSheet = .new
      case .open:
        openPathText = ""
        openErrorMessage = nil
        fileSheet = .open
      case .openRecent(let url):
        beginOpen(url)
      case .quit:
        // A termination handler can only allow or cancel; it cannot end
        // the run loop itself. So "discard and quit" is spelled as
        // *disarm the guard, then quit again*, and the status line is
        // what makes that a two-step the author expects rather than a
        // key press that appeared to do nothing.
        model.allowsQuitWithUnsavedChanges = true
        model.announce("Changes discarded — press the exit key again to quit")
      }
    }

    let resumeQueuedAction: @MainActor @Sendable () -> Void = {
      guard let queued = queuedAfterSave else { return }
      queuedAfterSave = nil
      performDocumentAction(queued)
    }

    let performSave: @MainActor @Sendable () -> Void = {
      switch model.saveRoute {
      case .writeBack(let target):
        guard !isSavingProject else { return }
        isSavingProject = true
        openMenu = nil
        model.announce("Saving…")
        refresh()
        Task { @MainActor in
          // `overwriteExisting: true`: the target *is* this document's
          // own project file, so there is nothing to confirm.
          let saved = await model.saveProjectOffMain(to: target, overwriteExisting: true)
          isSavingProject = false
          if saved {
            resumeQueuedAction()
          }
          refresh()
        }
      case .promptForLocation:
        // The fall-through. A document that came from a GIF has a
        // `path`, and writing a layered document back over it would
        // flatten every layer under a verb that promises the opposite.
        presentSaveAsSheet(Self.saveFallThroughReason(for: model.document))
      }
    }

    let requestDocumentAction: @MainActor @Sendable (PendingDocumentAction) -> Void = { action in
      openMenu = nil
      guard model.isDirty else {
        performDocumentAction(action)
        return
      }
      pendingDocumentAction = action
      isUnsavedChangesPresented = true
    }

    let fileActions = FileMenuActions(
      new: { requestDocumentAction(.new) },
      open: { requestDocumentAction(.open) },
      openRecent: { url in requestDocumentAction(.openRecent(url)) },
      save: performSave,
      saveAs: { presentSaveAsSheet(nil) },
      exportGIF: presentExportSheet
    )
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
    // Onion-skin ghosts, drawn from the same memoized composites the canvas
    // and the timeline already read. Adjacent frames are in that cache
    // because the timeline needs their thumbnails, so a ghost costs no
    // compositing work — only the per-visible-cell blend inside the canvas's
    // bounded loop.
    let ghostLayers = onionSkin.ghostLayers(
      around: model.currentFrameIndex,
      composites: composites
    )
    let primaryColor = model.document.palette[model.primaryColorIndex]
    let secondaryColor = model.document.palette[model.secondaryColorIndex]
    let viewportCommands = self.viewportCommands(model: model)
    let onionSkinCommands = self.onionSkinCommands(model: model, refresh: refresh)

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
          // No `ScrollView` here any more. The viewport clips in source-pixel
          // space *before* colors are resolved, so a second clipping authority
          // would only double-scroll the same content — and would reintroduce
          // the "materialize the whole canvas, then throw most of it away"
          // cost the viewport exists to delete.
          GeometryReader { proxy in
            canvasRegion(
              cellBudget: proxy.size,
              model: model,
              frameColors: frameColors,
              ghosts: ghostLayers,
              viewportCommands: viewportCommands,
              onionSkinCommands: onionSkinCommands,
              presentKeyboardHelp: presentKeyboardHelp,
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
          onionSkin: $onionSkin,
          fileActions: fileActions,
          presentPaletteSheet: presentPaletteSheet,
          presentKeyboardHelp: presentKeyboardHelp,
          refresh: refresh
        )
        .offset(x: openMenu.dropdownOffset + 1, y: 1)
      }

      // The autosave clock. It lives here, on a node of its own, rather
      // than as a second `.task` on this view's root — that node's one
      // task is already spent on playback, and the framework supports
      // exactly one per node (see `AutosaveTicker`).
      AutosaveTicker(interval: autosaveInterval) {
        model.writeAutosaveSnapshot(at: Date())
      }

      // The "press ?" nudge, spent once per state directory. Its own node
      // for the same reason the ticker has one: the root's single `.task`
      // is already playback's.
      FirstRunHintView(stateDirectory: model.stateDirectory) {
        model.announce(FirstRunHint.message)
        refresh()
      }

      // The `?` overlay. A presentation, so it goes on a sibling node
      // rather than the root chain — see the warning below.
      KeyBindingHelpHost(isPresented: $isKeyboardHelpPresented)

      // The unsaved-changes guard and the New / Open / Save As sheets,
      // also on a node of their own. Same reason as the ticker, a
      // different budget: see `FilePresentationHost` for why two more
      // modifiers on the root chain overflow the resolve stack.
      FilePresentationHost(
        isUnsavedChangesPresented: $isUnsavedChangesPresented,
        fileSheet: $fileSheet,
        openPathText: $openPathText,
        projectSavePathText: $projectSavePathText,
        overwriteProjectSaveConfirmed: $overwriteProjectSaveConfirmed,
        pendingAction: pendingDocumentAction,
        recentDocuments: model.recentDocuments.urls,
        openErrorMessage: openErrorMessage,
        isOpening: isOpening,
        isSavingProject: isSavingProject,
        saveAsFallThroughReason: saveAsFallThroughReason,
        onGuardSave: {
          isUnsavedChangesPresented = false
          // The guard closes now, so the intent has to move somewhere
          // that outlives it; the save flow picks it back up once the
          // write actually lands.
          queuedAfterSave = pendingDocumentAction
          pendingDocumentAction = nil
          performSave()
          refresh()
        },
        onGuardDiscard: {
          isUnsavedChangesPresented = false
          let action = pendingDocumentAction
          pendingDocumentAction = nil
          if let action {
            performDocumentAction(action)
          }
          refresh()
        },
        onGuardCancel: {
          isUnsavedChangesPresented = false
          pendingDocumentAction = nil
          refresh()
        },
        onCreateDocument: { size in
          model.newDocument(size: size)
          // The document that was on screen is gone, so a recovery file
          // describing it is an offer to reopen work the author just
          // chose to leave behind.
          model.clearAutosaveSnapshot()
          fileSheet = nil
          refresh()
        },
        onOpenDocument: beginOpen,
        onSaveProject: { target, overwriteExisting in
          guard !isSavingProject else { return }
          isSavingProject = true
          model.announce("Saving...")
          refresh()
          Task { @MainActor in
            let saved = await model.saveProjectOffMain(
              to: target,
              overwriteExisting: overwriteExisting
            )
            isSavingProject = false
            if saved {
              fileSheet = nil
              saveAsFallThroughReason = nil
              // A `Save…` answer to the guard only finishes here, once
              // the bytes are actually down.
              resumeQueuedAction()
            }
            refresh()
          }
        },
        onCancelSheet: {
          fileSheet = nil
          openErrorMessage = nil
          overwriteProjectSaveConfirmed = false
          saveAsFallThroughReason = nil
          // Backing out of the save turns off the verb that was waiting
          // on it — proceeding would discard exactly the work the author
          // just declined to lose.
          queuedAfterSave = nil
          refresh()
        }
      )
    }
    // The root's modifier chain is at its depth budget. Resolution
    // recurses once per nested `ModifiedContent` layer, and this chain is
    // ~40 deep once the keybinding chains are expanded; adding two more
    // presentation modifiers here overflowed the resolve stack outright
    // (the whole editor crashed, not just the new sheets). New
    // presentations and new `.task`s go on their own node — see
    // `FilePresentationHost` and `AutosaveTicker` in the `ZStack` above.
    .panel(id: "gifeditor")
    .applyFocusedEditorBindings(
      model: model,
      viewport: viewportCommands,
      onionSkin: onionSkinCommands,
      showKeyboardHelp: presentKeyboardHelp,
      refresh: refresh
    )
    .applyCursorBindings(model: model, viewport: viewportCommands, refresh: refresh)
    .applyViewportBindings(viewport: viewportCommands, refresh: refresh)
    .applyFrameBindings(model: model, refresh: refresh)
    .applyLayerBindings(model: model, refresh: refresh)
    .applyClipboardBindings(model: model, refresh: refresh)
    .applyHistoryBindings(model: model, refresh: refresh)
    .applyPaletteBindings(
      model: model,
      presentPaletteSheet: presentPaletteSheet,
      refresh: refresh
    )
    .applyFileBindings(
      isResizeSheetPresented: $isResizeSheetPresented,
      fileActions: fileActions,
      refresh: refresh
    )
    .applyTerminationHandling(
      model: model,
      confirmUnsavedChanges: { requestDocumentAction(.quit) },
      refresh: refresh
    )
    .sheet("Export GIF", isPresented: $isExportSheetPresented) {
      SaveGIFPreviewSheetView(
        document: exportPreviewDocument ?? model.document,
        requestID: exportPreviewRequestID,
        pathText: $exportPathText,
        overwriteConfirmed: $overwriteExportConfirmed,
        onSave: { target, overwriteExisting in
          guard !isExporting else {
            return
          }
          isExporting = true
          model.announce("Exporting...")
          refresh()
          Task {
            @MainActor in
            let exported = await model.exportGIFOffMain(
              to: target,
              overwriteExisting: overwriteExisting
            )
            isExporting = false
            if exported {
              isExportSheetPresented = false
              exportPreviewDocument = nil
            }
            refresh()
          }
        },
        onCancel: {
          isExportSheetPresented = false
          overwriteExportConfirmed = false
          exportPreviewDocument = nil
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
    .sheet("Palette", isPresented: $isPaletteSheetPresented) {
      PaletteEditorSheetView(
        model: model,
        refresh: refresh,
        onClose: {
          isPaletteSheetPresented = false
        }
      )
    }
    .task(id: model.isPlaybackActive) { @MainActor in
      await playFrames(model: model, refresh: refresh)
    }
  }

  /// Why `Save` sent the author to `Save As` instead of just writing.
  ///
  /// Only ever non-nil when the document has a path that is *not* a
  /// project file, which is exactly the case the fall-through exists
  /// for. An untitled document needs no explanation: it has never had a
  /// location, so of course it is being asked for one.
  static func saveFallThroughReason(for document: GIFDocument) -> String? {
    guard let path = document.path, !GIFDocumentIO.isProjectFile(path) else {
      return nil
    }
    return "\(path.lastPathComponent) is an export — saving there would flatten every layer."
  }

  /// What the unsaved-changes guard says, named for the verb that
  /// triggered it so the author knows what they are about to lose it to.
  static func unsavedChangesMessage(for action: PendingDocumentAction?) -> String {
    let verb: String
    switch action {
    case .new: verb = "Starting a new document"
    case .open, .openRecent: verb = "Opening another document"
    case .quit: verb = "Quitting"
    case nil: verb = "This"
    }
    return "\(verb) will discard unsaved changes. Save writes the layered project."
  }

  /// The canvas, sized against the cell budget the layout system just handed
  /// the region.
  ///
  /// Recording the budget here — inside the `GeometryReader`'s content, which
  /// is realized during layout — is a plain object write, not a `@State`
  /// mutation, so it cannot re-enter the layout pass that produced it. The
  /// render itself never reads the box: it resolves the viewport straight from
  /// `cellBudget`, so what is drawn is always measured, never remembered.
  private func canvasRegion(
    cellBudget: CellSize,
    model: EditorViewModel,
    frameColors: [EditorColor?],
    ghosts: [CanvasGhostLayer],
    viewportCommands: CanvasViewportCommands,
    onionSkinCommands: OnionSkinCommands,
    presentKeyboardHelp: @escaping @MainActor @Sendable () -> Void,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    canvasCellBudget.record(cellBudget)
    let viewport = canvasViewport.resolved(
      in: CanvasViewportContext(
        canvasSize: model.document.size,
        cellBudget: cellBudget,
        mode: pixelGridMode
      )
    )
    return InteractiveCanvasView(
      size: model.document.size,
      cells: frameColors,
      model: model,
      refresh: refresh,
      mode: pixelGridMode,
      viewport: viewport,
      ghosts: ghosts
    )
    .applyFocusedEditorBindings(
      model: model,
      viewport: viewportCommands,
      onionSkin: onionSkinCommands,
      showKeyboardHelp: presentKeyboardHelp,
      refresh: refresh
    )
  }

  /// The onion-skin closures the key bindings and the View menu drive.
  ///
  /// Each one mutates the `@State` value and announces the result, so a key
  /// that changes something invisible — turning ghosting on with only one
  /// frame in the document, say — still says what it did. `announce` writes
  /// the status line and nothing else: no document write, so no dirty flag
  /// and no undo entry.
  private func onionSkinCommands(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> OnionSkinCommands {
    func apply(_ change: @escaping (inout OnionSkinSettings) -> Void)
      -> @MainActor @Sendable () -> Void
    {
      {
        change(&onionSkin)
        model.announce(onionSkin.announcement)
        refresh()
      }
    }
    return OnionSkinCommands(
      toggle: apply { $0.toggle() },
      cycleSides: apply { $0.cycleSides() },
      increaseDepth: apply { $0.increaseDepth() },
      decreaseDepth: apply { $0.decreaseDepth() }
    )
  }

  /// The zoom/pan/follow closures the key bindings drive.
  ///
  /// They read the *last measured* cell budget rather than a live one, because
  /// a key press happens between renders. A stale budget can only mis-size a
  /// pan step for one frame after a terminal resize; the next render corrects
  /// the box, and the rendered viewport was never wrong to begin with.
  private func viewportCommands(model: EditorViewModel) -> CanvasViewportCommands {
    let budget = canvasCellBudget
    let mode = pixelGridMode
    let context: @MainActor @Sendable () -> CanvasViewportContext = {
      CanvasViewportContext(
        canvasSize: model.document.size,
        cellBudget: budget.current,
        mode: mode
      )
    }
    return CanvasViewportCommands(
      zoomIn: { canvasViewport.zoomIn(cursor: model.cursor, in: context()) },
      zoomOut: { canvasViewport.zoomOut(cursor: model.cursor, in: context()) },
      fitToWindow: { canvasViewport.fitToWindow(cursor: model.cursor, in: context()) },
      pan: { dx, dy in canvasViewport.pan(dx: dx, dy: dy, in: context()) },
      followCursor: { canvasViewport.follow(cursor: model.cursor, in: context()) }
    )
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
          + "B\(model.brushSize)  \(canvasViewport.level.label)  "
          + onionSkinLabel
          + gridModeLabel
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

  /// Onion-skin readout, or nothing at all when it is off — the default
  /// state should not spend columns of an 80-wide status strip saying so.
  private var onionSkinLabel: String {
    let label = onionSkin.statusLabel
    return label.isEmpty ? "" : label + "  "
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
