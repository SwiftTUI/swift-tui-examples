import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// The editor's display colors, checked against the two terminals they have
/// to survive: one whose background is not black, and one that can only show
/// 256 of them.
///
/// Every assertion here is about *what lands on screen*, not about the
/// literals in ``EditorTheme``. Under `.reduced` fidelity the two are not the
/// same thing — SwiftTUI's renderer snaps each channel to one of six levels
/// before it writes the escape sequence, so `Color.cyan` (`#56B6C2`) arrives
/// as `#87D7FF` and two greys eight percent apart arrive as one grey. So the
/// checks run through ``TerminalColorCube/displayed(_:fidelity:)`` first and
/// measure the color the artist actually sees.
@MainActor
@Suite("GIF editor theme")
struct EditorThemeTests {
  // MARK: - The quantizer mirror

  /// The cube's axis boundaries, which are the whole reason any of this is
  /// necessary. `round(component × 5)` puts them at `0.1, 0.3, 0.5, 0.7,
  /// 0.9`, and everything between two boundaries is one color.
  @Test("the cube mirrors the renderer's six levels per channel")
  func cubeAxisMatchesTheRenderer() {
    #expect(TerminalColorCube.axis(0.0) == 0)
    #expect(TerminalColorCube.axis(0.09) == 0)
    #expect(TerminalColorCube.axis(0.11) == 1)
    #expect(TerminalColorCube.axis(0.29) == 1)
    #expect(TerminalColorCube.axis(0.31) == 2)
    #expect(TerminalColorCube.axis(1.0) == 5)
    // Clamped, like the renderer's, so an out-of-gamut component cannot
    // index outside the cube.
    #expect(TerminalColorCube.axis(-1.0) == 0)
    #expect(TerminalColorCube.axis(2.0) == 5)
  }

