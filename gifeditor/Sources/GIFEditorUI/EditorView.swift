import Foundation
import GIFEditorCore
import SwiftTUI

/// Public root view of the editor. Owns one `EditingSession` for the
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
///
/// ## How the stack answers to the terminal's height
///
/// Every region above is a fixed number of rows except the body row, which
/// takes whatever is left; that is what puts the status strip on the bottom
/// line of a 40-row terminal and gives every row the chrome saves to the
/// canvas. When even the fixed rows do not fit — and at the 24 rows a default
/// terminal opens at, they did not — ``EditorLayoutDensity`` is what they
/// compress by, in the order set out there. Below the compressed layout's own
/// measured floor, ``TerminalFitGate`` shows a sentence instead of a surface
/// the terminal cannot hold.
public struct EditorView: View {
  // The view-model is a reference type, so we just hold it as an
  // @State (the Reference Box pattern). Mutating @MainActor methods on
  // it advance state in-place; we still mark the @State so the
  // framework treats this view as having local-owned state.
  @State private var lifecycle: DocumentLifecycle
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

  // MARK: - Terminal environment
  //
  // Both are refreshed by the run loop on every frame from the live
  // presentation surface, so a resize or a terminal that answers the
  // background-color query late is picked up on the next render without the
  // editor watching for either.

  /// The terminal's own foreground/background/palette, as SwiftTUI resolved
  /// them (an `OSC 11` query, then `COLORFGBG`, then a dark default). The
  /// editor spends it on one question — light terminal or dark — through
  /// ``EditorBackgroundAppearance``.
  @Environment(\.terminalAppearance) private var terminalAppearance
  /// The whole terminal, which is what ``EditorLayoutFloor`` is a floor on.
  /// The canvas region's own budget comes from the `GeometryReader` below and
  /// is a different question.
  @Environment(\.terminalSize) private var terminalSize

  // MARK: - File lifecycle state

  /// Which of New / Open / Save As is up. One optional rather than three
  /// booleans, so "two sheets at once" is not a state this view can
  /// reach.
  @State private var openPathText = ""
  @State private var projectSavePathText = ""
  @State private var overwriteProjectSaveConfirmed = false

  /// How much color the terminal can show, resolved once per process.
  ///
  /// A stored property rather than a read of ``EditorColorFidelity/detected``
  /// at every use site, so a test can build an editor pinned to `.reduced`
  /// without a true-color terminal to run it in.
  private let colorFidelity: EditorColorFidelity

  /// How often the autosave node snapshots the document. A parameter so
  /// a test can drive the real timer at a millisecond scale instead of
  /// waiting out the production interval.
  private let autosaveInterval: Duration

  private var model: EditingSession {
    lifecycle.session
  }

  /// `autosaveInterval` is optional rather than defaulted to
  /// `AutosaveTicker.defaultInterval` because a default argument in a
  /// `public` declaration may only name things at least as visible as
  /// the declaration, and the ticker is internal.
  ///
  /// The internal overload below adds `colorFidelity`, which is off this
  /// signature for the same reason and answers the same need: a test has to
  /// be able to build the 256-color editor without a 256-color terminal to
  /// run it in.
  public init(
    document: GIFDocument,
    origin: DocumentOrigin? = nil,
    projectBacking: ProjectBacking? = nil,
    initialStatusMessage: String = "",
    stateDirectory: URL? = nil,
    recoveredUnsavedWork: Bool = false,
    autosaveInterval: Duration? = nil
  ) {
    self.init(
      document: document,
      origin: origin,
      projectBacking: projectBacking,
      initialStatusMessage: initialStatusMessage,
      stateDirectory: stateDirectory,
      recoveredUnsavedWork: recoveredUnsavedWork,
      autosaveInterval: autosaveInterval,
      colorFidelity: nil
    )
  }

  /// Builds the editor around an already prepared lifecycle. The composition
  /// root uses this after launch loading and recovery have been resolved by
  /// `DocumentLifecycle`.
  public init(
    lifecycle: DocumentLifecycle,
    autosaveInterval: Duration? = nil
  ) {
    _lifecycle = State(initialValue: lifecycle)
    self.autosaveInterval = autosaveInterval ?? AutosaveTicker.defaultInterval
    colorFidelity = .detected
  }

