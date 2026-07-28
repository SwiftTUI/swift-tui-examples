import Foundation
import GIFEditorCore
import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor presentation runtime")
struct PresentationRuntimeTests {
  /// A menu trigger changing from `▾` to `▴` proves only that the button
  /// mutated `openMenu`. The user-facing contract is that the dropdown is
  /// painted over the editor on that same click.
  @Test("clicking File opens its dropdown", .timeLimit(.minutes(1)))
  func clickingFileOpensItsDropdown() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.file-menu-click"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .click(CellPoint(x: 3, y: 0)),
        // The arrow is the known regression outcome, so accepting it keeps a
        // failure red instead of waiting forever for the missing dropdown.
        .awaitCondition {
          terminal.latestFrame?.contains("File ▴") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 16, height: 16)),
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    let openedFrame = terminal.latestFrame ?? ""
    #expect(result.exitReason == .inputEnded)
    #expect(openedFrame.contains("File ▴"))
    #expect(openedFrame.contains("New…"))
    #expect(openedFrame.contains("Open…"))
  }

  /// The frame operation buttons and thumbnail buttons share the timeline,
  /// but only a thumbnail composes its button tap with a reorder drag. Select
  /// frame 2, then use the known-working duplicate command as the control:
  /// duplicating the selected second frame must land on frame 3, not frame 2.
  @Test("clicking a timeline thumbnail selects that frame", .timeLimit(.minutes(1)))
  func clickingATimelineThumbnailSelectsThatFrame() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.frame-click"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        // At 80×24 the compact timeline starts on row 16. Its second 4×4
        // thumbnail occupies columns 30...35 and rows 18...21.
        .click(CellPoint(x: 32, y: 19)),
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
        .awaitCondition {
          terminal.latestFrame?.contains("Duplicated frame") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(document: playbackDocument(), stateDirectory: sharedStateDirectory)
      }
    ).run()

    let duplicatedFrame = terminal.latestFrame ?? ""
    #expect(result.exitReason == .inputEnded)
    #expect(duplicatedFrame.contains("Duplicated frame"))
    #expect(
      duplicatedFrame.contains("F3/3"),
      "the click must select frame 2 before duplication inserts after it"
    )
  }

  /// `Ctrl+E` is the GIF export, and it is the sheet that keeps the
  /// encoded preview — export is a lossy *conversion*, so seeing the
  /// bytes before committing is the whole affordance.
  @Test("Ctrl+E opens the GIF export sheet with an encoded preview")
  func ctrlEOpensExportSheetWithEncodedPreview() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.export-sheet"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("e"), modifiers: .ctrl)),
        .awaitCondition {
          terminal.latestFrame?.contains("Export GIF") == true
            && terminal.latestFrame?.contains("Encoded preview") == true
            && terminal.latestFrame?.contains("Destination") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 16, height: 16)),
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Export GIF") })
  }

  /// **The release gate, driven through real key presses.**
  ///
  /// `Ctrl+S` on a document that came from a GIF must not write back
  /// over it. The editor is handed a document whose `path` is
  /// `nyan.gif`; the sheet that appears has to be the project save, with
  /// a `.halfcell` destination and the reason spelled out — not a silent
  /// write that flattens every layer.
  @Test("Ctrl+S on a GIF-backed document falls through to Save As", .timeLimit(.minutes(1)))
  func ctrlSFallsThroughToSaveAsForAGIFBackedDocument() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.save-fallthrough"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("s"), modifiers: .ctrl)),
        .awaitCondition {
          terminal.latestFrame?.contains("Save project") == true
        },
      ])

    let document = GIFDocument.blank(size: .init(width: 8, height: 8))
    let origin = DocumentOrigin(
      source: .file(URL(fileURLWithPath: "/art/nyan.gif")),
      kind: .gif
    )

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: document,
          origin: origin,
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    let sheet = terminal.frames.last { $0.contains("Save project") } ?? ""
    #expect(result.exitReason == .inputEnded)
    #expect(!sheet.isEmpty, "Ctrl+S must raise the project save sheet, not write the GIF")
    // The destination is the project sibling, and the sheet says why the
    // author is being asked at all.
    #expect(sheet.contains("nyan.halfcell"))
    #expect(sheet.contains("flatten"))
  }

  /// `Ctrl+S` on a document that *did* come from a project writes
  /// straight back, with no sheet at all. The control for the test
  /// above: without it, a green fall-through could equally mean
  /// "Ctrl+S always prompts".
  @Test("Ctrl+S on a project-backed document saves without prompting", .timeLimit(.minutes(1)))
  func ctrlSWritesBackToAProjectPath() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("halfcell-runtime-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("session.halfcell")

    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.save-writeback"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("s"), modifiers: .ctrl)),
        .awaitCondition {
          terminal.latestFrame?.contains("Saved to") == true
        },
      ])

    let document = GIFDocument.blank(size: .init(width: 8, height: 8))

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: document,
          origin: DocumentOrigin(source: .file(target), kind: .project),
          projectBacking: ProjectBacking(target),
          stateDirectory: directory
        )
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(!terminal.frames.contains { $0.contains("Save project") }, "no prompt was needed")
    #expect(FileManager.default.fileExists(atPath: target.path))
    // What landed is the lossless project, not a GIF.
    let written = try Data(contentsOf: target)
    #expect(DocumentIngestion.kind(of: written) == .project)
  }

  /// The autosave timer runs on `AutosaveTicker`'s node, not on the
  /// editor root's already-spent `.task` (finding F8).
  ///
  /// The evidence is the file: the interval is driven down to
  /// milliseconds and the test waits for a real snapshot to appear on
  /// disk while the editor renders normally. If the ticker's `.task`
  /// were stacked onto the root beside playback, no snapshot would ever
  /// be written.
  @Test("the autosave node writes a recovery snapshot", .timeLimit(.minutes(1)))
  func autosaveTickerWritesASnapshot() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("halfcell-runtime-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let autosaveURL = GIFDocumentIO.autosaveURL(inStateDirectory: directory)

    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.autosave"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        // Paint one pixel so there is unsaved work worth snapshotting —
        // a clean document deliberately writes nothing.
        .press(KeyPress(.space, modifiers: [])),
        .awaitCondition {
          FileManager.default.fileExists(atPath: autosaveURL.path)
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 4, height: 4)),
          stateDirectory: directory,
          autosaveInterval: .milliseconds(20)
        )
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    let recovered = try #require(try AutosaveStore.recover(from: autosaveURL))
    #expect(recovered.document.size == GIFEditorCore.PixelSize(width: 4, height: 4))
  }

  /// The dirty guard, extended past quit: `Ctrl+Alt+N` on a document
  /// with unsaved work raises the confirmation rather than replacing it.
  @Test("New on a dirty document asks before discarding", .timeLimit(.minutes(1)))
  func newOnADirtyDocumentAsksFirst() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.new-guard"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.space, modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Painted at") == true
        },
        .press(KeyPress(.character("n"), modifiers: [.ctrl, .alt])),
        .awaitCondition {
          // Either the guard came up (the contract) or the size prompt
          // did (the regression). Waiting only on the guard would hang
          // rather than fail if the guard were ever dropped.
          terminal.latestFrame?.contains("Unsaved changes") == true
            || terminal.latestFrame?.contains("New document") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 8, height: 8)),
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Unsaved changes") })
    #expect(terminal.frames.contains { $0.contains("Discard") })
    // The size prompt must not have jumped the guard.
    #expect(!terminal.frames.contains { $0.contains("New document") })
  }

  /// The control for the guard: with nothing unsaved, `Ctrl+Alt+N` goes
  /// straight to the size prompt.
  @Test("New on a clean document goes straight to the size prompt", .timeLimit(.minutes(1)))
  func newOnACleanDocumentSkipsTheGuard() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.new-clean"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("n"), modifiers: [.ctrl, .alt])),
        .awaitCondition {
          terminal.latestFrame?.contains("New document") == true
            || terminal.latestFrame?.contains("Unsaved changes") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 8, height: 8)),
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("New document") })
    #expect(!terminal.frames.contains { $0.contains("Unsaved changes") })
  }

  /// Escape dismisses a sheet presented from `FilePresentationHost`.
  ///
  /// Worth pinning separately from the other Escape tests: those sheets
  /// hang off the editor *root*, and these had to move onto a sibling
  /// node to keep the root's modifier chain inside the resolve stack.
  /// "Still renders" and "still participates in the dismiss stack" are
  /// different claims, and only the second one is about being usable.
  @Test("Escape dismisses a sheet presented off the editor root", .timeLimit(.minutes(1)))
  func escapeDismissesAHostPresentedSheet() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.new-escape"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("n"), modifiers: [.ctrl, .alt])),
        .awaitCondition {
          terminal.latestFrame?.contains("New document") == true
        },
        .press(KeyPress(.escape, modifiers: [])),
        // Either the sheet closes (the contract) or the editor root
        // claims Escape over it (the regression). Waiting on the closed
        // sheet alone would hang rather than fail if that flipped.
        .awaitCondition {
          terminal.latestFrame?.contains("New document") != true
            || terminal.latestFrame?.contains("Selection cleared") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 8, height: 8)),
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    let finalFrame = terminal.latestFrame ?? ""
    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("New document") })
    #expect(!finalFrame.contains("New document"))
    // The editor is still rendering behind the dismissed sheet, so the
    // check above cannot pass vacuously on a teardown write.
    #expect(finalFrame.contains("Palette"))
  }

  /// `Ctrl+O` raises the open sheet, with the path field and the
  /// completion affordance that stands in for a picker.
  @Test("Ctrl+O opens the open sheet", .timeLimit(.minutes(1)))
  func ctrlOOpensTheOpenSheet() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.open-sheet"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("o"), modifiers: .ctrl)),
        .awaitCondition {
          terminal.latestFrame?.contains("Open a GIF") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 8, height: 8)),
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    let sheet = terminal.frames.last { $0.contains("Open a GIF") } ?? ""
    #expect(result.exitReason == .inputEnded)
    #expect(!sheet.isEmpty)
    #expect(sheet.contains("Complete"))
    #expect(sheet.contains("Recent"))
  }

  @Test("Alt+P toggles playback mode")
  func altPTogglesPlaybackMode() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.playback"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("p"), modifiers: .alt)),
        .awaitCondition {
          terminal.latestFrame?.contains("Playback started") == true
            && terminal.latestFrame?.contains("PLAY") == true
        },
        .press(KeyPress(.character("p"), modifiers: .alt)),
        .awaitCondition {
          terminal.latestFrame?.contains("Playback paused") == true
            && terminal.latestFrame?.contains("PLAY") == false
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(document: playbackDocument(), stateDirectory: sharedStateDirectory)
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Playback started") })
    #expect(terminal.latestFrame?.contains("Playback paused") == true)
    #expect(!terminal.frames.contains { $0.contains("Keyboard help") })
  }

  /// Bare `Escape` closes the save sheet, honoring the `Esc` system hint on
  /// its Cancel button.
  ///
  /// The dispatch order this pins is worth stating: the editor root's
  /// modifier-free key handler (`applyFocusedEditorBindings`, which maps
  /// `.escape` to `clearSelection()`) is *not* on the focus bubble path out of
  /// a portal-presented sheet, so the runtime falls through to its reserved
  /// bare-Escape modal dismiss. `bareEscapeOutsideASheetStillClearsTheSelection`
  /// is the control for that claim: the same key on the same editor, with no
  /// sheet up, does reach the editor root.
  @Test("Escape dismisses the GIF export sheet", .timeLimit(.minutes(1)))
  func escapeDismissesExportSheet() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.save-sheet-escape"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("e"), modifiers: .ctrl)),
        .awaitCondition {
          terminal.latestFrame?.contains("Review GIF before saving") == true
        },
        .press(KeyPress(.escape, modifiers: [])),
        // Two outcomes end the wait: the sheet closes (the contract), or the
        // editor root claims Escape first and announces "Selection cleared"
        // over a still-open sheet (the regression). Waiting on the closed sheet
        // alone would hang rather than fail if that ordering ever flipped.
        .awaitCondition {
          terminal.latestFrame?.contains("Review GIF before saving") != true
            || terminal.latestFrame?.contains("Selection cleared") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 16, height: 16)),
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    let finalFrame = terminal.latestFrame ?? ""
    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Review GIF before saving") })
    #expect(!finalFrame.contains("Review GIF before saving"))
    // The editor is still rendering behind the dismissed sheet, so the check
    // above cannot pass vacuously on a teardown write.
    #expect(finalFrame.contains("Palette"))
  }

  /// Bare `Escape` closes the resize-canvas sheet, honoring the `Esc` system
  /// hint on its Cancel button. Unlike the save sheet this one focuses no
  /// `TextField`, so it also covers the button-focused shape of the same path.
  @Test("Escape dismisses the resize canvas sheet", .timeLimit(.minutes(1)))
  func escapeDismissesResizeCanvasSheet() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.resize-sheet-escape"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("r"), modifiers: .ctrl)),
        .awaitCondition {
          terminal.latestFrame?.contains("Pick a square canvas size") == true
        },
        .press(KeyPress(.escape, modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Pick a square canvas size") != true
            || terminal.latestFrame?.contains("Selection cleared") == true
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 16, height: 16)),
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    let finalFrame = terminal.latestFrame ?? ""
    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Pick a square canvas size") })
    #expect(!finalFrame.contains("Pick a square canvas size"))
    #expect(finalFrame.contains("Palette"))
  }

  /// Control for the two sheet-dismiss tests above: with no sheet presented the
  /// editor root *does* claim bare Escape and clears the selection. Without
  /// this, a green dismiss test could equally mean "nothing anywhere handles
  /// Escape", and a future root binding that starts swallowing Escape inside
  /// sheets would look identical to today.
  @Test("bare Escape outside a sheet still clears the selection", .timeLimit(.minutes(1)))
  func bareEscapeOutsideASheetStillClearsTheSelection() async throws {
    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.bare-escape"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.escape, modifiers: [])),
        .awaitCondition {
          terminal.frames.contains { $0.contains("Selection cleared") }
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 16, height: 16)),
          stateDirectory: sharedStateDirectory
        )
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Selection cleared") })
  }

  /// `?` opens the shortcut overlay, Escape closes it, and the editor is
  /// still taking input afterwards.
  ///
  /// This test used to assert the *opposite* of its first half: a
  /// hand-written "Keyboard help" sheet existed, was reduced to a bare
  /// `Spinner()` mid-debugging, and was then deleted outright in the
  /// commit that spent its slot on the root modifier chain on the save
  /// sheet. What survived was the second half — press a key afterwards
  /// and check the editor answers — and that is the half worth keeping.
  /// The overlay is back, rendered from `KeyBindingCatalog` rather than
  /// from a second copy of the shortcut list, and it still has to hand
  /// the editor back when it closes.
  @Test("? opens the keyboard overlay and the editor still responds", .timeLimit(.minutes(1)))
  func questionMarkOpensKeyboardHelp() async throws {
    let directory = temporaryStateDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let terminal = GIFEditorPresentationRecordingTerminalHost(
      surfaceSize: .init(width: 80, height: 24)
    )
    let rootIdentity = Identity(components: ["gifeditor.presentation-runtime.help"])

    let inputReader = GIFEditorPresentationInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.character("?"), modifiers: [])),
        .awaitCondition {
          terminal.latestFrame?.contains("Keyboard shortcuts") == true
        },
        .press(KeyPress(.escape, modifiers: [])),
        // Either the overlay closes (the contract) or the editor root
        // claims Escape over it (the regression). Waiting on the closed
        // overlay alone would hang rather than fail if that flipped.
        .awaitCondition {
          terminal.latestFrame?.contains("Keyboard shortcuts") != true
            || terminal.latestFrame?.contains("Selection cleared") == true
        },
        // The surviving half of the original test: the brush-size key
        // must still reach the editor once the overlay is gone.
        .press(KeyPress(.character("]"), modifiers: [])),
        .awaitCondition {
          terminal.frames.contains { $0.contains("B2") }
        },
      ])

    let result = try await RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: GIFEditorPresentationEmptySignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 80, height: 24),
      viewBuilder: { _, _ in
        EditorView(
          document: GIFDocument.blank(size: .init(width: 16, height: 16)),
          stateDirectory: directory
        )
      }
    ).run()

    #expect(result.exitReason == .inputEnded)
    #expect(terminal.frames.contains { $0.contains("Keyboard shortcuts") })
    // Rendered from the catalog, so a row the catalog owns is on screen.
    #expect(terminal.frames.contains { $0.contains("Bucket fill") })
    #expect(terminal.latestFrame?.contains("Keyboard shortcuts") != true)
    #expect(terminal.frames.contains { $0.contains("B2") })
  }

  /// The first-run hint appears once, and the marker it leaves behind
  /// keeps it from appearing again.
  @Test("the first-run hint is shown once per state directory", .timeLimit(.minutes(1)))
  func firstRunHintIsShownOnce() async throws {
    let directory = temporaryStateDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    func launch(identity: String, expectsHint: Bool) async throws -> [String] {
      let terminal = GIFEditorPresentationRecordingTerminalHost(
        surfaceSize: .init(width: 80, height: 24)
      )
      let rootIdentity = Identity(components: [identity])
      // Waiting on the hint would hang the second launch, where its
      // absence is the point; waiting on a key press would race the
      // hint's node against the status line that press writes. So each
      // launch settles on the thing it is actually asserting.
      let steps: [GIFEditorPresentationInputStep] =
        expectsHint
        ? [
          .awaitCondition {
            terminal.frames.contains { $0.contains(FirstRunHint.message) }
          }
        ]
        : [
          .press(KeyPress(.character("]"), modifiers: [])),
          .awaitCondition {
            terminal.frames.contains { $0.contains("B2") }
          },
        ]
      let inputReader = GIFEditorPresentationInputReader(
        frameSignal: terminal.frameSignal,
        steps: steps
      )
      _ = try await RunLoop(
        rootIdentity: rootIdentity,
        presentationSurface: terminal,
        terminalInputReader: inputReader,
        signalReader: GIFEditorPresentationEmptySignalReader(),
        stateContainer: StateContainer(
          initialState: 0,
          invalidationIdentities: [rootIdentity]
        ),
        focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
        proposal: .init(width: 80, height: 24),
        viewBuilder: { _, _ in
          EditorView(
            document: GIFDocument.blank(size: .init(width: 16, height: 16)),
            stateDirectory: directory
          )
        }
      ).run()
      return terminal.frames
    }

    let first = try await launch(
      identity: "gifeditor.presentation-runtime.first-run.1",
      expectsHint: true
    )
    #expect(first.contains { $0.contains(FirstRunHint.message) })
    #expect(
      FileManager.default.fileExists(
        atPath: FirstRunHint.markerURL(inStateDirectory: directory).path
      )
    )

    let second = try await launch(
      identity: "gifeditor.presentation-runtime.first-run.2",
      expectsHint: false
    )
    #expect(!second.contains { $0.contains(FirstRunHint.message) })
    // Not vacuous: the second launch really did run and take input.
    #expect(second.contains { $0.contains("B2") })
  }
}

