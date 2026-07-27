import GIFEditorCore
import SwiftTUI

/// Pointer-travel → editor-value arithmetic for the timeline's two drag
/// affordances: the scrubbable delay readout and drag-to-reorder on the
/// thumbnail strip.
///
/// Kept as free functions on a caseless enum, separate from the views, for
/// one reason: a gesture handler is the hardest thing in a TUI to test, and
/// almost all of what could be wrong with these two gestures is arithmetic.
/// Pulling the arithmetic out leaves the view holding only the wiring.
enum TimelineDragMath {

  // MARK: - Reorder

  /// Cells a thumbnail's border adds to its rendered width — one column
  /// each side.
  static let thumbnailBorderCells = 2

  /// The gap the thumbnail `HStack` leaves between slots. The strip
  /// declares no explicit spacing, and SwiftTUI's default horizontal stack
  /// spacing is one cell.
  static let thumbnailSpacingCells = 1

  /// Cells of horizontal travel worth exactly one timeline slot.
  ///
  /// Derived from the thumbnail's own width rather than hard-coded, so a
  /// change to the thumbnail size in `EditorView` cannot silently make the
  /// drag map to the wrong frame.
  static func slotPitch(thumbnailWidth: Int) -> Int {
    max(1, thumbnailWidth + thumbnailBorderCells + thumbnailSpacingCells)
  }

  /// Which slot a frame dragged from `source` should land in.
  ///
  /// The translation is measured in the *dragged thumbnail's* own local
  /// space, not the strip's, so the result is independent of how far the
  /// strip happens to be scrolled — which a container-relative reading
  /// would get wrong the moment the timeline holds more frames than fit.
  ///
  /// Rounding (rather than truncating) means the frame swaps once the
  /// pointer passes the halfway mark between two slots, which is where the
  /// eye expects it to.
  static func reorderDestination(
    source: Int,
    translationCells: Double,
    thumbnailWidth: Int,
    frameCount: Int
  ) -> Int {
    guard frameCount > 0 else { return 0 }
    let pitch = Double(slotPitch(thumbnailWidth: thumbnailWidth))
    let slots = (translationCells / pitch).rounded()
    // `Int(exactly:)` rather than a plain conversion: a NaN or infinite
    // translation would trap the truncating initializer, and a pointer
    // sample is external input.
    guard let offset = Int(exactly: slots) else { return source }
    return min(max(source + offset, 0), frameCount - 1)
  }

  // MARK: - Delay scrub

  /// Centiseconds of frame delay per cell of horizontal travel.
  ///
  /// One. Frame delays live in the single digits and low tens, so a
  /// coarser ratio would make the readout unable to express most of its
  /// own range, and a finer one would need sub-cell pointer precision the
  /// terminal does not always have.
  static let centisecondsPerCell = 1

  /// The delay offset a scrub of `translationCells` asks for, relative to
  /// the delay the scrub started from.
  static func delayDelta(translationCells: Double) -> Int {
    guard let cells = Int(exactly: translationCells.rounded()) else { return 0 }
    return cells * centisecondsPerCell
  }
}

/// The timeline's export-metadata column: per-frame disposal on top, the
/// document-wide loop count underneath.
///
/// Split out of `TimelineView` because it is the one part of the strip that
/// describes the *exported file* rather than the frame being drawn, and
/// because the disposal control has to explain a consequence rather than
/// just report a value — see ``disposalCluster``.
///
/// ## Why the labels are as short as they are
///
/// The timeline is a fixed-height strip in a row of columns that all
/// compete for the terminal's width, and the editor has to stay usable in
/// an 80-column window. This column is the fourth such competitor, and the
/// budget left for it is small and hard: spelled out — `disp background`
/// over `loop forever ⊖ ⊕ ∞`, **18 cells** — it takes enough width off the
/// thumbnail strip that the editor stops settling at 80×24 and *every*
/// runtime test times out, not just a layout assertion. Measured: 18 cells
/// hangs, 16 settles.
///
/// So the values are abbreviated to ``widestCell`` cells and the prose
/// that explains them goes to the status line, where there is room for a
/// sentence. The margin is one cell, which is why ``widestCell`` is
/// asserted by `TimelineCompletenessTests.exportColumnStaysWithinItsWidthBudget`
/// rather than left as a comment. If you widen anything here, re-run
/// `PresentationRuntimeTests` — it renders at exactly 80×24 and is what
/// catches it.
struct TimelineExportSettingsView: View {
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void

  /// The widest either row may render, in cells. See the type doc — this
  /// is a measured ceiling, not a preference.
  static let widestCell = 16

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      disposalCluster
      loopCluster
    }
  }

  // MARK: - Disposal

  /// `disp bg`, plus a `!` when the choice has switched the export off
  /// delta coding.
  ///
  /// That warning is the point of this control existing in the strip at
  /// all. `GIFEncoder` declines to delta-code *any* document carrying an
  /// authored disposal other than `.background`, so setting one frame to
  /// `keep` silently makes every frame in the export full-canvas — a file
  /// several times larger, from a control that looks per-frame. An author
  /// is entitled to make that trade; they are not entitled to be surprised
  /// by it, so the cost is flagged next to the control that incurs it
  /// rather than left to be discovered from a byte count. The `!` is the
  /// glyph; the sentence is on the status line.
  private var disposalCluster: some View {
    HStack(spacing: 1) {
      Text("disp").foregroundStyle(.muted)
      Button {
        model.cycleCurrentFrameDisposal()
        refresh()
      } label: {
        Text(EditorViewModel.disposalCode(model.currentFrame.disposal))
          .foregroundStyle(model.currentFrame.disposal == .background ? .foreground : .warning)
      }
      .buttonStyle(.plain)
      if model.authoredDisposalDisablesDeltaCoding {
        Text("!").foregroundStyle(.warning)
      }
    }
  }

  // MARK: - Loop count

  /// `loop forever - +`.
  ///
  /// The count reads as prose — `forever` / `once` / `N×` — rather than as
  /// the raw number, because the raw number's most important value is `0`
  /// and `0` reads as "never" to everyone who has not read the GIF
  /// specification. That is the whole reason this control is worth having:
  /// the format's "zero means forever" is folklore until something says it
  /// out loud. Stepping down from `once` lands on `forever`, so the author
  /// can reach it without ever learning it is spelled zero.
  private var loopCluster: some View {
    HStack(spacing: 1) {
      Text("loop").foregroundStyle(.muted)
      Button {
        model.toggleLoopsForever()
        refresh()
      } label: {
        Text(EditorViewModel.loopCode(model.document.loopCount))
          .foregroundStyle(model.document.loopCount == 0 ? .tint : .foreground)
      }
      .buttonStyle(.plain)
      stepButton("-") { model.adjustLoopCount(by: -1) }
      stepButton("+") { model.adjustLoopCount(by: 1) }
    }
  }

  private func stepButton(
    _ glyph: String,
    action: @escaping @MainActor () -> Void
  ) -> some View {
    Button {
      action()
      refresh()
    } label: {
      Text(glyph).foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
  }
}
