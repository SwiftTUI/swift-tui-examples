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

  func mermaidColor(for role: MermaidPaintRole) -> Color {
    switch role {
    case .background: mermaid.background.swiftTUIColor
    case .border: mermaid.border.swiftTUIColor
    case .text, .unknown: mermaid.text.swiftTUIColor
    case .edge: mermaid.edge.swiftTUIColor
    case .edgeLabel: mermaid.edgeLabel.swiftTUIColor
    case .title: mermaid.title.swiftTUIColor
    }
  }
}
