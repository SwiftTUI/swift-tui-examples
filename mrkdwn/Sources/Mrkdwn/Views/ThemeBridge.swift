import SwiftTUI

extension ThemeColor {
  var swiftTUIColor: Color {
    try! Color(hex: hex)
  }
}

extension ViewerTheme {
  var terminalAppearance: TerminalAppearance {
    TerminalAppearance(
      foregroundColor: foreground.swiftTUIColor,
      backgroundColor: background.swiftTUIColor,
      tintColor: accent.swiftTUIColor,
      source: .override
    )
  }

  func headingColor(level: Int) -> Color {
    headings[min(max(level, 1), 6) - 1].swiftTUIColor
  }
}
