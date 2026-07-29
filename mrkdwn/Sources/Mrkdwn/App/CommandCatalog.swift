public import SwiftTUI

struct ViewerCommandDescription: Equatable, Sendable {
  var keys: String
  var title: String
}

public enum CommandCatalog {
  static let entries: [ViewerCommandDescription] = [
    .init(keys: "j / k · ↑ / ↓", title: "Scroll one line"),
    .init(keys: "PgDn / PgUp · Space", title: "Scroll one page"),
    .init(keys: "g / G · Home / End", title: "Jump to top or bottom"),
    .init(keys: "] / [", title: "Next or previous heading"),
    .init(keys: "t", title: "Toggle table of contents"),
    .init(keys: "/", title: "Search document"),
    .init(keys: "n / N", title: "Next or previous match"),
    .init(keys: "b / f", title: "Back or forward document"),
    .init(keys: "r", title: "Reload document and theme"),
    .init(keys: "m / Alt-M", title: "Toggle focused / reveal next Mermaid source"),
    .init(keys: "?", title: "Toggle this help"),
    .init(keys: "q / Control-C", title: "Quit"),
  ]

  public static let runtimeExitKeys: [KeyPress] = [
    KeyPress(.character("q")),
    KeyPress(.character("c"), modifiers: .ctrl),
  ]
}