  init(
    document: GIFDocument,
    origin: DocumentOrigin? = nil,
    projectBacking: ProjectBacking? = nil,
    initialStatusMessage: String = "",
    stateDirectory: URL? = nil,
    recoveredUnsavedWork: Bool = false,
    autosaveInterval: Duration? = nil,
    colorFidelity: EditorColorFidelity?
  ) {
    _lifecycle = State(
      initialValue: DocumentLifecycle(
        document: document,
        origin: origin,
        projectBacking: projectBacking,
        initialStatusMessage: initialStatusMessage,
        stateDirectory: stateDirectory,
        startsDirty: recoveredUnsavedWork
      )
    )
    self.autosaveInterval = autosaveInterval ?? AutosaveTicker.defaultInterval
    self.colorFidelity = colorFidelity ?? .detected
  }

  public var body: some View {
    // `revision` is read here so the framework's @State subscription
    // tracks it; bumping it via the bindings' `refresh` callback
    // forces a body re-evaluation against the (already-mutated)
    // model. A future @Observable adoption can drop this seam.
    _ = revision
    let lifecycle = self.lifecycle
    let model = lifecycle.session
    let refresh: @MainActor @Sendable () -> Void = { revision &+= 1 }
    let presentExportSheet: @MainActor @Sendable () -> Void = {
      exportPathText = lifecycle.defaultExportURL.path
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
    // The lifecycle serializes every transition. This closure only bridges an
    // event into its async state machine and refreshes the reference-box view.
    let dispatchLifecycle: @MainActor @Sendable (DocumentLifecycle.Intent) -> Void = {
      intent in
      let wasSaveAs = lifecycle.fileSheet == .saveAs
      switch intent {
      case .autosave:
        break  // A background tick must not dismiss UI the author is using.
      default:
        openMenu = nil
      }
      Task { @MainActor in
        _ = await lifecycle.dispatch(intent, onTransition: refresh)
        // Autosave changes no presented or Editing state. Invalidating the
        // whole terminal every tick creates a perpetual render loop even
        // for a clean document and can starve input delivery.
        if case .autosave = intent {
          return
        }
        if !wasSaveAs, lifecycle.fileSheet == .saveAs {
          projectSavePathText = lifecycle.defaultProjectSaveURL.path
          overwriteProjectSaveConfirmed = false
        }
        refresh()
      }
    }

    let fileActions = FileMenuActions(
      new: { dispatchLifecycle(.request(.new)) },
      open: {
        openPathText = ""
        dispatchLifecycle(.request(.open))
      },
      openRecent: { url in dispatchLifecycle(.request(.openRecent(url))) },
      save: { dispatchLifecycle(.requestSave) },
      saveAs: { dispatchLifecycle(.requestSaveAs) },
      exportGIF: presentExportSheet
    )
    // How much of the terminal's height the chrome may spend. Read from the
    // live `terminalSize`, so a resize picks the other layout up on the next
    // frame without this view watching for one — and derived from the
    // regular layout's own measured minimum rather than from a threshold
    // somebody chose. See `EditorLayoutDensity`.
    let density = EditorLayoutFloor.density(for: terminalSize)
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
          thumbnail: Self.thumbnail(
            from: composites[index],
            sourceSize: model.document.size,
            side: density.timelineThumbnailSide
          ),
          delayCentiseconds: model.document.frames[index].delayCentiseconds
        )
      }
      : []
    // The terminal's own appearance and color depth, resolved into the
    // checkerboard shades, overlay-mark colors and onion tints the canvas
    // draws with. Rebuilt per body evaluation because
    // `\.terminalAppearance` is refreshed per frame: a background-color
    // query that answers late lands on the next render rather than never.
    let theme = EditorTheme(
      appearance: EditorBackgroundAppearance(terminalAppearance),
      fidelity: colorFidelity
    )
    // Onion-skin ghosts, drawn from the same memoized composites the canvas
    // and the timeline already read. Adjacent frames are in that cache
    // because the timeline needs their thumbnails, so a ghost costs no
    // compositing work — only the per-visible-cell blend inside the canvas's
    // bounded loop.
    let ghostLayers = onionSkin.ghostLayers(
      around: model.currentFrameIndex,
      composites: composites,
      theme: theme
    )
    let primaryColor = model.document.palette[model.primaryColorIndex]
    let secondaryColor = model.document.palette[model.secondaryColorIndex]
    let viewportCommands = self.viewportCommands(model: model)
    let onionSkinCommands = self.onionSkinCommands(model: model, refresh: refresh)
    // Below `EditorLayoutFloor.minimumWidth` the layout stops shrinking and
    // starts overflowing the terminal instead — the inspector runs off the
    // right edge, the timeline's labels stack a letter per row, and the
    // status strip breaks words mid-syllable. `TerminalFitGate` swaps the
    // whole stack for a sentence there. It sits inside the `ZStack`, around
    // the body's content, rather than around `body` itself: the root's
    // modifier chain is at its resolve-stack budget (see the note after this
    // `ZStack`), and wrapping that chain in a conditional would spend depth
    // this view does not have.
    let fitsTerminal = EditorLayoutFloor.fits(terminalSize)

