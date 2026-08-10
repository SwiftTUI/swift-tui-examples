/// The single source of truth for every key the editor answers to.
///
/// Three consumers read this table and nothing else: the binding sites in
/// `EditorKeyBindings.swift` (which take their key, modifiers and label
/// from it), the `?` overlay in `KeyBindingHelpView.swift`, and the
/// generator behind `docs/KEYBINDINGS.md`. A binding that is not in here
/// cannot reach either of the last two, which is the whole point — a
/// hand-maintained help screen and a hand-maintained doc are two more
/// places to forget.
///
/// This file deliberately imports nothing. The chord vocabulary is the
/// editor's own rather than SwiftTUI's `KeyEvent` / `EventModifiers` so
/// that the catalog and its Markdown renderer compile standalone, which
/// is what lets `Scripts/generate-keybindings-doc.sh` emit the doc with
/// one `swiftc` invocation instead of booting a terminal app. The bridge
/// to SwiftTUI's types lives in `KeyBindingBridge.swift`, and a test
/// walks every chord across it.

// MARK: - Chord vocabulary

/// A key identity, in the subset the editor actually binds.
///
/// Narrower than SwiftTUI's `KeyEvent` on purpose: the cases that exist
/// here are the ones the editor has a binding for, so a typo names a
/// case that does not compile rather than a key nothing will ever send.
enum EditorKey: Hashable, Sendable {
  case character(Character)
  case space
  case `return`
  case escape
  case arrowLeft
  case arrowRight
  case arrowUp
  case arrowDown

  /// How the key prints in the overlay and the generated doc.
  var display: String {
    switch self {
    case .character(let character): String(character)
    case .space: "Space"
    case .return: "Enter"
    case .escape: "Esc"
    case .arrowLeft: "←"
    case .arrowRight: "→"
    case .arrowUp: "↑"
    case .arrowDown: "↓"
    }
  }
}

/// Modifier flags, mirroring SwiftTUI's `EventModifiers` without
/// depending on it.
struct EditorKeyModifiers: OptionSet, Hashable, Sendable {
  let rawValue: UInt8

  init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  static let shift = Self(rawValue: 1 << 0)
  static let alt = Self(rawValue: 1 << 1)
  static let ctrl = Self(rawValue: 1 << 2)

  /// Printed leading-first, so a two-modifier chord always reads
  /// `Ctrl+Alt+N` and never `Alt+Ctrl+N`.
  var displayPrefix: String {
    var parts: [String] = []
    if contains(.ctrl) { parts.append("Ctrl") }
    if contains(.alt) { parts.append("Alt") }
    if contains(.shift) { parts.append("Shift") }
    guard !parts.isEmpty else { return "" }
    return parts.joined(separator: "+") + "+"
  }
}

/// One key plus its modifiers — what a terminal delivers and what the
/// editor matches against.
struct EditorKeyChord: Hashable, Sendable {
  let key: EditorKey
  let modifiers: EditorKeyModifiers

  init(_ key: EditorKey, modifiers: EditorKeyModifiers = []) {
    self.key = key
    self.modifiers = modifiers
  }

  /// A chord with no modifiers at all. These are the ones
  /// `handleFocusedEditorKey` dispatches; SwiftTUI drops modifier-less
  /// `keyCommand` registrations, so bare keys can only be served that
  /// way.
  var isBare: Bool { modifiers.isEmpty }

  /// Conventional shortcut notation: a modified letter prints
  /// capitalized (`Ctrl+S`) even though the terminal delivers it
  /// lowercase, while a bare letter stays as typed (`p`, `h`) because
  /// that is literally the key to press.
  var display: String {
    guard
      !modifiers.isEmpty,
      case .character(let character) = key,
      character.isLetter
    else {
      return modifiers.displayPrefix + key.display
    }
    return modifiers.displayPrefix + character.uppercased()
  }

  // Spelling helpers, so a binding site reads like the doc row it
  // produces.
  static func bare(_ character: Character) -> Self { Self(.character(character)) }
  static func ctrl(_ character: Character) -> Self {
    Self(.character(character), modifiers: .ctrl)
  }
  static func alt(_ character: Character) -> Self {
    Self(.character(character), modifiers: .alt)
  }
}