  /// The nine colors the renderer answers before it reaches the cube at all.
  /// They matter because a palette slot of pure white *is* `Color.white` by
  /// equality, so it takes the named branch and lands on the greyscale ramp
  /// rather than the cube's corner.
  @Test("the cube honors the renderer's nine named-color short circuits")
  func cubeHonorsNamedColors() {
    #expect(TerminalColorCube.code(for: .black) == 16)
    #expect(TerminalColorCube.code(for: .white) == 255)
    #expect(TerminalColorCube.code(for: .cyan) == 117)
    #expect(TerminalColorCube.code(for: .magenta) == 176)
    // An EditorColor of pure white reaches Color.white by value, which is
    // what makes the short circuit reachable from a document at all.
    #expect(
      TerminalColorCube.code(for: EditorColor(red: 255, green: 255, blue: 255).toTerminalColor())
        == 255
    )
  }

  /// The bug this item exists to fix, pinned as a fact about the old values
  /// rather than as a memory of one.
  @Test("the pre-P2.4 checkerboard shades were the same 256-color cell")
  func theOldCheckerboardCollapsedOn256Colors() {
    #expect(
      TerminalColorCube.code(for: Color(white: 0.18))
        == TerminalColorCube.code(for: Color(white: 0.10)),
      "if these ever stop colliding the reduced-fidelity checker pair has no reason to exist"
    )
  }

  // MARK: - Fidelity

  /// Which color levels the editor compensates for, and — the part that
  /// matters for the suite itself — which one a test run reports.
  ///
  /// A `swift test` is not attached to a terminal, so
  /// `TerminalCapabilityProfile.detect` answers `.none` and the editor
  /// renders in `.full`. Without that the same suite would draw palette
  /// collision markers under a TTY and not under a pipe, which is a test
  /// suite whose result depends on how it was launched.
  @Test("only the levels that actually quantize are compensated for")
  func fidelityMapsTheColorLevels() {
    #expect(EditorColorFidelity(.trueColor) == .full)
    #expect(EditorColorFidelity(.ansi256) == .reduced)
    #expect(EditorColorFidelity(.ansi16) == .reduced)
    #expect(EditorColorFidelity(.none) == .full)
    #expect(
      EditorColorFidelity(
        TerminalCapabilityProfile.detect(environment: [:], isTTY: false).colorLevel
      ) == .full,
      "a non-terminal must resolve to the same fidelity every time this suite runs"
    )
    #expect(
      EditorColorFidelity(
        TerminalCapabilityProfile.detect(
          environment: ["TERM": "xterm-256color"],
          isTTY: true
        ).colorLevel
      ) == .reduced
    )
    #expect(
      EditorColorFidelity(
        TerminalCapabilityProfile.detect(
          environment: ["TERM": "xterm-256color", "COLORTERM": "truecolor"],
          isTTY: true
        ).colorLevel
      ) == .full
    )
  }

  // MARK: - Checkerboard

  @Test("every theme's checkerboard reaches the terminal as two colors")
  func checkerboardSurvivesEveryTerminal() {
    for theme in EditorTheme.allCombinations {
      let high = TerminalColorCube.displayed(theme.checkerHighShade, fidelity: theme.fidelity)
      let low = TerminalColorCube.displayed(theme.checkerLowShade, fidelity: theme.fidelity)
      #expect(high != low, "\(label(theme)): the checkerboard collapsed into one shade")
      // Two colors is not enough on its own — they have to differ enough to
      // read as a pattern. 1.25:1 is where the existing dark pair sits on a
      // true-color terminal (1.29:1), so this is the bar the editor already
      // cleared, held for the other three combinations.
      #expect(
        high.contrastRatio(to: low) >= 1.25,
        "\(label(theme)): checker squares are \(high.contrastRatio(to: low)):1 apart"
      )
    }
  }

  @Test("the light theme's checkerboard is light and the dark theme's is dark")
  func checkerboardFollowsTheAppearance() {
    let threshold = EditorBackgroundAppearance.lightBackgroundLuminance
    for theme in EditorTheme.allCombinations {
      let shades = [theme.checkerHighShade, theme.checkerLowShade].map {
        TerminalColorCube.displayed($0, fidelity: theme.fidelity).relativeLuminance
      }
      switch theme.appearance {
      case .light:
        #expect(
          shades.allSatisfy { $0 > threshold },
          "\(label(theme)): a dark checker on a light terminal reads as painted grey"
        )
      case .dark:
        #expect(
          shades.allSatisfy { $0 < threshold },
          "\(label(theme)): a light checker on a dark terminal reads as painted grey"
        )
      }
    }
  }

  @Test("the checkerboard parity is the one the canvas has always used")
  func checkerboardParityIsStable() {
    let theme = EditorTheme.fallback
    #expect(theme.checkerShade(atParity: true) == theme.checkerHighShade)
    #expect(theme.checkerShade(atParity: false) == theme.checkerLowShade)
  }

  // MARK: - Overlay marks

  /// Nothing the canvas draws over the artwork may disappear into the
  /// backdrop it is drawn on, in either terminal.
  ///
  /// Two floors rather than one, and the gap between them is the cube's
  /// fault: on a true-color terminal the marks clear 3:1 — WCAG's bar for a
  /// graphical object — against both checker squares. On a 256-color one the
  /// lightest available dark grey is `#5F5F5F` and the marks are pinned to
  /// hand-picked codes, so the best any pair can manage is a little over
  /// 2:1. That is still plainly a different tone for a solid block glyph,
  /// and it is the most the palette has.
  @Test("no overlay mark vanishes into the checkerboard")
  func overlayMarksReadAgainstTheCheckerboard() {
    for theme in EditorTheme.allCombinations {
      let floor = theme.fidelity == .full ? 3.0 : 2.0
      let squares = [
        ("high", TerminalColorCube.displayed(theme.checkerHighShade, fidelity: theme.fidelity)),
        ("low", TerminalColorCube.displayed(theme.checkerLowShade, fidelity: theme.fidelity)),
      ]
      for (name, color) in theme.overlayMarks {
        let displayed = TerminalColorCube.displayed(color, fidelity: theme.fidelity)
        for (squareName, square) in squares {
          let ratio = displayed.contrastRatio(to: square)
          #expect(
            ratio >= floor,
            "\(label(theme)): \(name) is \(ratio):1 against the \(squareName) checker square"
          )
        }
      }
    }
  }

  @Test("the overlay marks stay distinct from one another")
  func overlayMarksStayDistinct() {
    for theme in EditorTheme.allCombinations {
      let marks = theme.overlayMarks
      for first in marks.indices {
        for second in marks.indices where second > first {
          #expect(
            TerminalColorCube.areDistinguishable(
              marks[first].color,
              marks[second].color,
              fidelity: theme.fidelity
            ),
            "\(label(theme)): \(marks[first].name) and \(marks[second].name) are one color"
          )
        }
      }
    }
  }

  // MARK: - Onion skin

  @Test("cool and warm onion tints stay apart in every terminal")
  func onionTintsStayApart() {
    for theme in EditorTheme.allCombinations {
      #expect(
        TerminalColorCube.areDistinguishable(
          theme.onionTint(for: .previous),
          theme.onionTint(for: .next),
          fidelity: theme.fidelity
        ),
        "\(label(theme)): the cool and warm ghosts are the same color"
      )
      // Cool is cooler and warm is warmer, whatever the appearance did to
      // the two literals — the convention is the information.
      let previous = theme.onionTint(for: .previous)
      let next = theme.onionTint(for: .next)
      #expect(previous.blue > previous.red, "\(label(theme)): the previous tint is not cool")
      #expect(next.red > next.blue, "\(label(theme)): the next tint is not warm")
    }
  }

  @Test("a ghost is still visible against its own theme's checkerboard")
  func ghostsReadAgainstTheCheckerboard() {
    // Mid-grey artwork is the worst case: it carries the least of its own
    // hue into the tint, so what is left is the tint and the fade.
    let artwork = EditorColor(red: 128, green: 128, blue: 128)
    for theme in EditorTheme.allCombinations {
      for direction in [OnionSkinDirection.previous, .next] {
        let layer = CanvasGhostLayer(
          cells: [],
          tint: theme.onionTint(for: direction),
          opacity: OnionSkinAppearance.opacity(atDistance: 1)
        )
        for shade in [theme.checkerHighShade, theme.checkerLowShade] {
          let composited = layer.ghostColor(for: artwork).composited(over: shade)
          #expect(
            TerminalColorCube.areDistinguishable(
              composited,
              shade,
              fidelity: theme.fidelity
            ),
            "\(label(theme)): a \(direction) ghost is invisible on the checkerboard"
          )
        }
      }
    }
  }

  // MARK: - Background appearance

  @Test("the appearance follows the terminal's real background color")
  func appearanceFollowsTheTerminalBackground() {
    #expect(EditorBackgroundAppearance(terminalBackground: .black) == .dark)
    #expect(EditorBackgroundAppearance(terminalBackground: .white) == .light)
    // SwiftTUI's own fallback, which is what a terminal that answers no
    // query and sets no COLORFGBG gets — the editor must keep drawing what
    // it always drew there.
    #expect(EditorBackgroundAppearance(TerminalAppearance.fallback) == .dark)
    // The split is the luminance at which black ink starts out-contrasting
    // white ink, so the appearance and `legibleInk` can never disagree.
    let threshold = EditorBackgroundAppearance.lightBackgroundLuminance
    for level in stride(from: 0.0, through: 1.0, by: 0.02) {
      let background = Color(white: level)
      let appearance = EditorBackgroundAppearance(terminalBackground: background)
      let expected: EditorBackgroundAppearance =
        background.relativeLuminance >= threshold ? .light : .dark
      #expect(appearance == expected)
      #expect(
        (background.legibleInk == .black) == (appearance == .light),
        "the ink and the appearance disagreed at white=\(level)"
      )
    }
  }

  @Test("the fallback theme is what the editor drew before there was a theme")
  func fallbackThemeIsTheOldBehavior() {
    #expect(EditorTheme.fallback.appearance == .dark)
    #expect(EditorTheme.fallback.fidelity == .full)
    #expect(EditorTheme.fallback.checkerHighShade == Color(white: 0.18))
    #expect(EditorTheme.fallback.checkerLowShade == Color(white: 0.10))
    #expect(EditorTheme.fallback.cursorColor == .cyan)
    #expect(EditorTheme.fallback.selectionColor == .blue)
    #expect(EditorTheme.fallback.onionTint(for: .previous) == OnionSkinAppearance.previousTint)
    #expect(EditorTheme.fallback.onionTint(for: .next) == OnionSkinAppearance.nextTint)
  }

  private func label(_ theme: EditorTheme) -> String {
    "\(theme.appearance.rawValue)/\(theme.fidelity.rawValue)"
  }
}