    return ZStack(alignment: .topLeading) {
      TerminalFitGate(fits: fitsTerminal, available: terminalSize) {
        // `maxHeight: .infinity` on the stack, and on the body row inside it,
        // are what make the editor *fill* the terminal rather than sit in the
        // top of it: without them the stack is as tall as the sum of its
        // regions' ideals and a 40-row terminal shows the status strip on row
        // 21 with a band of dead rows under it.
        VStack(alignment: .leading, spacing: 0) {
          MenuBarView(
            openMenu: $openMenu,
            model: model,
            documentTitle: lifecycle.documentTitle,
            showsToolDock: $showsToolDock,
            showsRightPanel: $showsRightPanel,
            showsTimeline: $showsTimeline,
            pixelGridMode: $pixelGridMode,
            isResizeSheetPresented: $isResizeSheetPresented,
            refresh: refresh
          )
          ToolOptionsBar(
            model: model,
            refresh: refresh,
            density: density
          )
          HStack(alignment: .top, spacing: 1) {
            if showsToolDock {
              ToolboxView(
                tool: model.tool,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                model: model,
                refresh: refresh,
                density: density
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
                theme: theme,
                viewportCommands: viewportCommands,
                onionSkinCommands: onionSkinCommands,
                presentKeyboardHelp: presentKeyboardHelp,
                refresh: refresh
              )
            }
            .border(.separator, set: .single, placement: .outset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if showsRightPanel {
              InspectorColumnView(
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                palette: model.document.palette,
                primaryIndex: model.primaryColorIndex,
                secondaryIndex: model.secondaryColorIndex,
                layers: model.currentFrame.layers,
                selectedLayerIndex: model.currentLayerIndex,
                model: model,
                refresh: refresh,
                fidelity: theme.fidelity,
                density: density
              )
              .frame(maxHeight: .infinity, alignment: .top)
            }
          }
          // The body row is the editor's one flexible region: every other
          // region is a fixed number of rows, so the terminal's spare height
          // has exactly one place to go and the status strip stays on the
          // bottom line instead of floating above a band of dead rows.
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          if showsTimeline {
            TimelineView(
              frames: timelineFrames,
              currentFrameIndex: model.currentFrameIndex,
              model: model,
              refresh: refresh
            )
          }
          if density.drawsRedundantRules {
            Divider()
          }
          footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      // Only reachable while the editor itself is on screen: the menu bar is
      // what opens a dropdown, and it is the first thing the fit gate takes
      // away.
      if fitsTerminal, let openMenu {
        MenuBarDropdownView(
          menu: openMenu,
          openMenu: $openMenu,
          model: model,
          recentDocuments: lifecycle.recentDocuments.urls,
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
        dispatchLifecycle(.autosave(Date()))
      }

      // The "press ?" nudge, spent once per state directory. Its own node
      // for the same reason the ticker has one: the root's single `.task`
      // is already playback's.
      FirstRunHintView(stateDirectory: lifecycle.stateDirectory) {
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
        isUnsavedChangesPresented: Binding(
          get: { lifecycle.isUnsavedChangesPresented },
          set: { shown in
            if !shown { dispatchLifecycle(.cancelPresentation) }
          }
        ),
        fileSheet: Binding(
          get: { lifecycle.fileSheet },
          set: { sheet in
            if sheet == nil { dispatchLifecycle(.cancelPresentation) }
          }
        ),
        openPathText: $openPathText,
        projectSavePathText: $projectSavePathText,
        overwriteProjectSaveConfirmed: $overwriteProjectSaveConfirmed,
        pendingAction: lifecycle.pendingAction,
        recentDocuments: lifecycle.recentDocuments.urls,
        openErrorMessage: lifecycle.openErrorMessage,
        isOpening: lifecycle.isOpening,
        isSavingProject: lifecycle.isSaving,
        saveAsFallThroughReason: lifecycle.saveFallThroughReason,
        onGuardSave: {
          dispatchLifecycle(.dirtyDecision(.save))
        },
        onGuardDiscard: {
          dispatchLifecycle(.dirtyDecision(.discard))
        },
        onGuardCancel: {
          dispatchLifecycle(.dirtyDecision(.cancel))
        },
        onCreateDocument: { size in
          dispatchLifecycle(.create(size))
        },
        onOpenDocument: { url in
          openPathText = url.path
          dispatchLifecycle(.open(url))
        },
        onSaveProject: { target, overwriteExisting in
          dispatchLifecycle(.saveAs(target, overwriteExisting: overwriteExisting))
        },
        onCancelSheet: {
          overwriteProjectSaveConfirmed = false
          dispatchLifecycle(.cancelPresentation)
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
      lifecycle: lifecycle,
      confirmUnsavedChanges: { dispatchLifecycle(.request(.quit)) },
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
            let exported = await lifecycle.exportGIF(
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
          model.dispatch(.resizeCanvas(size))
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
    model: EditingSession,
    frameColors: [EditorColor?],
    ghosts: [CanvasGhostLayer],
    theme: EditorTheme,
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
      ghosts: ghosts,
      theme: theme
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
    model: EditingSession,
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
  private func viewportCommands(model: EditingSession) -> CanvasViewportCommands {
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

  /// The status strip, filled in from the model. The row itself lives in
  /// ``EditorStatusStripView`` so the floor can measure it.
  private var footer: some View {
    EditorStatusStripView(
      message: model.statusMessage,
      readout: playbackLabel
        + "F\(model.currentFrameIndex + 1)/\(model.document.frames.count)  "
        + "[\(model.cursor.x),\(model.cursor.y)]  "
        + "L\(model.currentLayerIndex + 1)/\(model.currentFrame.layers.count)  "
        + "B\(model.brushSize)  \(canvasViewport.level.label)  "
        + onionSkinLabel
        + gridModeLabel
    )
  }

  private var playbackLabel: String {
    model.isPlaybackActive ? "PLAY  " : ""
  }

  @MainActor
  private func playFrames(
    model: EditingSession,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) async {
    while model.isPlaybackActive && !Task.isCancelled {
      try? await Task.sleep(for: model.currentPlaybackDelay)
      guard !Task.isCancelled else { return }
      let previousFrame = model.currentFrameIndex
      model.dispatch(.advancePlaybackFrame)
      let didAdvance = model.currentFrameIndex != previousFrame
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

  /// Square thumbnail sampled nearest-neighbor from an already-composited
  /// frame. Takes the composited colors (rather than a frame index) so the
  /// caller can reuse the model's memoized composites instead of re-flattening
  /// per frame.
  ///
  /// `side` is the third rung of the compression ladder: 6 where the timeline
  /// has the rows for three half-block rows of picture, 4 where it has two.
  /// Every frame stays in the strip either way — this shrinks the pictures,
  /// not the film. ``TimelineDragMath/slotPitch(thumbnailWidth:)`` reads the
  /// width back off the thumbnail, so drag-to-reorder follows it.
  private static func thumbnail(
    from composited: [EditorColor?],
    sourceSize: GIFEditorCore.PixelSize,
    side: Int
  ) -> TimelineFrame.Thumbnail {
    let thumbWidth = side
    let thumbHeight = side
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