// MARK: - Sections

/// A heading in the overlay and in `docs/KEYBINDINGS.md`, with the prose
/// that belongs under it.
///
/// The notes live here rather than in the Markdown file because the
/// Markdown file is generated: anything a human writes there is
/// overwritten on the next run.
enum KeyBindingSection: String, CaseIterable, Sendable {
  case tools
  case transform
  case cursor
  case viewport
  case frames
  case onionSkin
  case layers
  case clipboard
  case history
  case palette
  case file
  case help

  var title: String {
    switch self {
    case .tools: "Tools"
    case .transform: "Transform"
    case .cursor: "Cursor"
    case .viewport: "Zoom / Pan"
    case .frames: "Frames / Timeline"
    case .onionSkin: "Onion Skin"
    case .layers: "Layers"
    case .clipboard: "Clipboard"
    case .history: "History"
    case .palette: "Palette / Colors"
    case .file: "File / App"
    case .help: "Help"
    }
  }

  /// Prose emitted under the section's table in the generated doc. The
  /// overlay shows tables only — a terminal sheet is a reference card,
  /// not a manual.
  var notes: [String] {
    switch self {
    case .tools:
      [
        """
        The canvas supports direct pointer editing. Drag with **Pen** or \
        **Eraser** to paint a connected stroke. Drag with **Marquee** to select a \
        rectangle. Drag with **Gradient**, **Rectangle**, or **Ellipse** to span \
        the drag endpoints. Click with **Fill** or **Eyedropper** to select one \
        pixel. Some hosts report pointer locations in terminal pixels. These \
        hosts can address each half of a cell independently. A cell-only host \
        uses the top half of each terminal cell.
        """,
        """
        **Rectangle**, **Ellipse**, and **Gradient** set an anchor on the first \
        press. They paint on the second press. Both drag directions span the \
        same cells. The brush size sets the outline thickness. Press `f` to fill \
        the shape. An active marquee clips shapes and fills.
        """,
        """
        **Mirror-X** modifies drawing and is not a tool. When it is on, each pen \
        and eraser stroke is painted twice. The second stroke is reflected \
        across the vertical center line of the canvas. The canvas sets the \
        reflection axis. A marquee does not move this axis.
        """,
      ]
    case .transform:
      [
        """
        Flip, rotate, cut, and `Ctrl+C` use the same selection rule. If a \
        marquee exists, they use its selection. Otherwise, they use the complete \
        current layer.
        """,
        """
        A quarter turn maps a `w × h` selection to an `h × w` selection. The \
        canvas size does not change. The marquee moves with its pixels, so the \
        pixels are not clipped to the old selection. The rotated region keeps \
        its old top-left corner. If the region crosses an edge, the app moves it \
        back onto the canvas. This corner-pinned rule prevents half-cell rounding \
        drift for odd dimensions. Four turns restore the region. Clockwise and \
        counterclockwise turns are inverse operations. If a rotated selection \
        cannot fit, the app rotates it around the center and clips the edges. A \
        non-square canvas uses this path for a whole-canvas turn. Undo restores \
        clipped pixels.
        """,
      ]
    case .viewport:
      [
        """
        Each cursor move keeps the cursor inside the visible rectangle. Thus, \
        keyboard drawing cannot move off-screen. Panning does not follow the \
        cursor. It lets you view a different part of the canvas.
        """,
        """
        Bare digits select colors. `Alt`-digits change frame timing. The two \
        adjacent symbols change the view scale.
        """,
      ]
    case .palette:
      [
        """
        The palette editor changes slot colors in hex or R/G/B. It adds, \
        removes, sorts, and compacts slots. It also imports Lospec `.hex` and \
        GIMP `.gpl` files. Remove, sort, compact, and import operations renumber \
        the slots. Each operation is one undoable edit. The edit also renumbers \
        the artwork, so its colors do not change. Slot 0 is the transparency \
        sentinel and never moves.
        """
      ]
    case .file:
      [
        """
        `Save` writes a layered `.halfcell` project to its current path. If the \
        document came from a GIF, `Save` opens `Save As…`. Thus, `Save` cannot \
        flatten a layered document without notice. `Export GIF…` flattens the \
        document and leaves it unsaved. `New…`, `Open…`, and quit use the same \
        unsaved-changes guard.
        """,
        """
        The New and Resize interfaces limit each axis to 256 pixels. The project \
        format has no such limit. The loader opens GIFs with other dimensions.
        """,
      ]
    case .onionSkin:
      [
        """
        Onion skin shows neighboring frames *under* the current frame. It does \
        not change the current frame. Ghosts are visible only through \
        transparent pixels. Earlier frames have a cool tint, and later frames \
        have a warm tint. More distant ghosts are fainter. Thus, the terminal \
        palette shows direction and distance.
        """,
        """
        Ghosting does not wrap. The first frame has no previous ghost. The last \
        frame has no next ghost. This rule prevents a distant end frame from \
        looking like an adjacent frame.
        """,
        """
        Onion skin is display only. It does not affect the eyedropper, \
        exported GIF, or saved project. Toggling it does not mark the document \
        as changed. A change to the ghost count or side turns onion skin on.
        """,
      ]
    case .frames:
      [
        """
        The `,` / `.` key pair controls the timeline. With `Alt`, the keys move \
        the selection between frames. The shifted `<` / `>` keys move the \
        current frame by one position. The bare keys move it to an end.
        """,
        """
        The loop count belongs to the exported file, not the editor preview. It \
        sets the GIF `NETSCAPE2.0` block. The format uses zero for "forever". \
        Thus, `)`, the shifted `0`, toggles this value. The readout shows the \
        word instead of the digit.
        """,
      ]
    case .cursor, .layers, .clipboard, .history, .help:
      []
    }
  }
}

