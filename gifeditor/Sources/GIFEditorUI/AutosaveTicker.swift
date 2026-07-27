import Foundation
import SwiftTUI

/// The autosave clock, on a view node of its own.
///
/// This view exists for one structural reason. The framework supports
/// exactly **one `.task` per view node** — the multi-`.task` work was
/// implemented, found to hang a tab-hosted `PhaseAnimator`, and reverted
/// — and `EditorView`'s root has already spent its one on playback
/// (`.task(id: model.isPlaybackActive)`). Stacking the autosave timer
/// there would put two tasks on one node, which is the shape that does
/// not work. The save sheet solves the same problem the same way, by
/// splitting its preview task and its animation task across two views.
///
/// So the timer gets a node. The view renders nothing and occupies no
/// cells; it is a place for a `.task` to live, and its whole contract is
/// that `onTick` runs on the main actor every `interval` until the
/// editor goes away.
///
/// `interval` is a parameter rather than a constant so a test can run
/// the real timer at a millisecond scale instead of waiting out a
/// production interval or reaching past the view to call the callback
/// directly — which would test the callback and not the node.
struct AutosaveTicker: View {
  let interval: Duration
  let onTick: @MainActor @Sendable () -> Void

  /// The production cadence. Long enough that a full-canvas snapshot is
  /// never a visible cost, short enough that a crash costs a minute of
  /// drawing rather than a session of it.
  static let defaultInterval: Duration = .seconds(20)

  var body: some View {
    Text("")
      .frame(width: 0, height: 0)
      .task(id: interval) { @MainActor in
        // No `guard isDirty` here: what counts as work worth saving is
        // the model's judgement, and asking it on every tick keeps this
        // view a clock and nothing else.
        while !Task.isCancelled {
          try? await Task.sleep(for: interval)
          guard !Task.isCancelled else { return }
          onTick()
        }
      }
  }
}
