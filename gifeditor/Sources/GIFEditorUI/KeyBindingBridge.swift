import SwiftTUI

/// Translates between the catalog's chord vocabulary and SwiftTUI's, and
/// exposes the one `keyCommand` overload the editor is allowed to use.
///
/// `KeyBindingCatalog.swift` imports nothing so it can be compiled by the
/// doc generator on its own; the cost of that is this file, which is the
/// single crossing point between the two vocabularies. A test walks every
/// chord in the catalog across it in both directions, so the translation
/// cannot quietly rot.

// MARK: - Vocabulary bridge

extension EditorKeyModifiers {
  init(_ modifiers: EventModifiers) {
    var result: EditorKeyModifiers = []
    if modifiers.contains(.ctrl) { result.insert(.ctrl) }
    if modifiers.contains(.alt) { result.insert(.alt) }
    if modifiers.contains(.shift) { result.insert(.shift) }
    self = result
  }

  var eventModifiers: EventModifiers {
    var result: EventModifiers = []
    if contains(.ctrl) { result.insert(.ctrl) }
    if contains(.alt) { result.insert(.alt) }
    if contains(.shift) { result.insert(.shift) }
    return result
  }
}

extension EditorKey {
  /// `nil` for the keys the catalog has no vocabulary for — Tab, Home,
  /// function keys and the rest. Those are keys the editor does not bind,
  /// so refusing to name them is the point: an unbound key falls through
  /// as `.ignored` rather than matching some near-miss case.
  init?(_ key: KeyEvent) {
    switch key {
    case .character(let character): self = .character(character)
    case .space: self = .space
    case .return: self = .return
    case .escape: self = .escape
    case .arrowLeft: self = .arrowLeft
    case .arrowRight: self = .arrowRight
    case .arrowUp: self = .arrowUp
    case .arrowDown: self = .arrowDown
    default: return nil
    }
  }

  var keyEvent: KeyEvent {
    switch self {
    case .character(let character): .character(character)
    case .space: .space
    case .return: .return
    case .escape: .escape
    case .arrowLeft: .arrowLeft
    case .arrowRight: .arrowRight
    case .arrowUp: .arrowUp
    case .arrowDown: .arrowDown
    }
  }
}

extension EditorKeyChord {
  init?(_ keyPress: KeyPress) {
    guard let key = EditorKey(keyPress.key) else { return nil }
    self.init(key, modifiers: EditorKeyModifiers(keyPress.modifiers))
  }

  var keyPress: KeyPress {
    KeyPress(key.keyEvent, modifiers: modifiers.eventModifiers)
  }
}

// MARK: - Installation

/// Which catalog chords the live view tree has actually registered.
///
/// Every `keyCommand` the editor installs goes through the overload
/// below, and the overload records the `(command, chord)` pair it just
/// registered. A runtime test resets this, boots the editor, and compares
/// what got installed against what the catalog declares — so a catalog
/// row with no binding site, or a binding site under the wrong chord,
/// fails rather than merely reading wrong in the docs.
///
/// The production cost is one set insert per registration per body build.
@MainActor
enum InstalledKeyCommands {
  private(set) static var chords: Set<EditorKeyChord> = []
  private(set) static var commands: Set<EditorCommand> = []

  static func record(_ command: EditorCommand, chord: EditorKeyChord) {
    chords.insert(chord)
    commands.insert(command)
  }

  static func reset() {
    chords.removeAll()
    commands.removeAll()
  }
}

extension View where Self: ActionScope & Sendable {
  /// Registers a catalog command's chord on this action scope.
  ///
  /// **This is the only `keyCommand` spelling the editor may use.** The
  /// description SwiftTUI records is the catalog's label and the binding
  /// is the catalog's chord, so a shortcut cannot exist under a name or a
  /// key the `?` overlay and `docs/KEYBINDINGS.md` have never heard of.
  /// SwiftTUI's own overload — the one taking an inline description
  /// string — stays visible and callable, so `KeyBindingCatalogTests`
  /// fails the suite if a call to it reappears anywhere in
  /// `GIFEditorUI`.
  ///
  /// `chord` names which of a multi-chord command's keys this site
  /// installs; commands with exactly one chord omit it. Passing a chord
  /// the command does not own is a programmer error, not a runtime
  /// condition, so it traps.
  @MainActor
  func keyCommand(
    _ command: EditorCommand,
    chord: EditorKeyChord? = nil,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    let entry = KeyBindingCatalog.entry(for: command)
    let resolved = chord ?? entry.soleChord
    guard let resolved, entry.chords.contains(resolved) else {
      preconditionFailure(
        "\(command.rawValue) has \(entry.chords.count) chords; name the one this site installs"
      )
    }
    InstalledKeyCommands.record(command, chord: resolved)
    return keyCommand(
      entry.label,
      key: resolved.key.keyEvent,
      modifiers: resolved.modifiers.eventModifiers,
      action: action
    )
  }
}
