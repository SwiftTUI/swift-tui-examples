import GIFEditorCore
import SwiftTUI

extension View {
  func applyFocusedEditorBindings(
    model: EditorViewModel,
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
    model: EditorViewModel,
    viewport: CanvasViewportCommands = .inert,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.jumpCursorLeft) {
        model.moveCursor(dx: -8, dy: 0)
        viewport.followCursor()
        refresh()
      }
      .keyCommand(.jumpCursorRight) {
        model.moveCursor(dx: 8, dy: 0)
        viewport.followCursor()
        refresh()
      }
      .keyCommand(.jumpCursorUp) {
        model.moveCursor(dx: 0, dy: -8)
        viewport.followCursor()
        refresh()
      }
      .keyCommand(.jumpCursorDown) {
        model.moveCursor(dx: 0, dy: 8)
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
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.previousFrame) {
        model.previousFrame()
        refresh()
      }
      .keyCommand(.nextFrame) {
        model.nextFrame()
        refresh()
      }
      .keyCommand(.newFrame) {
        model.insertBlankFrameAfterCurrent()
        refresh()
      }
      .keyCommand(.duplicateFrame) {
        model.duplicateCurrentFrame()
        refresh()
      }
      .keyCommand(.deleteFrame) {
        model.deleteCurrentFrame()
        refresh()
      }
      .keyCommand(.decreaseFrameDelay) {
        model.adjustCurrentFrameDelay(by: -10)
        refresh()
      }
      .keyCommand(.increaseFrameDelay) {
        model.adjustCurrentFrameDelay(by: 10)
        refresh()
      }
      .keyCommand(.equalizeFrameDelays) {
        model.setAllFrameDelaysToCurrent()
        refresh()
      }
      .keyCommand(.togglePlayback) {
        model.togglePlayback()
        refresh()
      }
  }

  func applyLayerBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.newLayer) {
        model.addLayer()
        refresh()
      }
      .keyCommand(.selectLayerBelow) {
        model.selectLayerBelow()
        refresh()
      }
      .keyCommand(.selectLayerAbove) {
        model.selectLayerAbove()
        refresh()
      }
      .keyCommand(.toggleLayerVisibility) {
        model.toggleCurrentLayerVisibility()
        refresh()
      }
      .keyCommand(.deleteLayer) {
        model.deleteCurrentLayer()
        refresh()
      }
  }

  func applyClipboardBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.copySelection) {
        model.copySelection()
        refresh()
      }
      .keyCommand(.paste) {
        model.paste()
        refresh()
      }
  }

  func applyHistoryBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.undo) {
        model.undo()
        refresh()
      }
      .keyCommand(.redo) {
        model.redo()
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
    model: EditorViewModel,
    presentPaletteSheet: @escaping @MainActor @Sendable () -> Void = {},
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(.editPalette) {
        presentPaletteSheet()
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("1")) {
        model.setSecondaryColor(1)
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("2")) {
        model.setSecondaryColor(2)
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("3")) {
        model.setSecondaryColor(3)
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("4")) {
        model.setSecondaryColor(4)
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("5")) {
        model.setSecondaryColor(5)
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("6")) {
        model.setSecondaryColor(6)
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("7")) {
        model.setSecondaryColor(7)
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("8")) {
        model.setSecondaryColor(8)
        refresh()
      }
      .keyCommand(.secondaryColorSlot, chord: .alt("9")) {
        model.setSecondaryColor(9)
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
  /// `allowsQuitWithUnsavedChanges` is read off the model — a reference
  /// type — rather than captured as a value, because a termination
  /// handler is registered once per resolve and must see the flag the
  /// guard set a moment ago, not the one that was true when this
  /// modifier was last built.
  func applyTerminationHandling(
    model: EditorViewModel,
    confirmUnsavedChanges: @escaping @MainActor @Sendable () -> Void,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    onTerminationRequest { request in
      guard model.isDirty, !model.allowsQuitWithUnsavedChanges else {
        return .allow
      }
      // EOF is not cancellable — the input stream is already gone, so
      // there is nobody left to answer a prompt.
      guard request != .inputEnded else {
        return .allow
      }
      confirmUnsavedChanges()
      model.statusMessage = "Unsaved changes — save or discard before quitting"
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
  model: EditorViewModel,
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
  model: EditorViewModel,
  viewport: CanvasViewportCommands,
  onionSkin: OnionSkinCommands,
  showKeyboardHelp: @MainActor @Sendable () -> Void
) {
  switch command {
  case .selectPen: model.selectTool(.pen)
  case .selectEraser: model.selectTool(.eraser)
  case .selectBucketFill: model.selectTool(.fill)
  case .selectGradient: model.selectTool(.gradient)
  case .selectMarquee: model.selectTool(.marquee)
  case .selectMovePixels: model.selectTool(.select)
  case .selectEyedropper: model.selectTool(.eyedropper)
  case .selectRectangle: model.selectTool(.rectangle)
  case .selectEllipse: model.selectTool(.ellipse)
  case .swapColors: model.swapPrimaryAndSecondary()
  case .decreaseBrushSize: model.decreaseBrushSize()
  case .increaseBrushSize: model.increaseBrushSize()
  case .toggleShapeFill: model.toggleShapeFill()
  case .toggleStrokeMirrorX: model.toggleStrokeMirrorX()
  case .applyTool: model.applyToolAtCursor()
  case .clearSelection: model.clearSelection()

  // Region rewrites. Each acts on the marquee, or on the whole layer
  // when there is none, and each is a single undo step.
  case .flipHorizontally: model.flipHorizontally()
  case .flipVertically: model.flipVertically()
  case .rotateClockwise: model.rotateClockwise()
  case .rotateCounterClockwise: model.rotateCounterClockwise()
  case .cutSelection: model.cutSelection()

  case .moveCursorLeft:
    model.moveCursor(dx: -1, dy: 0)
    viewport.followCursor()
  case .moveCursorRight:
    model.moveCursor(dx: 1, dy: 0)
    viewport.followCursor()
  case .moveCursorUp:
    model.moveCursor(dx: 0, dy: -1)
    viewport.followCursor()
  case .moveCursorDown:
    model.moveCursor(dx: 0, dy: 1)
    viewport.followCursor()

  case .zoomOut: viewport.zoomOut()
  case .zoomIn: viewport.zoomIn()
  case .fitToWindow: viewport.fitToWindow()

  case .moveFrameEarlier: model.moveCurrentFrame(by: -1)
  case .moveFrameLater: model.moveCurrentFrame(by: 1)
  case .moveFrameToStart: model.moveCurrentFrameToStart()
  case .moveFrameToEnd: model.moveCurrentFrameToEnd()

  // Export metadata. None of these three reaches a composited colour, so
  // all three declare `.nothing` at their write site — see
  // `EditorViewModel.setLoopCount(_:)` and `setCurrentFrameDisposal(_:)`.
  case .cycleFrameDisposal: model.cycleCurrentFrameDisposal()
  case .decreaseLoopCount: model.adjustLoopCount(by: -1)
  case .increaseLoopCount: model.adjustLoopCount(by: 1)
  case .toggleLoopsForever: model.toggleLoopsForever()

  // Display state only. None of these four touch the document, so none of
  // them go through `mutateDocument` and none of them mark it dirty.
  case .toggleOnionSkin: onionSkin.toggle()
  case .cycleOnionSkinSides: onionSkin.cycleSides()
  case .decreaseOnionSkinGhosts: onionSkin.decreaseDepth()
  case .increaseOnionSkinGhosts: onionSkin.increaseDepth()

  case .primaryColorSlot:
    guard let slot = chord.paletteSlot else { return }
    model.setPrimaryColor(slot)

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
