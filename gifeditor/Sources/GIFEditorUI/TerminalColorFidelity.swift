import Foundation
import SwiftTUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// How many distinct colors the terminal can actually put on screen.
///
/// SwiftTUI already degrades gracefully on its own: `TerminalCellTextRenderer`
/// emits `38;2;R;G;B` on a true-color terminal, `38;5;N` on a 256-color one and
/// the nearest of nine ANSI-16 codes below that, so *no* app has to quantize
/// anything by hand. What it does not do is tell the app which of those
/// happened, and for an image editor that difference is visible: two palette
/// slots the artist can tell apart in 24-bit land can land on the same
/// 256-color cell, and so can the two shades of the canvas's transparency
/// checkerboard.
///
/// So the editor asks the same question SwiftTUI's runner asks, through the
/// same public entry point, and spends the answer on the handful of choices
/// that stop reading when the palette shrinks. Everything else keeps using
/// plain 24-bit colors and lets the renderer do the work.
enum EditorColorFidelity: String, CaseIterable, Equatable, Sendable {
  /// 24-bit color. Every distinct `EditorColor` is a distinct cell color.
  case full
  /// The 256-color cube or less. Nearby colors collapse onto a shared cell,
  /// so the editor's own display colors have to be spread further apart and
  /// the palette grid has to say when two slots have collided.
  case reduced

  /// `.none` maps to `.full`, which reads backwards and is not: at that level
  /// the renderer emits no color escape at all, so there is no quantizer to
  /// compensate for and spreading the editor's shades apart would change
  /// nothing anyone can see. It is also what a non-TTY reports — a piped
  /// build, a test run — which is what keeps the editor from rendering one
  /// way under a terminal and another way under a redirect.
  init(_ level: TerminalCapabilityProfile.ColorLevel) {
    switch level {
    case .trueColor, .none: self = .full
    case .ansi256, .ansi16: self = .reduced
    }
  }

  /// What this process's terminal reported, resolved once.
  ///
  /// `TerminalCapabilityProfile.detect(environment:isTTY:)` is the same public
  /// function SwiftTUI's own CLI runner calls before it builds a terminal
  /// host, reading `COLORTERM`, `TERM` and `NO_COLOR`. It is not reachable
  /// from the view environment — there is no `\.terminalCapabilityProfile` —
  /// so the editor resolves it here rather than per frame. That is sound
  /// because none of those variables changes for the life of the process,
  /// and it is the reason this is a `let` and not a computed property.
  ///
  /// Anything that is not a terminal — a pipe, a test bundle, the WASI host
  /// with its own hard-coded true-color surface — reports `.none` and lands
  /// on `.full`, which is the same answer the editor gave before any of this
  /// existed.
  static let detected: EditorColorFidelity = {
    EditorColorFidelity(
      TerminalCapabilityProfile.detect(
        environment: ProcessInfo.processInfo.environment,
        isTTY: isatty(1) != 0
      ).colorLevel
    )
  }()
}

/// The 256-color cube, as SwiftTUI's terminal renderer actually walks it.
///
/// A mirror, not a reimplementation for its own sake: the code that matters
/// lives in `TerminalCellTextRenderer+ColorCodes.ansi256Code(for:)` inside
/// `SwiftTUIRuntime`, which is `internal` on an `internal` type and carries no
/// `@_spi` escape hatch, so an app cannot call it. The editor needs the answer
/// — "will these two colors reach the terminal as the same cell?" — and this
/// is the only way to have it.
///
/// Two details are load-bearing and both are copied deliberately:
///
/// * Each channel snaps to one of **six** levels, `round(component × 5)`, so
///   the axis boundaries sit at `0.1, 0.3, 0.5, 0.7, 0.9`. Two greys `0.08`
///   apart on either side of nothing land on the same level.
/// * The renderer special-cases nine named colors before it reaches the cube
///   at all, and hands them hand-picked codes (`.white` → 255, from the
///   greyscale ramp, not the cube's 231). `Color.white` and friends are plain
///   `Color` values, so a palette slot of pure white *is* `.white` by
///   equality and does take that branch.
///
/// The greyscale ramp (232…255) is unreachable through the cube path, which is
/// why dark greys collapse so readily: below `0.1` everything is code 16.
enum TerminalColorCube {
  /// The ANSI-256 code `color` is emitted as on a 256-color terminal.
  static func code(for color: Color) -> Int {
    switch color {
    case .black: return 16
    case .red: return 203
    case .green: return 114
    case .yellow: return 179
    case .blue: return 111
    case .magenta: return 176
    case .cyan: return 117
    case .white: return 255
    case .gray: return 145
    default: break
    }
    return 16 + 36 * axis(color.red) + 6 * axis(color.green) + axis(color.blue)
  }

  /// The `0...5` cube level one channel falls on.
  static func axis(_ component: Double) -> Int {
    Int((min(1, max(0, component)) * 5).rounded())
  }

  /// The six values an xterm-256 cube axis actually paints.
  static let axisValues = [0, 95, 135, 175, 215, 255]

  /// What the terminal puts on screen for an ANSI-256 code.
  ///
  /// The inverse of ``code(for:)`` far enough to answer the only question the
  /// editor asks of it: *how legible is this once the terminal has had its
  /// way with it?* A source color and its displayed color can be far apart —
  /// `Color.cyan` is `#56B6C2` in 24-bit and `#87D7FF` after the renderer
  /// pins it to code 117 — so a contrast check run against the source would
  /// be measuring a color nobody sees.
  ///
  /// Covers the whole 0…255 range: the sixteen system colors (approximated by
  /// the xterm defaults), the 6×6×6 cube, and the 24-step greyscale ramp that
  /// the cube path never reaches but `.white` → 255 does.
  static func displayedColor(forCode code: Int) -> Color {
    func color(_ r: Int, _ g: Int, _ b: Int) -> Color {
      Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
    switch code {
    case 0..<16:
      let base = [
        (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
        (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
        (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
        (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
      ][code]
      return color(base.0, base.1, base.2)
    case 16..<232:
      let index = code - 16
      return color(
        axisValues[index / 36],
        axisValues[(index % 36) / 6],
        axisValues[index % 6]
      )
    default:
      let level = 8 + 10 * (min(255, max(232, code)) - 232)
      return color(level, level, level)
    }
  }

  /// What `color` looks like once the terminal has quantized it — itself
  /// under `.full` fidelity, and its cube cell under `.reduced`.
  static func displayed(_ color: Color, fidelity: EditorColorFidelity) -> Color {
    switch fidelity {
    case .full: color
    case .reduced: displayedColor(forCode: code(for: color))
    }
  }

  /// Whether two colors survive as two colors.
  ///
  /// Under `.full` fidelity every distinct color does, so this only ever asks
  /// the cube when the cube is what the terminal will use.
  static func areDistinguishable(
    _ first: Color,
    _ second: Color,
    fidelity: EditorColorFidelity
  ) -> Bool {
    switch fidelity {
    case .full: first != second
    case .reduced: code(for: first) != code(for: second)
    }
  }
}
