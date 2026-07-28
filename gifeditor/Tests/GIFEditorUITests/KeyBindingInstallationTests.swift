import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// What the editor *actually installs*, against what the catalog claims.
///
/// The catalog tests check the table's own consistency, and the compiler
/// checks that every command has a chord and behavior. Neither of them
/// can tell whether a binding site exists: a command could be declared,
/// documented, shown in the `?` overlay, given an action in `perform`,
/// and still never be chained onto the editor's action scope.
///
/// So this renders the real `EditorView` and reads back the
/// `(command, chord)` pairs `keyCommand(_:chord:action:)` recorded while
/// its body was built. Building the body is what runs the chains, so a
/// missing binding site, a duplicate, or one installed under the wrong
/// chord all show up here.
@MainActor
@Suite("GIF editor keybinding installation", .serialized)
struct KeyBindingInstallationTests {
  /// The chords the catalog says are registered as `keyCommand`s.
  private static var declaredChordCommandChords: Set<EditorKeyChord> {
    var chords: Set<EditorKeyChord> = []
    for entry in KeyBindingCatalog.entries where entry.dispatch == .keyCommand {
      chords.formUnion(entry.chords)
    }
    return chords
  }

  private static var declaredChordCommands: Set<EditorCommand> {
    Set(
      KeyBindingCatalog.entries
        .filter { $0.dispatch == .keyCommand }
        .map(\.command)
    )
  }

  @Test("the editor installs exactly the chords the catalog declares")
  func editorInstallsExactlyTheDeclaredChords() {
    InstalledKeyCommands.reset()
    renderEditor()

    let installed = InstalledKeyCommands.chords
    let declared = Self.declaredChordCommandChords

    let missing = declared.subtracting(installed).map(\.display).sorted()
    #expect(
      missing.isEmpty,
      "the catalog declares \(missing.joined(separator: ", ")) but no binding site installs it"
    )

    // The reverse can only happen by installing a command under a chord
    // it does not own, which `keyCommand(_:chord:)` traps on — so this
    // is a belt-and-braces check that the trap has not been loosened.
    let unexpected = installed.subtracting(declared).map(\.display).sorted()
    #expect(
      unexpected.isEmpty,
      "installed but not declared: \(unexpected.joined(separator: ", "))"
    )

    #expect(InstalledKeyCommands.commands == Self.declaredChordCommands)
  }

  /// Guards the guard. If the recorder silently stopped recording — the
  /// one way the check above could pass vacuously — the counts would
  /// both be zero and everything would look fine.
  @Test("the installation recorder actually sees the editor's bindings")
  func recorderIsNotVacuous() {
    InstalledKeyCommands.reset()
    #expect(InstalledKeyCommands.chords.isEmpty)
    renderEditor()
    #expect(InstalledKeyCommands.chords.count > 30)
  }

  /// Renders the editor into a throwaway state directory.
  ///
  /// The directory matters even for a one-shot render: `EditingSession`
  /// reads the recents list at construction, and a test that read the
  /// developer's real `~/.config/halfcell/` would be reading whatever
  /// they last opened.
  private func renderEditor() {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("halfcell-keybindings-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    var environment = EnvironmentValues()
    environment.terminalSize = CellSize(width: 80, height: 24)
    _ = DefaultRenderer().render(
      EditorView(
        document: GIFDocument.blank(size: .init(width: 8, height: 8)),
        stateDirectory: directory
      ),
      context: ResolveContext(
        identity: Identity(components: ["gifeditor.ui.tests.keybinding-installation"]),
        environmentValues: environment
      ),
      proposal: ProposedSize(width: 80, height: 24)
    )
  }
}