// MARK: - Dispatch

/// Which mechanism actually delivers a command's chord.
enum KeyBindingDispatch: Sendable {
  /// Served by `handleFocusedEditorKey`, off the focused view's
  /// `onKeyPress(.any)`. SwiftTUI reserves modifier-less keys for its own
  /// dispatch and silently drops bare `keyCommand` registrations, so this
  /// is the only route a bare key has.
  case focusedKey
  /// Registered as a `keyCommand` on the editor panel's action scope.
  case keyCommand
  /// Owned by the app's run loop, not by any view — `GIFEditorApp`
  /// declares it with `.exitOnKeys`. Listed so the reference is complete;
  /// the completeness test skips it, because `GIFEditorUI` has no way to
  /// install or observe it.
  case runLoopExitKey
}

// MARK: - Commands

/// Every command the editor binds a key to.
///
/// `CaseIterable` plus an exhaustive `entry` switch is the compile-time
/// half of the guarantee: a new case does not build until it has a
/// section, a chord and a label, and `EditorCommand.perform` does not
/// build until a focused-key case has behavior.
enum EditorCommand: String, CaseIterable, Hashable, Sendable {
  // Tools
  case selectPen
  case selectEraser
  case selectBucketFill
  case selectGradient
  case selectMarquee
  case selectMovePixels
  case selectEyedropper
  case selectRectangle
  case selectEllipse
  case swapColors
  case decreaseBrushSize
  case increaseBrushSize
  case toggleShapeFill
  case toggleStrokeMirrorX
  case applyTool
  case clearSelection

  // Transform
  case flipHorizontally
  case flipVertically
  case rotateClockwise
  case rotateCounterClockwise

  // Cursor
  case moveCursorLeft
  case moveCursorRight
  case moveCursorUp
  case moveCursorDown
  case jumpCursorLeft
  case jumpCursorRight
  case jumpCursorUp
  case jumpCursorDown

  // Zoom / Pan
  case zoomOut
  case zoomIn
  case fitToWindow
  case panLeft
  case panRight
  case panUp
  case panDown

  // Frames / Timeline
  case previousFrame
  case nextFrame
  case newFrame
  case duplicateFrame
  case deleteFrame
  case moveFrameEarlier
  case moveFrameLater
  case moveFrameToStart
  case moveFrameToEnd
  case decreaseFrameDelay
  case increaseFrameDelay
  case equalizeFrameDelays
  case cycleFrameDisposal
  case decreaseLoopCount
  case increaseLoopCount
  case toggleLoopsForever
  case togglePlayback

