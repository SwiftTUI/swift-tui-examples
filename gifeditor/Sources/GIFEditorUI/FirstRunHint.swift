import Foundation
import SwiftTUI

/// The "press `?`" nudge, shown once and then never again.
///
/// Discoverability for a terminal app is a real problem — there is no
/// menu bar to browse and no tooltip to hover — but a hint that reappears
/// every launch is chrome the author has to read past forever. So it is
/// spent on first run and remembered in the same `~/.config/halfcell/`
/// directory the recents list and the autosave file already live in.
enum FirstRunHint {
  /// What the status line says on a first launch.
  static let message = "Press ? for the keyboard reference"

  /// The marker file. A sibling of the recents and autosave files rather
  /// than a key inside one of them: neither of those formats has a place
  /// for it, and an empty file is the whole state this needs.
  static func markerURL(inStateDirectory directory: URL) -> URL {
    directory.appendingPathComponent("first-run")
  }

  /// Claims the first run, returning `true` exactly once per state
  /// directory.
  ///
  /// The claim and the check are one call because two calls are a race:
  /// the hint must be shown by whoever created the marker, not by whoever
  /// merely saw it missing.
  ///
  /// Every failure here is silent and answers `false`. A read-only home
  /// directory is a reason to skip a nicety, not to interrupt someone who
  /// opened a drawing program.
  @discardableResult
  static func claim(inStateDirectory directory: URL) -> Bool {
    let marker = markerURL(inStateDirectory: directory)
    guard !FileManager.default.fileExists(atPath: marker.path) else {
      return false
    }
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    guard (try? Data().write(to: marker, options: .withoutOverwriting)) != nil else {
      // Somebody else got there first, or the write failed. Either way
      // this run is not the one that shows the hint.
      return false
    }
    return true
  }
}

/// Runs the first-run claim on a view node of its own.
///
/// On its own node for the same reason `AutosaveTicker` is: `EditorView`'s
/// root has exactly one `.task`, already spent on playback, and the
/// framework supports one per node. Doing the claim in `EditorView.init`
/// instead would be worse than untidy — that initializer runs on every
/// view-value construction, including the ones tests make, so the hint
/// would be spent by a test run rather than by a launch.
struct FirstRunHintView: View {
  let stateDirectory: URL
  let onFirstRun: @MainActor @Sendable () -> Void

  var body: some View {
    Text("")
      .frame(width: 0, height: 0)
      .task {
        guard FirstRunHint.claim(inStateDirectory: stateDirectory) else { return }
        onFirstRun()
      }
  }
}