/// The palette grid, on a terminal that cannot show every slot the artist
/// picked.
@MainActor
@Suite("GIF editor palette legibility")
struct PaletteLegibilityTests {
  /// Two slots a fifth of the range apart are one color on a 256-color
  /// terminal. The grid cannot move them, so it has to say so.
  @Test("adjacent slots that collapse to one cell color are marked")
  func collapsedSlotsAreMarked() {
    let view = paletteView(
      colors: [
        1: EditorColor(red: 40, green: 40, blue: 40),
        // 0x28 -> 0x2E is well inside one cube level: both land on level 1.
        2: EditorColor(red: 46, green: 46, blue: 46),
        // Two levels apart, so this one is genuinely a different cell.
        3: EditorColor(red: 200, green: 40, blue: 40),
      ],
      fidelity: .reduced
    )

    #expect(
      !TerminalColorCube.areDistinguishable(
        view.palette[1].toTerminalColor(),
        view.palette[2].toTerminalColor(),
        fidelity: .reduced
      ),
      "the fixture must actually collide, or the check below is vacuous"
    )
    #expect(view.collidesWithNeighbour(2))
    #expect(!view.collidesWithNeighbour(3))
  }

  @Test("no slot is marked on a true-color terminal")
  func fullFidelityNeverMarks() {
    let view = paletteView(
      colors: [
        1: EditorColor(red: 40, green: 40, blue: 40),
        2: EditorColor(red: 46, green: 46, blue: 46),
      ],
      fidelity: .full
    )
    #expect(!view.collidesWithNeighbour(2))
  }

  /// The first column has no swatch to its left, so it answers to the one
  /// above it — the other neighbour a reader's eye actually compares against.
  @Test("the first column compares against the row above it")
  func firstColumnLooksUp() {
    var colors: [Int: EditorColor] = [:]
    for slot in 0..<16 {
      colors[slot] = EditorColor(red: UInt8(slot * 16), green: 0, blue: 0)
    }
    // Slot 8 is the first column of row two; make it match slot 0 exactly.
    colors[8] = colors[0]
    let view = paletteView(colors: colors, fidelity: .reduced)
    #expect(view.collidesWithNeighbour(8))
  }

  /// The marker only ever appears where nothing else is already drawing the
  /// boundary — a slot wearing `P` or `S` is told apart by that.
  @Test("the collision marker renders, and yields to the P/S markers")
  func markerRendersAndYields() {
    let colliding = paletteView(
      colors: [1: EditorColor(red: 40, green: 40, blue: 40)],
      fidelity: .reduced,
      primary: 5,
      secondary: 6
    )
    let text = render(colliding, width: 28, height: 6)
    #expect(
      text.contains(String(PaletteView.collisionMarker)),
      "a palette full of collisions drew no marker at all"
    )
    // P and S still win their own cells.
    #expect(text.contains("P"))
    #expect(text.contains("S"))

    let full = paletteView(
      colors: [1: EditorColor(red: 40, green: 40, blue: 40)],
      fidelity: .full,
      primary: 5,
      secondary: 6
    )
    #expect(
      !render(full, width: 28, height: 6).contains(String(PaletteView.collisionMarker)),
      "a true-color terminal got collision markers it does not need"
    )
  }

  /// The marker replaces a blank cell rather than claiming a new one, so the
  /// grid is the same width with it as without.
  @Test("marking a collision costs the palette grid no columns")
  func markerCostsNoWidth() {
    let plain = render(
      paletteView(colors: [:], fidelity: .full),
      width: 28,
      height: 6
    )
    let marked = render(
      paletteView(colors: [:], fidelity: .reduced),
      width: 28,
      height: 6
    )
    #expect(widestLine(plain) == widestLine(marked))
    #expect(widestLine(marked) <= 28)
  }

  // MARK: - Fixtures

  private func paletteView(
    colors: [Int: EditorColor],
    fidelity: EditorColorFidelity,
    primary: PaletteIndex = 1,
    secondary: PaletteIndex = 2
  ) -> PaletteView {
    var palette = GIFDocument.blank(size: .init(width: 4, height: 4)).palette
    for (slot, color) in colors {
      palette[PaletteIndex(slot)] = color
    }
    let model = EditingSession(
      document: GIFDocument.blank(size: .init(width: 4, height: 4))
    )
    return PaletteView(
      palette: palette,
      primaryIndex: primary,
      secondaryIndex: secondary,
      model: model,
      refresh: {},
      fidelity: fidelity
    )
  }

  private func widestLine(_ text: String) -> Int {
    text.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
  }

  private func render(
    _ view: some View,
    width: Int,
    height: Int,
    id: String = #function
  ) -> String {
    var environment = EnvironmentValues()
    environment.terminalSize = CellSize(width: width, height: height)
    return DefaultRenderer().render(
      view,
      context: ResolveContext(
        identity: Identity(components: ["gifeditor.palette.legibility.\(id)"]),
        environmentValues: environment
      ),
      proposal: ProposedSize(width: width, height: height)
    ).rasterSurface.lines.joined(separator: "\n")
  }

  /// A directory no test writes to — it exists so constructing a view model
  /// cannot read the developer's real `~/.config/halfcell/` recents list.
  private static let throwawayStateDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-palette-legibility-\(UUID().uuidString)")
}