  // Onion skin
  case toggleOnionSkin
  case cycleOnionSkinSides
  case decreaseOnionSkinGhosts
  case increaseOnionSkinGhosts

  // Layers
  case newLayer
  case selectLayerBelow
  case selectLayerAbove
  case toggleLayerVisibility
  case deleteLayer

  // Clipboard
  case cutSelection
  case copySelection
  case paste

  // History
  case undo
  case redo

  // Palette / Colors
  case primaryColorSlot
  case secondaryColorSlot
  case editPalette

  // File / App
  case newDocument
  case openDocument
  case saveDocument
  case saveDocumentAs
  case exportGIF
  case resizeCanvas
  case quit

  // Help
  case showKeyboardHelp
}

/// One row of the catalog: what a command is called, where it belongs,
/// and every chord that reaches it.
struct KeyBindingEntry: Sendable {
  let command: EditorCommand
  let section: KeyBindingSection
  /// Every chord bound to this command. More than one when a command has
  /// synonyms (`←` and `h`) or spans a run of keys (`1`…`9`).
  let chords: [EditorKeyChord]
  /// Replaces the derived `chords`-joined spelling when the derived one
  /// would be a wall of alternatives. Only the two digit runs use it.
  let displayOverride: String?
  let label: String
  let dispatch: KeyBindingDispatch

  init(
    _ command: EditorCommand,
    _ section: KeyBindingSection,
    _ chords: [EditorKeyChord],
    _ label: String,
    dispatch: KeyBindingDispatch,
    displayOverride: String? = nil
  ) {
    self.command = command
    self.section = section
    self.chords = chords
    self.displayOverride = displayOverride
    self.label = label
    self.dispatch = dispatch
  }

  /// The shortcut column, in the overlay and in the doc.
  var display: String {
    displayOverride ?? chords.map(\.display).joined(separator: " / ")
  }

  /// The single chord this command is registered under, for the binding
  /// sites that install exactly one.
  var soleChord: EditorKeyChord? {
    chords.count == 1 ? chords[0] : nil
  }
}

// MARK: - The catalog

enum KeyBindingCatalog {
  /// Every binding, in the order the doc and the overlay present them.
  ///
  /// Grouped by section and ordered within a section by usefulness
  /// rather than by key, because this list *is* the reference card.
  static let entries: [KeyBindingEntry] = EditorCommand.allCases.map(entry(for:))

