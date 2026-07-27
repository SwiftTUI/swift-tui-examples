import Foundation

/// A document-replacing verb the editor may have to hold back.
///
/// New, Open and Quit each destroy unsaved work, so each one is captured
/// as a value while the unsaved-changes guard asks the author what to do
/// about it, and is then performed (or dropped) by their answer. One
/// enum rather than a boolean per verb: there is exactly one pending
/// intent at a time, and the compiler should be the thing that knows it.
enum PendingDocumentAction: Equatable, Sendable {
  case new
  case open
  case openRecent(URL)
  case quit
}

/// Which file-lifecycle sheet is up.
///
/// A single `.sheet(item:)` rather than one `isPresented` sheet per
/// verb. The three are mutually exclusive by construction, and an enum
/// makes that a fact rather than three booleans that could disagree.
/// The unsaved-changes guard deliberately does *not* live here: it is a
/// `confirmationDialog`, a different presentation kind, so the guard can
/// hand off to a sheet without the two fighting over one slot.
enum FileSheet: Identifiable, Equatable, Sendable {
  case new
  case open
  case saveAs

  var id: String {
    switch self {
    case .new: "new"
    case .open: "open"
    case .saveAs: "save-as"
    }
  }
}

/// The File menu's verbs, bundled so the menu views take one parameter
/// rather than six.
///
/// Every field is the same closure shape the keybindings call, so a menu
/// item and its shortcut are guaranteed to run the same code rather than
/// two implementations that drift.
struct FileMenuActions: Sendable {
  var new: @MainActor @Sendable () -> Void
  var open: @MainActor @Sendable () -> Void
  var openRecent: @MainActor @Sendable (URL) -> Void
  var save: @MainActor @Sendable () -> Void
  var saveAs: @MainActor @Sendable () -> Void
  var exportGIF: @MainActor @Sendable () -> Void

  /// Does nothing, for the render tests that exercise menu *layout*
  /// rather than behavior.
  static let inert = FileMenuActions(
    new: {},
    open: {},
    openRecent: { _ in },
    save: {},
    saveAs: {},
    exportGIF: {}
  )
}