/// A throwaway `~/.config/halfcell/` stand-in.
///
/// Every `EditorView` a runtime test builds needs one: the view model
/// loads the recents list at construction and the first-run node writes
/// a marker on its first frame, and neither belongs in the developer's
/// real config directory.
private func temporaryStateDirectory() -> URL {
  URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-runtime-\(UUID().uuidString)")
}

/// The state directory for the runs that are *not* about persistence.
///
/// Created once per test process, with the first-run hint already
/// claimed, so the nudge never lands in a status line these tests assert
/// on and no run reads the developer's real recents list. Nothing else
/// is ever written into it — the tests that do write pick their own
/// directory and delete it — so it is left for the OS to reap along with
/// the rest of the temporary directory.
private let sharedStateDirectory: URL = {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-runtime-shared-\(UUID().uuidString)")
  FirstRunHint.claim(inStateDirectory: directory)
  return directory
}()

private func playbackDocument() -> GIFDocument {
  let size = GIFEditorCore.PixelSize(width: 4, height: 4)
  let first = EditorFrame(
    layers: [EditorLayer(name: "Frame 1", pixels: PixelBuffer(size: size, fill: 1))],
    delayCentiseconds: 1
  )
  let second = EditorFrame(
    layers: [EditorLayer(name: "Frame 2", pixels: PixelBuffer(size: size, fill: 2))],
    delayCentiseconds: 1
  )
  return GIFDocument(size: size, frames: [first, second])
}

private final class GIFEditorPresentationRecordingTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []

  var latestFrame: String? {
    frames.last
  }

  /// Notified after every appended frame, so an awaited input step can
  /// re-check its predicate the instant a frame lands instead of polling.
  let frameSignal = MainActorConditionSignal()

  init(
    surfaceSize: CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    ).render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
    return TerminalPresentationMetrics(
      bytesWritten: rendered.utf8.count,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  /// The run loop only ever presents on the MainActor; `assumeIsolated`
  /// bridges these nonisolated protocol witnesses to the MainActor-isolated
  /// signal.
  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}

private enum GIFEditorPresentationInputStep {
  case press(KeyPress)
  case click(CellPoint)
  /// Suspends the input script until `predicate` holds, re-evaluated only when
  /// the host appends a frame (`frameSignal.notify()`) rather than on a clock.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class GIFEditorPresentationInputReader: TerminalInputReading {
  private let steps: [GIFEditorPresentationInputStep]
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    steps: [GIFEditorPresentationInputStep]
  ) {
    self.frameSignal = frameSignal
    self.steps = steps
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let event):
            continuation.yield(.key(event))
          case .click(let cell):
            continuation.yield(
              .mouse(.init(kind: .down(.primary), location: .cellFallback(cell)))
            )
            continuation.yield(
              .mouse(.init(kind: .up(.primary), location: .cellFallback(cell)))
            )
          case .awaitCondition(let predicate):
            await frameSignal.wait(until: predicate)
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class GIFEditorPresentationEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