  /// The one place a command's section, chords and label are written.
  ///
  /// Exhaustive by construction: adding an `EditorCommand` case without
  /// a row here is a compile error, so a binding cannot exist without a
  /// doc row and a help row.
  static func entry(for command: EditorCommand) -> KeyBindingEntry {
    switch command {
    // MARK: Tools
    case .selectPen:
      KeyBindingEntry(
        command, .tools, [.bare("p")], "Pen — paint the primary color", dispatch: .focusedKey)
    case .selectEraser:
      KeyBindingEntry(
        command, .tools, [.bare("e")], "Eraser — clear to transparent", dispatch: .focusedKey)
    case .selectBucketFill:
      KeyBindingEntry(
        command, .tools, [.bare("b")], "Bucket fill (4-connected)", dispatch: .focusedKey)
    case .selectGradient:
      KeyBindingEntry(
        command, .tools, [.bare("g")], "Gradient between primary and secondary",
        dispatch: .focusedKey)
    case .selectMarquee:
      KeyBindingEntry(
        command, .tools, [.bare("m")], "Marquee — rectangular selection", dispatch: .focusedKey)
    case .selectMovePixels:
      KeyBindingEntry(
        command, .tools, [.bare("v")], "Select / move pixels", dispatch: .focusedKey)
    case .selectEyedropper:
      KeyBindingEntry(
        command, .tools, [.bare("i")], "Eyedropper — pick the color under the cursor",
        dispatch: .focusedKey)
    // The shape tools take the two free lowercase letters that name them
    // — `r` for rectangle, `c` for circle, since `e` is already the
    // eraser. Both are bare, like every other tool key, which also means
    // neither costs the editor root a `keyCommand` layer.
    case .selectRectangle:
      KeyBindingEntry(
        command, .tools, [.bare("r")], "Rectangle — span it from two corners",
        dispatch: .focusedKey)
    case .selectEllipse:
      KeyBindingEntry(
        command, .tools, [.bare("c")], "Ellipse — inscribed in the same two corners",
        dispatch: .focusedKey)
    case .swapColors:
      KeyBindingEntry(
        command, .tools, [.bare("x")], "Swap primary and secondary color", dispatch: .focusedKey)
    case .decreaseBrushSize:
      KeyBindingEntry(
        command, .tools, [.bare("[")], "Decrease brush size", dispatch: .focusedKey)
    case .increaseBrushSize:
      KeyBindingEntry(
        command, .tools, [.bare("]")], "Increase brush size", dispatch: .focusedKey)
    case .toggleShapeFill:
      KeyBindingEntry(
        command, .tools, [.bare("f")], "Filled shapes on / off", dispatch: .focusedKey)
    case .toggleStrokeMirrorX:
      KeyBindingEntry(
        command, .tools, [.bare("s")], "Mirror-X symmetry for pen and eraser strokes",
        dispatch: .focusedKey)
    case .applyTool:
      KeyBindingEntry(
        command, .tools, [EditorKeyChord(.space), EditorKeyChord(.return)],
        "Apply the current tool at the cursor (complete a marquee)", dispatch: .focusedKey)
    case .clearSelection:
      KeyBindingEntry(
        command, .tools, [EditorKeyChord(.escape)], "Clear selection", dispatch: .focusedKey)

    // MARK: Transform
    //
    // Shifted letters, and shifted on purpose: these four rewrite a
    // region of pixels in one press, which is a heavier act than picking
    // a tool, and the shift is what keeps a mistyped `h` from rotating
    // the artwork. `H` and `V` name the axis they mirror about; `R` and
    // `L` are rotate-right and rotate-left, which is also why the
    // clockwise one is not `C` — that is the ellipse.
    case .flipHorizontally:
      KeyBindingEntry(
        command, .transform, [.bare("H")], "Flip the selection (or the layer) left ↔ right",
        dispatch: .focusedKey)
    case .flipVertically:
      KeyBindingEntry(
        command, .transform, [.bare("V")], "Flip the selection (or the layer) top ↔ bottom",
        dispatch: .focusedKey)
    case .rotateClockwise:
      KeyBindingEntry(
        command, .transform, [.bare("R")], "Rotate a quarter turn clockwise",
        dispatch: .focusedKey)
    case .rotateCounterClockwise:
      KeyBindingEntry(
        command, .transform, [.bare("L")], "Rotate a quarter turn counter-clockwise",
        dispatch: .focusedKey)

    // MARK: Cursor
    case .moveCursorLeft:
      KeyBindingEntry(
        command, .cursor, [EditorKeyChord(.arrowLeft), .bare("h")], "Move cursor left 1 pixel",
        dispatch: .focusedKey)
    case .moveCursorRight:
      KeyBindingEntry(
        command, .cursor, [EditorKeyChord(.arrowRight), .bare("l")], "Move cursor right 1 pixel",
        dispatch: .focusedKey)
    case .moveCursorUp:
      KeyBindingEntry(
        command, .cursor, [EditorKeyChord(.arrowUp), .bare("k")], "Move cursor up 1 pixel",
        dispatch: .focusedKey)
    case .moveCursorDown:
      KeyBindingEntry(
        command, .cursor, [EditorKeyChord(.arrowDown), .bare("j")], "Move cursor down 1 pixel",
        dispatch: .focusedKey)
    case .jumpCursorLeft:
      KeyBindingEntry(
        command, .cursor, [EditorKeyChord(.arrowLeft, modifiers: .ctrl)],
        "Jump cursor left 8 pixels", dispatch: .keyCommand)
    case .jumpCursorRight:
      KeyBindingEntry(
        command, .cursor, [EditorKeyChord(.arrowRight, modifiers: .ctrl)],
        "Jump cursor right 8 pixels", dispatch: .keyCommand)
    case .jumpCursorUp:
      KeyBindingEntry(
        command, .cursor, [EditorKeyChord(.arrowUp, modifiers: .ctrl)],
        "Jump cursor up 8 pixels", dispatch: .keyCommand)
    case .jumpCursorDown:
      KeyBindingEntry(
        command, .cursor, [EditorKeyChord(.arrowDown, modifiers: .ctrl)],
        "Jump cursor down 8 pixels", dispatch: .keyCommand)

    // MARK: Zoom / Pan
    case .zoomOut:
      KeyBindingEntry(
        command, .viewport, [.bare("-")], "Zoom out one step", dispatch: .focusedKey)
    case .zoomIn:
      KeyBindingEntry(
        command, .viewport, [.bare("=")], "Zoom in one step (1× / 2× / 4×)",
        dispatch: .focusedKey)
    case .fitToWindow:
      KeyBindingEntry(
        command, .viewport, [.bare("0")], "Fit the whole canvas to the window",
        dispatch: .focusedKey)
    case .panLeft:
      KeyBindingEntry(
        command, .viewport, [EditorKeyChord(.arrowLeft, modifiers: .alt)],
        "Pan the viewport left half a screen", dispatch: .keyCommand)
    case .panRight:
      KeyBindingEntry(
        command, .viewport, [EditorKeyChord(.arrowRight, modifiers: .alt)],
        "Pan the viewport right half a screen", dispatch: .keyCommand)
    case .panUp:
      KeyBindingEntry(
        command, .viewport, [EditorKeyChord(.arrowUp, modifiers: .alt)],
        "Pan the viewport up half a screen", dispatch: .keyCommand)
    case .panDown:
      KeyBindingEntry(
        command, .viewport, [EditorKeyChord(.arrowDown, modifiers: .alt)],
        "Pan the viewport down half a screen", dispatch: .keyCommand)

    // MARK: Frames / Timeline
    case .previousFrame:
      KeyBindingEntry(command, .frames, [.alt(",")], "Previous frame", dispatch: .keyCommand)
    case .nextFrame:
      KeyBindingEntry(command, .frames, [.alt(".")], "Next frame", dispatch: .keyCommand)
    case .newFrame:
      KeyBindingEntry(
        command, .frames, [.ctrl("n")], "New blank frame after current", dispatch: .keyCommand)
    case .duplicateFrame:
      KeyBindingEntry(
        command, .frames, [.ctrl("d")], "Duplicate current frame after current",
        dispatch: .keyCommand)
    case .deleteFrame:
      KeyBindingEntry(
        command, .frames, [.alt("d")], "Delete current frame", dispatch: .keyCommand)
    case .moveFrameEarlier:
      KeyBindingEntry(
        command, .frames, [.bare("<")], "Move current frame one position earlier",
        dispatch: .focusedKey)
    case .moveFrameLater:
      KeyBindingEntry(
        command, .frames, [.bare(">")], "Move current frame one position later",
        dispatch: .focusedKey)
    case .moveFrameToStart:
      KeyBindingEntry(
        command, .frames, [.bare(",")], "Move current frame to the start of the timeline",
        dispatch: .focusedKey)
    case .moveFrameToEnd:
      KeyBindingEntry(
        command, .frames, [.bare(".")], "Move current frame to the end of the timeline",
        dispatch: .focusedKey)
    case .decreaseFrameDelay:
      KeyBindingEntry(
        command, .frames, [.alt("-")], "Decrease current frame delay (10 cs)",
        dispatch: .keyCommand)
    case .increaseFrameDelay:
      KeyBindingEntry(
        command, .frames, [.alt("=")], "Increase current frame delay (10 cs)",
        dispatch: .keyCommand)
    case .equalizeFrameDelays:
      KeyBindingEntry(
        command, .frames, [.alt("0")], "Set every frame delay to the current one",
        dispatch: .keyCommand)
    case .cycleFrameDisposal:
      KeyBindingEntry(
        command, .frames, [.bare("d")],
        "Cycle the current frame's disposal (background / keep / previous / unspecified)",
        dispatch: .focusedKey)
    // The shifted `-` / `=` pair, one row over from the delay keys they
    // rhyme with: `Alt`-modified steps a frame's delay, shifted steps the
    // whole document's loop count.
    case .decreaseLoopCount:
      KeyBindingEntry(
        command, .frames, [.bare("_")], "One fewer play of the exported GIF",
        dispatch: .focusedKey)
    case .increaseLoopCount:
      KeyBindingEntry(
        command, .frames, [.bare("+")], "One more play of the exported GIF",
        dispatch: .focusedKey)
    case .toggleLoopsForever:
      KeyBindingEntry(
        command, .frames, [.bare(")")], "Toggle looping forever (the format's zero)",
        dispatch: .focusedKey)
    case .togglePlayback:
      KeyBindingEntry(
        command, .frames, [.alt("p")], "Toggle playback", dispatch: .keyCommand)

    // MARK: Onion skin
    //
    // All four are bare keys, which is a depth decision as much as an
    // ergonomic one: bare keys ride the `onKeyPress(.any)` handler the
    // editor root already wears, so a whole feature's worth of bindings
    // adds *zero* nested `ModifiedContent` layers to a root chain that is
    // already at its resolve-stack budget. `o` is the obvious letter and
    // was free — `Ctrl+O` opens a document, which is a different verb —
    // and `{` / `}` are the shifted siblings of the `[` / `]` brush-size
    // pair, so the bracket family means "count" throughout.
    case .toggleOnionSkin:
      KeyBindingEntry(
        command, .onionSkin, [.bare("o")], "Toggle onion skin", dispatch: .focusedKey)
    case .cycleOnionSkinSides:
      KeyBindingEntry(
        command, .onionSkin, [.bare("O")],
        "Cycle which neighbors are ghosted (both / previous / next)",
        dispatch: .focusedKey)
    case .decreaseOnionSkinGhosts:
      KeyBindingEntry(
        command, .onionSkin, [.bare("{")], "One fewer ghost frame per side",
        dispatch: .focusedKey)
    case .increaseOnionSkinGhosts:
      KeyBindingEntry(
        command, .onionSkin, [.bare("}")], "One more ghost frame per side (max 3)",
        dispatch: .focusedKey)

    // MARK: Layers
    case .newLayer:
      KeyBindingEntry(
        command, .layers, [.alt("n")], "New empty layer above current", dispatch: .keyCommand)
    case .selectLayerBelow:
      KeyBindingEntry(
        command, .layers, [.alt("j")], "Select layer below", dispatch: .keyCommand)
    case .selectLayerAbove:
      KeyBindingEntry(
        command, .layers, [.alt("k")], "Select layer above", dispatch: .keyCommand)
    case .toggleLayerVisibility:
      KeyBindingEntry(
        command, .layers, [.alt("h")], "Toggle current layer visibility", dispatch: .keyCommand)
    case .deleteLayer:
      KeyBindingEntry(
        command, .layers, [.alt("x")], "Delete current layer", dispatch: .keyCommand)

    // MARK: Clipboard
    //
    // `X` rather than `Ctrl+X`: the shifted letter is free, it costs the
    // editor root no `keyCommand` layer, and it puts cut in the same
    // shifted family as the transforms it belongs with — bare `x` is
    // still the colour swap.
    case .cutSelection:
      KeyBindingEntry(
        command, .clipboard, [.bare("X")], "Cut selection (or the whole layer if none)",
        dispatch: .focusedKey)
    case .copySelection:
      KeyBindingEntry(
        command, .clipboard, [.ctrl("c")], "Copy selection (or the whole layer if none)",
        dispatch: .keyCommand)
    case .paste:
      KeyBindingEntry(
        command, .clipboard, [.ctrl("v")], "Paste at cursor", dispatch: .keyCommand)

    // MARK: History
    case .undo:
      KeyBindingEntry(
        command, .history, [.ctrl("z")], "Undo last document edit", dispatch: .keyCommand)
    case .redo:
      KeyBindingEntry(
        command, .history, [.ctrl("y")], "Redo last undone edit", dispatch: .keyCommand)

    // MARK: Palette / Colors
    case .primaryColorSlot:
      KeyBindingEntry(
        command, .palette, Self.digitChords(modifiers: []),
        "Pick palette slot 1–9 as primary", dispatch: .focusedKey, displayOverride: "1…9")
    case .secondaryColorSlot:
      KeyBindingEntry(
        command, .palette, Self.digitChords(modifiers: .alt),
        "Pick palette slot 1–9 as secondary", dispatch: .keyCommand,
        displayOverride: "Alt+1…Alt+9")
    case .editPalette:
      KeyBindingEntry(
        command, .palette, [.ctrl("p")], "Open the palette editor (Edit → Palette…)",
        dispatch: .keyCommand)

    // MARK: File / App
    case .newDocument:
      KeyBindingEntry(
        command, .file, [EditorKeyChord(.character("n"), modifiers: [.ctrl, .alt])],
        "New… — start a fresh document at a chosen size", dispatch: .keyCommand)
    case .openDocument:
      KeyBindingEntry(
        command, .file, [.ctrl("o")], "Open… — load a GIF or a `.halfcell` project",
        dispatch: .keyCommand)
    case .saveDocument:
      KeyBindingEntry(
        command, .file, [.ctrl("s")], "Save the layered project", dispatch: .keyCommand)
    case .saveDocumentAs:
      KeyBindingEntry(
        command, .file, [.alt("s")], "Save As… — always prompts for a project path",
        dispatch: .keyCommand)
    case .exportGIF:
      KeyBindingEntry(
        command, .file, [.ctrl("e")], "Export GIF… — write a flattened copy",
        dispatch: .keyCommand)
    case .resizeCanvas:
      KeyBindingEntry(
        command, .file, [.ctrl("r")], "Resize canvas… (presets 16…256, or any width × height)",
        dispatch: .keyCommand)
    case .quit:
      KeyBindingEntry(
        command, .file, [.ctrl("q")], "Quit — prompts when there are unsaved changes",
        dispatch: .runLoopExitKey)

    // MARK: Help
    case .showKeyboardHelp:
      KeyBindingEntry(
        command, .help, [.bare("?")], "Show this keyboard reference", dispatch: .focusedKey)
    }
  }

