import GIFEditorCore
import SwiftTUI

/// Bottom-strip timeline. Renders the playback / navigation cluster,
/// a horizontally-scrolling row of clickable frame
/// thumbnails (the active frame is wrapped in `[ ]` and tinted),
/// frame operations (`＋ ⎘ ✕`), a delay readout / stepper
/// (`⊖ ⊕`) plus an `=all` equalize button, and the export-metadata
/// column (`TimelineExportSettingsView`).
///
/// Every visible affordance is a `.plain`-styled `Button` that calls
/// the same model method as its keyboard shortcut, so users can drive
/// the timeline entirely via mouse, entirely via keyboard, or any
/// mix.
///
/// Two affordances are drags rather than buttons, because both are
/// continuous values a stepper expresses badly: the delay readout scrubs
/// horizontally, and a thumbnail can be dragged along the strip to
/// reorder it. Both map pointer travel to a value through
/// ``TimelineDragMath``, which is where that arithmetic is tested.
struct TimelineView: View {
  let frames: [TimelineFrame]
  let currentFrameIndex: Int
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      VStack {
        Text("Frames").foregroundStyle(.muted)
        navigationCluster
      }
      ScrollView(.horizontal) {
        HStack {
          ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
            thumbnail(frame: frame, index: index)
          }
        }
      }
      .focusable(false)
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack {
        frameOperations
        delayCluster
      }
      TimelineExportSettingsView(model: model, refresh: refresh)
    }
    .padding(.horizontal, 1)
    .frame(maxWidth: .infinity, alignment: .leading)
    .border(.separator, set: .single)
  }

  // MARK: - Navigation cluster (◀◀ ◀ ▶ ▶▶)

  private var navigationCluster: some View {
    HStack(spacing: 1) {
      playbackButton
      navButton("◀◀", action: model.goToFirstFrame)
      navButton("◀", action: model.previousFrame)
      navButton("▶", action: model.nextFrame)
      navButton("▶▶", action: model.goToLastFrame)
    }
  }

  private var playbackButton: some View {
    Button {
      model.togglePlayback()
      refresh()
    } label: {
      Text(model.isPlaybackActive ? "pause" : "play")
        .foregroundStyle(model.isPlaybackActive ? .tint : .muted)
    }
    .buttonStyle(.plain)
    .disabled(frames.count < 2)
  }

  private func navButton(
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

  // MARK: - Frame operations (＋ ⎘ ✕)

  private var frameOperations: some View {
    HStack(spacing: 1) {
      navButton("＋", action: model.insertBlankFrameAfterCurrent)
      navButton("⎘", action: model.duplicateCurrentFrame)
      navButton("✕", action: model.deleteCurrentFrame)
    }
  }

  // MARK: - Delay cluster (delay XXcs ⊖ ⊕ =all)

  private var delayCluster: some View {
    HStack(spacing: 1) {
      Text("delay").foregroundStyle(.muted)
      delayReadout
      navButton("-") { model.adjustCurrentFrameDelay(by: -10) }
      navButton("+") { model.adjustCurrentFrameDelay(by: 10) }
      Button {
        model.setAllFrameDelaysToCurrent()
        refresh()
      } label: {
        Text("=all").foregroundStyle(.muted)
      }
      .buttonStyle(.plain)
    }
  }

  /// The delay, scrubbable by dragging horizontally across it.
  ///
  /// The whole drag is one undo step: `beginDelayScrub()` opens an undo
  /// group that `endDelayScrub()` closes, so an author who drags twenty
  /// cells presses undo once rather than twenty times. `beginDelayScrub()`
  /// is idempotent, which is what lets both callbacks open the scrub
  /// without the handler having to track whether the drag has started —
  /// including the case where a drag ends without ever reporting a change.
  private var delayReadout: some View {
    Text("\(currentDelay) cs")
      .foregroundStyle(model.isScrubbingDelay ? .tint : .foreground)
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
          .onChanged { value in
            model.beginDelayScrub()
            model.updateDelayScrub(
              by: TimelineDragMath.delayDelta(translationCells: value.translation.dx)
            )
            refresh()
          }
          .onEnded { value in
            model.beginDelayScrub()
            model.updateDelayScrub(
              by: TimelineDragMath.delayDelta(translationCells: value.translation.dx)
            )
            model.endDelayScrub()
            refresh()
          }
      )
  }

  private var currentDelay: Int {
    guard frames.indices.contains(currentFrameIndex) else { return 0 }
    return frames[currentFrameIndex].delayCentiseconds
  }

  // MARK: - Thumbnails

  /// One frame slot: a click target that selects, and a drag that reorders.
  ///
  /// The drag is a `simultaneousGesture` so it composes with the button
  /// rather than replacing it — a click still selects the frame. The
  /// reorder is committed only on `.onEnded`, and only when the pointer
  /// travelled far enough to name a different slot, so a click (whose
  /// translation is zero) resolves to `index` and takes
  /// ``EditorViewModel/moveCurrentFrame(by:)``'s no-op branch. That is
  /// what keeps a plain click from recording an empty undo step.
  private func thumbnail(frame: TimelineFrame, index: Int) -> some View {
    let active = index == currentFrameIndex
    let pixels = frame.thumbnail.pixels.map { $0?.toTerminalColor() }
    return Button {
      model.selectFrame(at: index)
      refresh()
    } label: {
      Canvas.pixelGrid(
        width: frame.thumbnail.width,
        height: frame.thumbnail.height,
        pixels: pixels,
        mode: .verticalHalfBlock
      )
      .border(active ? .tint : .separator, set: .rounded)
      // .overlay(alignment: .bottomTrailing) {
      //   Text(active ? "[\(index + 1)]" : "\(index + 1)")
      //     .foregroundStyle(active ? .tint : .muted)
      //     .background(.clear)
      // }
    }
    .buttonStyle(.plain)
    .simultaneousGesture(
      DragGesture(minimumDistance: 1, coordinateSpace: .local)
        .onEnded { value in
          let destination = TimelineDragMath.reorderDestination(
            source: index,
            translationCells: value.translation.dx,
            thumbnailWidth: frame.thumbnail.width,
            frameCount: frames.count
          )
          guard destination != index else { return }
          model.moveFrame(from: index, to: destination)
          refresh()
        }
    )
  }
}

/// Pre-flattened thumbnail data passed in from the parent so this view
/// doesn't need to depend on the document/view-model directly.
public struct TimelineFrame: Equatable {
  public let thumbnail: Thumbnail
  public let delayCentiseconds: Int

  public init(thumbnail: Thumbnail, delayCentiseconds: Int) {
    self.thumbnail = thumbnail
    self.delayCentiseconds = delayCentiseconds
  }

  public struct Thumbnail: Equatable {
    public let width: Int
    public let height: Int
    public let pixels: [EditorColor?]

    public init(width: Int, height: Int, pixels: [EditorColor?]) {
      precondition(pixels.count == width * height)
      self.width = width
      self.height = height
      self.pixels = pixels
    }
  }
}
