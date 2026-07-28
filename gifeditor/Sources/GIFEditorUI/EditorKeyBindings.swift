import GIFEditorCore
import SwiftTUI

extension View {
  func applyFocusedEditorBindings(
    model: EditingSession,
    viewport: CanvasViewportCommands = .inert,
    onionSkin: OnionSkinCommands = .inert,
    showKeyboardHelp: @escaping @MainActor @Sendable () -> Void = {},
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> ModifiedContent<Self, KeyPressModifier> {
    onKeyPress(.any) { keyPress in
      guard
        handleFocusedEditorKey(
          keyPress,
          model: model,
          viewport: viewport,
          onionSkin: onionSkin,
          showKeyboardHelp: showKeyboardHelp
        )
      else {
        return .ignored
      }

      refresh()
      return .handled
    }
  }
}

/// Focused-key and key-command chains for the editor.
///
/// `keyCommand` is only callable on a view that conforms to
/// `ActionScope` (e.g. one that has been wrapped with `.panel(id:)`),
/// so we can't compose these as `ViewModifier`s — `Content` in a
/// `ViewModifier.body` is a plain `View` without the action-scope
/// conformance. Instead we expose generic functions that take an
/// `ActionScope`-conforming view and return one. The editor view
/// chains modifier-bearing commands onto its panel, while bare focused
/// keys are also applied to the focusable canvas.
///
/// Every site below names a `KeyBindingCatalog` command rather than a
/// key, a modifier set and a label. The chord and the description come
/// out of the catalog, so the `?` overlay and `docs/KEYBINDINGS.md`
/// describe what is actually installed by construction rather than by
/// diligence. See `KeyBindingBridge.swift` for the overload that does it.
extension View where Self: ActionScope & Sendable {
  func applyCursorBindings(
    model: EditingSession,
    viewport: CanvasViewportCommands = .inert,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.jumpCursorLeft) {
        model.dispatch(.moveCursor(dx: -8, dy: 0))
        viewport.followCursor()
        refresh()
      }
      .keyCommand(.jumpCursorRight) {
        model.dispatch(.moveCursor(dx: 8, dy: 0))
        viewport.followCursor()
        refresh()
      }
      .keyCommand(.jumpCursorUp) {
        model.dispatch(.moveCursor(dx: 0, dy: -8))
        viewport.followCursor()
        refresh()
      }
      .keyCommand(.jumpCursorDown) {
        model.dispatch(.moveCursor(dx: 0, dy: 8))
        viewport.followCursor()
        refresh()
      }
  }

