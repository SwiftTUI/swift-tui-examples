import SwiftTUI

/// Whether the terminal the editor is drawing into is dark-on-light or
/// light-on-dark.
///
/// Not a preference and not a guess: SwiftTUI asks the terminal itself. Its
/// host sends an `OSC 11` background-color query at raw-mode entry, falls back
/// to the `COLORFGBG` convention, and finally to a dark default, then publishes
/// the answer as `EnvironmentValues.terminalAppearance`. So the editor reads a
/// real background color and decides from that, rather than shipping a
/// light-mode switch nobody would find.
enum EditorBackgroundAppearance: String, CaseIterable, Equatable, Sendable {
  case dark
  case light

  /// The luminance at which black ink starts beating white ink.
  ///
  /// Solving `(1.05)/(L + 0.05) = (L + 0.05)/0.05` — the point where WCAG
  /// contrast against white equals contrast against black — gives
  /// `L = √0.0525 − 0.05 ≈ 0.1791`. Above it a background wants dark marks on
  /// it, which is exactly the question "is this a light terminal?" asks. It is
  /// also the crossover `Color.accessibleTextColor(light:dark:)` uses, so the
  /// appearance and the ink the editor picks can never disagree.
  static let lightBackgroundLuminance = 0.1791

  init(terminalBackground: Color) {
    self =
      terminalBackground.relativeLuminance >= Self.lightBackgroundLuminance ? .light : .dark
  }

  init(_ appearance: TerminalAppearance) {
    self.init(terminalBackground: appearance.backgroundColor)
  }
}

/// Every display-only color the editor picks for itself, resolved against the
/// terminal it is actually running in.
///
/// Two axes, and they answer different failures:
///
/// * ``EditorBackgroundAppearance`` — the transparency checkerboard, the
///   cursor, the selection outline and the onion-skin tints were all chosen
///   against a dark terminal. On a light one the dark checkerboard stops
///   reading as "nothing is here" and starts reading as painted grey, and the
///   pale marks laid over it wash out.
/// * ``EditorColorFidelity`` — on a 256-color terminal the two checkerboard
///   shades used to land on the *same* cube cell (`0.18` and `0.10` both
///   round to level 1), so the checkerboard vanished into a flat block. The
///   reduced palette gets a pair that is deliberately one cube level apart.
///
/// Nothing here reaches the document. These are the colors the canvas paints
/// *around* the artwork, and every one of them is recomputed from the
/// environment on the frame the terminal's appearance changes.
struct EditorTheme: Equatable, Sendable {
  let appearance: EditorBackgroundAppearance
  let fidelity: EditorColorFidelity

  init(appearance: EditorBackgroundAppearance, fidelity: EditorColorFidelity) {
    self.appearance = appearance
    self.fidelity = fidelity
  }

  /// What a caller with no environment to read gets: the dark, full-color
  /// editor, which is what every build before this one drew unconditionally.
  static let fallback = EditorTheme(appearance: .dark, fidelity: .full)

  // MARK: - Transparency checkerboard

  /// The lighter of the two checker squares.
  ///
  /// The dark pair is left exactly where it was under `.full` fidelity —
  /// there was nothing wrong with `0.18` / `0.10` on a true-color terminal.
  /// Under `.reduced` those two values are the *same* cube cell (both round
  /// to level 1) and the checkerboard collapses into a flat grey block, so
  /// the reduced pair straddles levels 1 and 0 instead: `0.20` and `0.04`.
  /// One level apart is the closest two colors can be and still be two, and
  /// levels 0/1 rather than 1/2 because the cube's second level is `#5F5F5F`
  /// — light enough that the cursor and selection marks laid over it start
  /// to lose contrast, which is the failure this whole exercise is about.
  ///
  /// The light pair does not need a second spelling: `0.92` and `0.80` land
  /// on levels 5 and 4 already, so the same two numbers survive both
  /// fidelities.
  var checkerHighShade: Color {
    switch (appearance, fidelity) {
    case (.dark, .full): Color(white: 0.18)
    case (.dark, .reduced): Color(white: 0.20)
    case (.light, _): Color(white: 0.92)
    }
  }

  /// The darker of the two checker squares.
  var checkerLowShade: Color {
    switch (appearance, fidelity) {
    case (.dark, .full): Color(white: 0.10)
    case (.dark, .reduced): Color(white: 0.04)
    case (.light, _): Color(white: 0.80)
    }
  }

  /// The checker square at a logical cell, keyed on `(x + y)` parity the way
  /// the canvas has always keyed it.
  func checkerShade(atParity parityIsEven: Bool) -> Color {
    parityIsEven ? checkerHighShade : checkerLowShade
  }

  // MARK: - Canvas overlay marks

  /// The cursor mark. Cyan on dark; a deep teal on light, because the pale
  /// cyan disappears against a near-white checker.
  var cursorColor: Color {
    switch appearance {
    case .dark: .cyan
    case .light: Color(red: 0.055, green: 0.431, blue: 0.478)
    }
  }

  /// The marquee selection outline.
  var selectionColor: Color {
    switch appearance {
    case .dark: .blue
    case .light: Color(red: 0.082, green: 0.329, blue: 0.753)
    }
  }

  /// The pending marquee anchor — the first corner, before the second lands.
  var marqueeAnchorColor: Color {
    switch appearance {
    case .dark: .yellow
    case .light: Color(red: 0.541, green: 0.353, blue: 0.0)
    }
  }

  /// The pending gradient anchor.
  var gradientAnchorColor: Color {
    switch appearance {
    case .dark: .green
    case .light: Color(red: 0.106, green: 0.420, blue: 0.200)
    }
  }

  // MARK: - Onion skin

  /// Cool: frames already drawn. Deepened on a light terminal, where the pale
  /// blue tint fades into the checker instead of standing off it.
  var onionPreviousTint: Color {
    switch appearance {
    case .dark: OnionSkinAppearance.previousTint
    case .light: Color(red: 0.12, green: 0.35, blue: 0.85)
    }
  }

  /// Warm: frames still to come.
  var onionNextTint: Color {
    switch appearance {
    case .dark: OnionSkinAppearance.nextTint
    case .light: Color(red: 0.85, green: 0.28, blue: 0.06)
    }
  }

  func onionTint(for direction: OnionSkinDirection) -> Color {
    switch direction {
    case .previous: onionPreviousTint
    case .next: onionNextTint
    }
  }

  // MARK: - Enumeration, for the tests that pin the theme's promises

  /// Every mark the canvas draws over the artwork, paired with a name.
  ///
  /// Exists so the contrast and distinguishability checks can walk the whole
  /// set instead of naming five colors and quietly missing the sixth one
  /// somebody adds later.
  var overlayMarks: [(name: String, color: Color)] {
    [
      ("cursor", cursorColor),
      ("selection", selectionColor),
      ("marquee anchor", marqueeAnchorColor),
      ("gradient anchor", gradientAnchorColor),
    ]
  }

  /// Every combination the editor can find itself in.
  static let allCombinations: [EditorTheme] = EditorBackgroundAppearance.allCases.flatMap {
    appearance in
    EditorColorFidelity.allCases.map { EditorTheme(appearance: appearance, fidelity: $0) }
  }
}