  /// `1`…`9` under `modifiers`. Slot 0 is the transparency sentinel and
  /// is never bound.
  private static func digitChords(modifiers: EditorKeyModifiers) -> [EditorKeyChord] {
    (1...9).map { EditorKeyChord(.character(Character("\($0)")), modifiers: modifiers) }
  }

  // MARK: - Lookups

  /// Entries in `section`, in catalog order.
  static func entries(in section: KeyBindingSection) -> [KeyBindingEntry] {
    entries.filter { $0.section == section }
  }

  /// Sections that have at least one entry, in declaration order.
  static var populatedSections: [KeyBindingSection] {
    KeyBindingSection.allCases.filter { !entries(in: $0).isEmpty }
  }

  /// Every chord the catalog claims, paired with the command it runs.
  ///
  /// Built once. A duplicate chord would silently lose a binding, so the
  /// builder traps on one rather than picking a winner — and a test
  /// asserts the same thing without relying on the trap firing.
  static let commandsByChord: [EditorKeyChord: EditorCommand] = {
    var table: [EditorKeyChord: EditorCommand] = [:]
    for entry in entries {
      for chord in entry.chords {
        precondition(
          table[chord] == nil,
          "\(chord.display) is claimed by both \(table[chord]!.rawValue) and \(entry.command.rawValue)"
        )
        table[chord] = entry.command
      }
    }
    return table
  }()

  /// The command a bare (modifier-less) key runs, if any.
  ///
  /// `handleFocusedEditorKey` dispatches through this and nothing else,
  /// which is why a bare key cannot be bound without a catalog row: the
  /// lookup is the binding.
  static func focusedCommand(for chord: EditorKeyChord) -> EditorCommand? {
    guard chord.isBare, let command = commandsByChord[chord] else { return nil }
    guard entry(for: command).dispatch == .focusedKey else { return nil }
    return command
  }
}