  /// Explicit viewport panning.
  ///
  /// `Alt+arrow` is the one arrow chord still free: bare arrows move the
  /// cursor by a pixel and `Ctrl+arrow` jumps it by eight, and neither of the
  /// terminal-ambiguous families `docs/KEYBINDINGS.md` documents (`Ctrl+digit`,
  /// `Ctrl+Shift+letter`, `Alt+[`) covers it. Panning is deliberately *not*
  /// followed by a cursor-follow: that is the one action whose whole purpose is
  /// to look somewhere the cursor is not.
  func applyViewportBindings(
    viewport: CanvasViewportCommands,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.panLeft) {
        viewport.pan(-1, 0)
        refresh()
      }
      .keyCommand(.panRight) {
        viewport.pan(1, 0)
        refresh()
      }
      .keyCommand(.panUp) {
        viewport.pan(0, -1)
        refresh()
      }
      .keyCommand(.panDown) {
        viewport.pan(0, 1)
        refresh()
      }
  }

  func applyFrameBindings(
    model: EditingSession,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.previousFrame) {
        model.dispatch(.previousFrame)
        refresh()
      }
      .keyCommand(.nextFrame) {
        model.dispatch(.nextFrame)
        refresh()
      }
      .keyCommand(.newFrame) {
        model.dispatch(.insertBlankFrame)
        refresh()
      }
      .keyCommand(.duplicateFrame) {
        model.dispatch(.duplicateFrame)
        refresh()
      }
      .keyCommand(.deleteFrame) {
        model.dispatch(.deleteFrame)
        refresh()
      }
      .keyCommand(.decreaseFrameDelay) {
        model.dispatch(.adjustFrameDelay(-10))
        refresh()
      }
      .keyCommand(.increaseFrameDelay) {
        model.dispatch(.adjustFrameDelay(10))
        refresh()
      }
      .keyCommand(.equalizeFrameDelays) {
        model.dispatch(.setAllFrameDelaysToCurrent)
        refresh()
      }
      .keyCommand(.togglePlayback) {
        model.dispatch(.togglePlayback)
        refresh()
      }
  }

  func applyLayerBindings(
    model: EditingSession,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.newLayer) {
        model.dispatch(.addLayer)
        refresh()
      }
      .keyCommand(.selectLayerBelow) {
        model.dispatch(.selectLayerBelow)
        refresh()
      }
      .keyCommand(.selectLayerAbove) {
        model.dispatch(.selectLayerAbove)
        refresh()
      }
      .keyCommand(.toggleLayerVisibility) {
        model.dispatch(.toggleCurrentLayerVisibility)
        refresh()
      }
      .keyCommand(.deleteLayer) {
        model.dispatch(.deleteCurrentLayer)
        refresh()
      }
  }

  func applyClipboardBindings(
    model: EditingSession,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.copySelection) {
        model.dispatch(.copySelection)
        refresh()
      }
      .keyCommand(.paste) {
        model.dispatch(.paste)
        refresh()
      }
  }

  func applyHistoryBindings(
    model: EditingSession,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.undo) {
        model.dispatch(.undo)
        refresh()
      }
      .keyCommand(.redo) {
        model.dispatch(.redo)
        refresh()
      }
  }

  /// Colour selection plus the palette editor sheet.
  ///
  /// `Ctrl+P` opens the sheet: it joins `Ctrl+S` (save) and `Ctrl+R`
  /// (resize) as the third sheet-opening chord, and it is the only
  /// spelling of `p` still free — bare `p` picks the pen and `Alt+P`
  /// toggles playback.
  ///
  /// The nine secondary-colour slots are the catalog's one command with
  /// more than one *chord-dispatched* key, so these are the only sites
  /// that name the chord alongside the command.
  func applyPaletteBindings(
    model: EditingSession,
    presentPaletteSheet: @escaping @MainActor @Sendable () -> Void = {},
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.editPalette) {
        presentPaletteSheet()
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("1")) {
        model.dispatch(.setSecondaryColor(1))
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("2")) {
        model.dispatch(.setSecondaryColor(2))
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("3")) {
        model.dispatch(.setSecondaryColor(3))
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("4")) {
        model.dispatch(.setSecondaryColor(4))
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("5")) {
        model.dispatch(.setSecondaryColor(5))
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("6")) {
        model.dispatch(.setSecondaryColor(6))
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("7")) {
        model.dispatch(.setSecondaryColor(7))
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("8")) {
        model.dispatch(.setSecondaryColor(8))
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("9")) {
        model.dispatch(.setSecondaryColor(9))
        refresh()
      }
  }

  /// The file-lifecycle chords.
  ///
  /// Every one of these runs the same closure its menu item runs — they
  /// share a `FileMenuActions` — so a shortcut and a menu row can never
  /// drift into two implementations of one verb.
  ///
  /// `Ctrl+S` is `Save` and `Alt+S` is `Save As`. `Alt+S` was already
  /// pointing at the save sheet as a second spelling of the one save
  /// verb, so splitting the pair costs nobody a rebind. `Ctrl+E`
  /// exports — bare `e` is the eraser, but the `Ctrl` spelling was free
  /// — and `Ctrl+O` opens.
  ///
  /// `New` takes `Ctrl+Alt+N` because both obvious spellings are already
  /// spent: `Ctrl+N` inserts a frame and `Alt+N` adds a layer, and
  /// stealing either would break a binding that is already in people's
  /// hands. The terminal parser reports `ESC` followed by `0x0E` as
  /// `[.ctrl, .alt]` + `n`, so this is a chord the input path actually
  /// receives rather than one of the ambiguous families
  /// `docs/KEYBINDINGS.md` warns about.
  func applyFileBindings(
    isResizeSheetPresented: Binding<Bool>,
    fileActions: FileMenuActions,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.newDocument) {
        fileActions.new()
        refresh()
      }
      .keyCommand(.openDocument) {
        fileActions.open()
        refresh()
      }
      .keyCommand(.saveDocument) {
        fileActions.save()
        refresh()
      }
      .keyCommand(.saveDocumentAs) {
        fileActions.saveAs()
        refresh()
      }
      .keyCommand(.exportGIF) {
        fileActions.exportGIF()
        refresh()
      }
      .keyCommand(.resizeCanvas) {
        isResizeSheetPresented.wrappedValue = true
        refresh()
      }
  }

  /// Quit is the third destructive verb, and it shares the guard with
  /// `New` and `Open` rather than owning a second one.
  ///
  /// The `Ctrl+Q` chord itself belongs to the run loop — `GIFEditorApp`
  /// declares it with `.exitOnKeys` — so the catalog lists it as
  /// `.runLoopExitKey` and this modifier only decides what happens when
  /// it fires.
  ///
  /// Quit authorization is read from the lifecycle rather than captured
  /// as a value, because a termination handler is registered once per
  /// resolve and must see the generation the guard armed a moment ago.
  func applyTerminationHandling(
    lifecycle: DocumentLifecycle,
    confirmUnsavedChanges: @escaping @MainActor @Sendable () -> Void,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    onTerminationRequest { request in
      guard lifecycle.session.isDirty, !lifecycle.allowsQuit else {
        return .allow
      }
      // EOF is not cancellable — the input stream is already gone, so
      // there is nobody left to answer a prompt.
      guard request != .inputEnded else {
        return .allow
      }
      confirmUnsavedChanges()
      lifecycle.session.announce("Unsaved changes — save or discard before quitting")
      refresh()
      return .cancel
    }
  }
}

