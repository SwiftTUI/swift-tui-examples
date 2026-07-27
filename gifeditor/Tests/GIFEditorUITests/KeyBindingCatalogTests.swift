import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// The catalog's invariants, and the two checks that make it the *only*
/// place a binding can be declared.
///
/// The compiler already carries most of the weight: `EditorCommand` is
/// `CaseIterable` and `KeyBindingCatalog.entry(for:)` switches over it
/// exhaustively, so a case without a chord, a section and a label does
/// not build; and `perform` in `EditorKeyBindings.swift` switches over it
/// with no `default`, so a case without behavior does not build either.
/// What is left for a test is the part the type system cannot see.
@MainActor
@Suite("GIF editor keybinding catalog")
struct KeyBindingCatalogTests {
  /// Every chord in `Sources/GIFEditorUI`, from the catalog's point of
  /// view. Built once and shared by the checks below.
  private static let allChords: [(EditorCommand, EditorKeyChord)] =
    KeyBindingCatalog.entries.flatMap { entry in
      entry.chords.map { (entry.command, $0) }
    }

  @Test("no two commands claim the same chord")
  func chordsAreUnique() {
    var owner: [EditorKeyChord: EditorCommand] = [:]
    for (command, chord) in Self.allChords {
      #expect(
        owner[chord] == nil,
        "\(chord.display) is claimed by both \(owner[chord]?.rawValue ?? "?") and \(command.rawValue)"
      )
      owner[chord] = command
    }
    // The lazily-built lookup the editor dispatches through agrees.
    #expect(KeyBindingCatalog.commandsByChord.count == Self.allChords.count)
  }

  /// A command's dispatch has to match the shape of its chords, because
  /// SwiftTUI enforces exactly this at registration time: it silently
  /// drops modifier-less `keyCommand`s (single keys are reserved for
  /// framework dispatch), so a bare key can only be served through
  /// `onKeyPress`, and a modified key registered as a focused key would
  /// never be reached because `focusedCommand(for:)` filters on
  /// `isBare`. Either mistake is a binding that silently does nothing.
  @Test("dispatch matches chord shape")
  func dispatchMatchesChordShape() {
    for entry in KeyBindingCatalog.entries {
      let bareCount = entry.chords.filter(\.isBare).count
      switch entry.dispatch {
      case .focusedKey:
        #expect(
          bareCount == entry.chords.count,
          "\(entry.command.rawValue) is focused-key dispatched but has a modified chord"
        )
      case .keyCommand:
        #expect(
          bareCount == 0,
          """
          \(entry.command.rawValue) is keyCommand dispatched but has a bare chord; \
          SwiftTUI drops modifier-less registrations
          """
        )
      case .runLoopExitKey:
        #expect(entry.chords.count == 1)
      }
    }
  }

  /// Every bare chord resolves back to its command through the lookup
  /// `handleFocusedEditorKey` actually uses, and no modified chord does.
  @Test("focused-key lookup resolves exactly the bare bindings")
  func focusedLookupResolvesBareBindings() {
    for (command, chord) in Self.allChords {
      let resolved = KeyBindingCatalog.focusedCommand(for: chord)
      if KeyBindingCatalog.entry(for: command).dispatch == .focusedKey {
        #expect(resolved == command, "\(chord.display) should reach \(command.rawValue)")
      } else {
        #expect(resolved == nil, "\(chord.display) must not be served as a focused key")
      }
    }
  }

  /// The chord vocabulary survives the crossing into SwiftTUI's and
  /// back. `KeyBindingCatalog.swift` imports nothing so the doc
  /// generator can compile it alone; this is the seam that pays for it,
  /// and an unmapped case here would be a binding registered under a key
  /// nobody presses.
  @Test("every catalog chord round-trips through SwiftTUI's key vocabulary")
  func chordsRoundTripThroughSwiftTUI() {
    for (command, chord) in Self.allChords {
      let press = chord.keyPress
      #expect(
        EditorKeyChord(press) == chord,
        "\(command.rawValue)'s \(chord.display) did not survive the SwiftTUI bridge"
      )
    }
  }

  /// The families `docs/KEYBINDINGS.md` warns about, checked rather than
  /// merely documented. The terminal input path does not deliver these
  /// as distinct presses, so binding one produces a shortcut that never
  /// fires and a doc row that lies.
  @Test("no terminal-ambiguous chord is bound")
  func noTerminalAmbiguousChordsAreBound() {
    for (command, chord) in Self.allChords {
      let name = "\(command.rawValue) (\(chord.display))"
      guard case .character(let character) = chord.key else { continue }

      #expect(
        !(chord.modifiers.contains(.ctrl) && chord.modifiers.contains(.shift)),
        "\(name): Ctrl+Shift+letter is not received distinctly"
      )
      #expect(
        !(chord.modifiers.contains(.ctrl) && character.isNumber),
        "\(name): Ctrl+digit is not received distinctly"
      )
      #expect(
        !(chord.modifiers.contains(.ctrl) && (character == "[" || character == "]")),
        "\(name): Ctrl+[ / Ctrl+] collide with Escape and other CSI introducers"
      )
      #expect(
        !(chord.modifiers.contains(.alt) && character == "["),
        "\(name): Alt+[ collides with the CSI introducer"
      )
    }
  }

  /// The keys the shape tools, the transforms and the timeline verbs are
  /// on, named one by one.
  ///
  /// The invariants above would be just as happy if `H` flipped
  /// vertically and `V` horizontally. This is the table a rebind has to
  /// come through, so moving a key is a deliberate edit in two places
  /// rather than a silent one in the catalog.
  @Test("each command reaches the editor on the key it is documented under")
  func documentedKeysResolveToTheirCommands() {
    let expected: [(Character, EditorCommand)] = [
      ("r", .selectRectangle),
      ("c", .selectEllipse),
      ("f", .toggleShapeFill),
      ("s", .toggleStrokeMirrorX),
      ("H", .flipHorizontally),
      ("V", .flipVertically),
      ("R", .rotateClockwise),
      ("L", .rotateCounterClockwise),
      ("X", .cutSelection),
      (",", .moveFrameToStart),
      (".", .moveFrameToEnd),
      ("d", .cycleFrameDisposal),
      ("_", .decreaseLoopCount),
      ("+", .increaseLoopCount),
      (")", .toggleLoopsForever),
    ]
    for (key, command) in expected {
      #expect(
        KeyBindingCatalog.focusedCommand(for: .bare(key)) == command,
        "bare \(key) should run \(command.rawValue)"
      )
    }
  }

  /// **The root-chain depth budget.**
  ///
  /// `EditorView`'s modifier chain resolves by recursing once per nested
  /// `ModifiedContent` layer, and it has already overflowed the resolve
  /// stack once — taking the whole editor down, not just the modifier
  /// that overflowed it. Every `keyCommand` chord is one such layer;
  /// every bare key rides the single `onKeyPress(.any)` handler the root
  /// already wears and costs nothing.
  ///
  /// So this is not a tidiness check. A change that grows this number is
  /// spending the editor's scarcest resource, and it should have to say
  /// so out loud — while a change that adds a whole feature's worth of
  /// bare keys leaves it alone.
  @Test("the editor's chord count — its resolve-stack budget — is unchanged")
  func chordDispatchedBindingsStayWithinTheirBudget() {
    let chords = KeyBindingCatalog.entries
      .filter { $0.dispatch == .keyCommand }
      .flatMap(\.chords)
    #expect(
      chords.count == 42,
      """
      the root chain installs \(chords.count) keyCommand layers, not 42. \
      Prefer a bare key (dispatch: .focusedKey) unless the chord is worth \
      a nested ModifiedContent layer on a chain that has already \
      overflowed the resolve stack once.
      """
    )
  }

  /// **The bypass check.**
  ///
  /// `keyCommand(_ command:chord:action:)` is what routes a binding
  /// through the catalog, but SwiftTUI's own
  /// `keyCommand(_ description:key:modifiers:)` is still visible and
  /// still callable — nothing in the language can hide it. So the
  /// remaining hole is closed here instead: a raw string-literal
  /// `keyCommand` anywhere in `GIFEditorUI` is a shortcut that would
  /// never reach the `?` overlay or `docs/KEYBINDINGS.md`, and it fails
  /// the suite.
  ///
  /// Reads the sources; writes nothing.
  @Test("no binding site bypasses the catalog")
  func noBindingSiteBypassesTheCatalog() throws {
    let sources = try Self.everySourceFile()
    #expect(!sources.isEmpty, "expected to find sources under \(Self.sourcesRoot.path)")

    for (name, text) in sources {
      // The catalog-routed overload takes a `.command` case; only the
      // raw SwiftTUI one takes a description string.
      #expect(
        !text.contains("keyCommand(\""),
        """
        \(name) registers a keyCommand with an inline description. Add the \
        binding to KeyBindingCatalog and use `.keyCommand(.yourCommand)` \
        instead, so the `?` overlay and docs/KEYBINDINGS.md see it.
        """
      )
    }
  }

  /// `.exitOnKeys` is the one binding route the catalog cannot install:
  /// it is declared on the `Scene` in `GIFEditorApp`, which `GIFEditorUI`
  /// cannot see. The catalog carries those keys as `.runLoopExitKey`
  /// entries so the `?` overlay and the docs still list them, but nothing
  /// made the two agree — the entry was documented and unverified.
  ///
  /// Counting is the strongest check available from here without parsing
  /// Swift: adding an exit key without cataloguing it, or dropping one
  /// while leaving its row behind, fails the suite.
  @Test("every run-loop exit key is catalogued")
  func everyRunLoopExitKeyIsCatalogued() throws {
    let declared = try Self.everySourceFile()
      .filter { $0.text.contains(".exitOnKeys(") }
      .reduce(into: 0) { total, file in
        // Count the `KeyPress(` literals inside each `.exitOnKeys([...])`.
        var remainder = Substring(file.text)
        while let open = remainder.range(of: ".exitOnKeys(") {
          guard let close = remainder[open.upperBound...].range(of: "])") else { break }
          total +=
            remainder[open.upperBound..<close.lowerBound]
            .components(separatedBy: "KeyPress(").count - 1
          remainder = remainder[close.upperBound...]
        }
      }

    let catalogued = EditorCommand.allCases.filter {
      KeyBindingCatalog.entry(for: $0).dispatch == .runLoopExitKey
    }

    #expect(
      declared == catalogued.count,
      """
      \(declared) key(s) are registered via .exitOnKeys but \(catalogued.count) \
      command(s) in KeyBindingCatalog dispatch as .runLoopExitKey. An exit key \
      that is not catalogued never reaches the ? overlay or \
      docs/KEYBINDINGS.md; a catalogued one that is no longer registered is a \
      shortcut the docs promise and the app does not honour.
      """
    )
    #expect(declared > 0, "expected at least one .exitOnKeys registration to verify against")
  }

  /// Every `.swift` file under `Sources/`, not just `GIFEditorUI` — a
  /// binding registered from another module is exactly the hole these
  /// checks exist to close.
  static func everySourceFile() throws -> [(name: String, text: String)] {
    let root = sourcesRoot
    guard
      let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: nil)
    else { return [] }
    return try walker.compactMap { $0 as? URL }
      .filter { $0.pathExtension == "swift" }
      .sorted { $0.path < $1.path }
      .map { (name: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8)) }
  }

  /// `Sources/`, located from this file rather than from the working
  /// directory, which `swift test` does not promise.
  static var sourcesRoot: URL {
    URL(fileURLWithPath: #filePath)  // …/Tests/GIFEditorUITests/<this file>
      .deletingLastPathComponent()  // …/Tests/GIFEditorUITests
      .deletingLastPathComponent()  // …/Tests
      .deletingLastPathComponent()  // …/gifeditor
      .appendingPathComponent("Sources")
  }

  /// `Sources/GIFEditorUI`, located from this file rather than from the
  /// working directory, which `swift test` does not promise.
  static var sourceDirectory: URL {
    URL(fileURLWithPath: #filePath)  // …/Tests/GIFEditorUITests/<this file>
      .deletingLastPathComponent()  // …/Tests/GIFEditorUITests
      .deletingLastPathComponent()  // …/Tests
      .deletingLastPathComponent()  // …/gifeditor
      .appendingPathComponent("Sources")
      .appendingPathComponent("GIFEditorUI")
  }
}
