import GIFEditorCore
import SwiftTUI

/// Onion skinning: the neighbouring frames, ghosted *under* the current one.
///
/// Everything here is display state. Nothing in this file can reach the
/// document, the undo stack, a `PixelBuffer`, the eyedropper or an export —
/// the ghosts exist only as extra colors the canvas mixes into cells the
/// current frame leaves transparent, and they are resolved inside the same
/// viewport-bounded loop that resolves the real pixels.

// MARK: - Which side a ghost came from

/// Which way in the timeline a ghost lies. Two cases, unlike
/// ``OnionSkinSides``, because a *ghost* is always on exactly one side even
/// when the *setting* asks for both.
enum OnionSkinDirection: Equatable, Sendable {
  case previous
  case next
}

/// Which neighbours the canvas ghosts.
enum OnionSkinSides: String, CaseIterable, Equatable, Sendable {
  case both
  case previous
  case next

  var includesPrevious: Bool { self != .next }
  var includesNext: Bool { self != .previous }

  /// Status-strip spelling.
  var label: String {
    switch self {
    case .both: "both"
    case .previous: "prev"
    case .next: "next"
    }
  }

  /// Menu-row spelling.
  var menuLabel: String {
    switch self {
    case .both: "Both"
    case .previous: "Previous"
    case .next: "Next"
    }
  }

  /// `both` → `previous` → `next` → `both`, so one key can walk the whole
  /// setting and land back where it started.
  var cycled: OnionSkinSides {
    switch self {
    case .both: .previous
    case .previous: .next
    case .next: .both
    }
  }
}

// MARK: - Appearance

/// How a ghost is drawn.
///
/// Two cues, not one. Intensity alone is what the plan suggested, and it is
/// not enough here: the transparent-cell backdrop is already a dark neutral
/// checker (18% / 10% grey), so a dimmed ghost of a dark color lands on top of
/// a dark background and reads as "slightly different checker" — and a dimmed
/// ghost carries no information about *which* neighbour it came from. Pulling
/// the ghost's hue toward a cool tint for earlier frames and a warm one for
/// later frames is the convention every pixel editor uses, survives a
/// 256-color terminal palette, and answers both questions at once: not-current
/// (wrong hue for the artwork) and which direction (cool = behind you, warm =
/// ahead of you).
enum OnionSkinAppearance {
  /// Cool: frames already drawn.
  static let previousTint = Color(red: 0.36, green: 0.60, blue: 1.0, alpha: 1.0)
  /// Warm: frames still to come.
  static let nextTint = Color(red: 1.0, green: 0.45, blue: 0.30, alpha: 1.0)

  /// How far a ghost's hue is pulled toward its tint. High enough that a
  /// white ghost is unmistakably blue or orange, low enough that a red ghost
  /// and a green ghost still differ.
  static let tintAmount = 0.55

  /// Alpha for each distance, nearest first. Steep on purpose: the frame
  /// immediately beside the current one is the one being matched against, and
  /// the ones behind it are context.
  static let opacities: [Double] = [0.45, 0.27, 0.16]

  static func tint(for direction: OnionSkinDirection) -> Color {
    switch direction {
    case .previous: previousTint
    case .next: nextTint
    }
  }

  /// Alpha of a ghost `distance` frames away. Clamped, so a distance past the
  /// table's end fades to its last entry rather than trapping.
  static func opacity(atDistance distance: Int) -> Double {
    opacities[min(max(1, distance), opacities.count) - 1]
  }
}

// MARK: - Settings

/// The author's onion-skin choices: on/off, how many ghosts per side, and
/// which side(s).
///
/// A plain value with no reference to the document, because onion skin is a
/// view concern in exactly the way zoom is: two editors looking at the same
/// file may reasonably disagree about it, and nothing about it belongs in a
/// saved project. It lives as `@State` on `EditorView` beside
/// ``CanvasViewportState`` and the pixel-grid mode, and needs no document
/// write at all.
struct OnionSkinSettings: Equatable, Sendable {
  /// Off by default. Onion skin changes what the canvas shows, and an editor
  /// that opens showing something other than the frame you opened has to
  /// explain itself before you have learned anything else about it.
  var isEnabled: Bool = false
  /// Ghosts per side. One by default: the neighbour you are actually
  /// in-betweening, and the only one that stays legible against a
  /// terminal's palette without training.
  var depth: Int = 1
  /// Both sides by default, which is what in-betweening needs — the whole
  /// point is seeing the arc you are landing between.
  var sides: OnionSkinSides = .both

  static let minimumDepth = 1
  /// Three is where the tint stops carrying: the fourth ghost's alpha is
  /// close enough to the checker that it reads as noise.
  static let maximumDepth = 3

  mutating func toggle() {
    isEnabled.toggle()
  }

  /// Adjusting the ghost count or the ghosted side turns onion skin *on*.
  ///
  /// Neither key has any other visible effect, so the alternative is a
  /// control that silently does nothing until you find the one that makes it
  /// matter.
  mutating func increaseDepth() {
    depth = min(Self.maximumDepth, depth + 1)
    isEnabled = true
  }

  mutating func decreaseDepth() {
    depth = max(Self.minimumDepth, depth - 1)
    isEnabled = true
  }