/// Bare-key handling for the focused editor.
///
/// The lookup *is* the binding: a key press becomes a catalog chord,
/// the catalog names the command, and the switch below runs it. There is
/// no branch for a key the catalog has never heard of, so a bare key
/// cannot be bound without also appearing in the `?` overlay and in
/// `docs/KEYBINDINGS.md`.
///
/// The zoom keys claim `-`, `=` and `0` *unmodified*. Their `Alt`-modified
/// spellings are already the frame-delay commands, and bare `1`–`9` are the
/// palette slots, so the digit row stays consistent: bare digits pick colors,
/// `Alt`-digits touch timing, and the two symbols beside them scale the view.
@MainActor
private func handleFocusedEditorKey(
  _ keyPress: KeyPress,
  model: EditingSession,
  viewport: CanvasViewportCommands,
  onionSkin: OnionSkinCommands,
  showKeyboardHelp: @MainActor @Sendable () -> Void
) -> Bool {
  guard
    let chord = EditorKeyChord(keyPress),
    let command = KeyBindingCatalog.focusedCommand(for: chord)
  else {
    return false
  }
  perform(
    command,
    chord: chord,
    model: model,
    viewport: viewport,
    onionSkin: onionSkin,
    showKeyboardHelp: showKeyboardHelp
  )
  return true
}

/// What each bare-key command does.
///
/// Deliberately without a `default`: adding an `EditorCommand` case fails
/// to compile here until someone decides whether it is a focused key with
/// behavior or a chord handled by one of the chains above.
///
/// Every case that moves the cursor also asks the viewport to follow it, so
/// keyboard drawing can never walk off-screen.
@MainActor
private func perform(
  _ command: EditorCommand,
  chord: EditorKeyChord,
  model: EditingSession,
  viewport: CanvasViewportCommands,
  onionSkin: OnionSkinCommands,
  showKeyboardHelp: @MainActor @Sendable () -> Void
) {
  switch command {
  case .selectPen: model.dispatch(.selectTool(.pen))
  case .selectEraser: model.dispatch(.selectTool(.eraser))
  case .selectBucketFill: model.dispatch(.selectTool(.fill))
  case .selectGradient: model.dispatch(.selectTool(.gradient))
  case .selectMarquee: model.dispatch(.selectTool(.marquee))
  case .selectMovePixels: model.dispatch(.selectTool(.select))
  case .selectEyedropper: model.dispatch(.selectTool(.eyedropper))
  case .selectRectangle: model.dispatch(.selectTool(.rectangle))
  case .selectEllipse: model.dispatch(.selectTool(.ellipse))
  case .swapColors: model.dispatch(.swapPrimaryAndSecondary)
  case .decreaseBrushSize: model.dispatch(.decreaseBrushSize)
  case .increaseBrushSize: model.dispatch(.increaseBrushSize)
  case .toggleShapeFill: model.dispatch(.toggleShapeFill)
  case .toggleStrokeMirrorX: model.dispatch(.toggleStrokeMirrorX)
  case .applyTool: model.dispatch(.applyActiveTool)
  case .clearSelection: model.dispatch(.clearSelection)

  // Region rewrites. Each acts on the marquee, or on the whole layer
  // when there is none, and each is a single undo step.
  case .flipHorizontally: model.dispatch(.flipHorizontally)
  case .flipVertically: model.dispatch(.flipVertically)
  case .rotateClockwise: model.dispatch(.rotateClockwise)
  case .rotateCounterClockwise: model.dispatch(.rotateCounterClockwise)
  case .cutSelection: model.dispatch(.cutSelection)

  case .moveCursorLeft:
    model.dispatch(.moveCursor(dx: -1, dy: 0))
    viewport.followCursor()
  case .moveCursorRight:
    model.dispatch(.moveCursor(dx: 1, dy: 0))
    viewport.followCursor()
  case .moveCursorUp:
    model.dispatch(.moveCursor(dx: 0, dy: -1))
    viewport.followCursor()
  case .moveCursorDown:
    model.dispatch(.moveCursor(dx: 0, dy: 1))
    viewport.followCursor()

  case .zoomOut: viewport.zoomOut()
  case .zoomIn: viewport.zoomIn()
  case .fitToWindow: viewport.fitToWindow()

  case .moveFrameEarlier: model.dispatch(.moveCurrentFrame(-1))
  case .moveFrameLater: model.dispatch(.moveCurrentFrame(1))
  case .moveFrameToStart: model.dispatch(.moveFrameToStart)
  case .moveFrameToEnd: model.dispatch(.moveFrameToEnd)

  // Export metadata. None of these three reaches a composited colour, so
  // all three declare `.nothing` at their write site — see
  // `EditingSession.setLoopCount(_:)` and `setCurrentFrameDisposal(_:)`.
  case .cycleFrameDisposal: model.dispatch(.cycleFrameDisposal)
  case .decreaseLoopCount: model.dispatch(.adjustLoopCount(-1))
  case .increaseLoopCount: model.dispatch(.adjustLoopCount(1))
  case .toggleLoopsForever: model.dispatch(.toggleLoopsForever)

  // Display state only. None of these four touch the document, so none of
  // them go through `mutateDocument` and none of them mark it dirty.
  case .toggleOnionSkin: onionSkin.toggle()
  case .cycleOnionSkinSides: onionSkin.cycleSides()
  case .decreaseOnionSkinGhosts: onionSkin.decreaseDepth()
  case .increaseOnionSkinGhosts: onionSkin.increaseDepth()

  case .primaryColorSlot:
    guard let slot = chord.paletteSlot else { return }
    model.dispatch(.setPrimaryColor(slot))

  case .showKeyboardHelp: showKeyboardHelp()

  // Chord-dispatched commands and the run loop's exit key. They reach
  // their action through `keyCommand` / `.exitOnKeys`, never through
  // here, and `KeyBindingCatalog.focusedCommand(for:)` filters them out
  // before this switch sees them.
  case .jumpCursorLeft, .jumpCursorRight, .jumpCursorUp, .jumpCursorDown,
    .panLeft, .panRight, .panUp, .panDown,
    .previousFrame, .nextFrame, .newFrame, .duplicateFrame, .deleteFrame,
    .decreaseFrameDelay, .increaseFrameDelay, .equalizeFrameDelays, .togglePlayback,
    .newLayer, .selectLayerBelow, .selectLayerAbove, .toggleLayerVisibility, .deleteLayer,
    .copySelection, .paste, .undo, .redo,
    .secondaryColorSlot, .editPalette,
    .newDocument, .openDocument, .saveDocument, .saveDocumentAs, .exportGIF,
    .resizeCanvas, .quit:
    return
  }
}

extension EditorKeyChord {
  /// The palette slot a digit chord names, for the two commands that
  /// bind a run of digits rather than a single key.
  var paletteSlot: UInt8? {
    guard
      case .character(let character) = key,
      let value = character.wholeNumberValue,
      (1...9).contains(value)
    else {
      return nil
    }
    return UInt8(value)
  }
}