  /// Walks `1…maximumDepth` and wraps, for the menu row — a menu item is one
  /// click, so it cannot offer a pair of `{` / `}` keys.
  mutating func cycleDepth() {
    depth = depth >= Self.maximumDepth ? Self.minimumDepth : depth + 1
    isEnabled = true
  }

  mutating func cycleSides() {
    sides = sides.cycled
    isEnabled = true
  }

  /// What the status line says after a change.
  var announcement: String {
    isEnabled ? "Onion skin on (\(sides.label) ×\(depth))" : "Onion skin off"
  }

  /// The status strip's persistent readout, or nothing when off.
  var statusLabel: String {
    isEnabled ? "onion \(sides.label)×\(depth)" : ""
  }

  /// The frames to ghost under `currentIndex`, ordered farthest → nearest so
  /// a caller can composite them in array order and end up with the nearest
  /// ghost on top.
  ///
  /// **Ghosting does not wrap.** At frame 0 there is nothing before the
  /// current frame, and at the last frame nothing after. A wrap would put the
  /// final frame under the first one at exactly the intensity a real
  /// neighbour gets, with no way to tell the two apart — so the first frame
  /// of a 30-frame animation would be drawn against content 29 frames away,
  /// which is the opposite of what onion skin is for. Documents that are not
  /// loops at all (sprite sheets, single-shot animations) would be wrong all
  /// of the time rather than some of it.
  func ghosts(around currentIndex: Int, frameCount: Int) -> [OnionSkinGhost] {
    guard isEnabled, frameCount > 1 else {
      return []
    }
    let depth = min(max(Self.minimumDepth, self.depth), Self.maximumDepth)
    var result: [OnionSkinGhost] = []
    result.reserveCapacity(depth * 2)
    for distance in stride(from: depth, through: 1, by: -1) {
      if sides.includesPrevious, currentIndex - distance >= 0 {
        result.append(
          OnionSkinGhost(
            frameIndex: currentIndex - distance,
            direction: .previous,
            distance: distance
          )
        )
      }
      if sides.includesNext, currentIndex + distance < frameCount {
        result.append(
          OnionSkinGhost(
            frameIndex: currentIndex + distance,
            direction: .next,
            distance: distance
          )
        )
      }
    }
    return result
  }

  /// The canvas-ready ghost layers for `currentIndex`.
  ///
  /// Takes already-composited frames rather than the document, so the canvas
  /// reuses `EditorViewModel.compositedFrames()`'s memoized pass instead of
  /// flattening the neighbours a second time. Adjacent frames are in that
  /// cache already — the timeline strip needs them for its thumbnails — so a
  /// ghost costs no compositing work at all.
  func ghostLayers(
    around currentIndex: Int,
    composites: [[EditorColor?]]
  ) -> [CanvasGhostLayer] {
    ghosts(around: currentIndex, frameCount: composites.count).map { ghost in
      CanvasGhostLayer(
        cells: composites[ghost.frameIndex],
        tint: OnionSkinAppearance.tint(for: ghost.direction),
        opacity: OnionSkinAppearance.opacity(atDistance: ghost.distance)
      )
    }
  }
}

/// One ghosted frame: which frame, which way, and how far.
struct OnionSkinGhost: Equatable, Sendable {
  var frameIndex: Int
  var direction: OnionSkinDirection
  /// Frames between this ghost and the current frame, counting from 1.
  var distance: Int
}

// MARK: - Canvas payload

/// A ghost as the canvas consumes it: a frame's composited colors plus the
/// appearance they are drawn with.
///
/// The canvas is handed the resolved appearance rather than the
/// ``OnionSkinGhost`` it came from, so `CanvasSurfaceView` never has to know
/// what "previous" means — it mixes colors and nothing else.
struct CanvasGhostLayer: Equatable, Sendable {
  /// Row-major composited colors of the ghosted frame, in the same extent as
  /// the canvas. Shared with the model's composite cache by value semantics,
  /// so holding one copies nothing.
  var cells: [EditorColor?]
  var tint: Color
  /// Alpha the tinted ghost is composited at.
  var opacity: Double

  /// The color one ghost pixel contributes, ready to composite over whatever
  /// is already in the cell.
  func ghostColor(for color: EditorColor) -> Color {
    color.toTerminalColor()
      .tinted(toward: tint, amount: OnionSkinAppearance.tintAmount)
      .faded(by: opacity)
  }
}

// MARK: - Commands

/// The onion-skin commands the key bindings drive.
///
/// Closures for the same reason ``CanvasViewportCommands`` is: the settings
/// live in an `EditorView` `@State`, and `EditorKeyBindings` has no business
/// knowing that.
struct OnionSkinCommands: Sendable {
  var toggle: @MainActor @Sendable () -> Void
  var cycleSides: @MainActor @Sendable () -> Void
  var increaseDepth: @MainActor @Sendable () -> Void
  var decreaseDepth: @MainActor @Sendable () -> Void

  /// No-op commands, for binding call sites with no onion skin to drive
  /// (tests and harnesses).
  static let inert = OnionSkinCommands(
    toggle: {},
    cycleSides: {},
    increaseDepth: {},
    decreaseDepth: {}
  )
}
