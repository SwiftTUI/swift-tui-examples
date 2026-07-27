/// Renders `KeyBindingCatalog` as the Markdown that lives at
/// `docs/KEYBINDINGS.md`.
///
/// Two callers, and they must agree exactly: the generator script writes
/// this string to the file, and `KeyBindingDocumentTests` compares the
/// checked-in file against it. A hand-edit to the doc therefore fails the
/// suite, which is the only reason the doc can be trusted to describe the
/// binary rather than whatever was true when someone last remembered.
///
/// Like `KeyBindingCatalog.swift` this file imports nothing, so
/// `Scripts/generate-keybindings-doc.sh` can compile the pair on their
/// own.
extension KeyBindingCatalog {
  /// Warns the next person off editing the file by hand. Also the string
  /// the drift test points at when it fails.
  static let generatedFileBanner =
    "<!-- Generated from Sources/GIFEditorUI/KeyBindingCatalog.swift by "
    + "Scripts/generate-keybindings-doc.sh. Do not edit by hand. -->"

  /// The whole of `docs/KEYBINDINGS.md`, ending in exactly one newline.
  static var markdownDocument: String {
    var lines: [String] = [
      "# gifeditor keybindings",
      "",
      generatedFileBanner,
      "",
      "Focused editor commands use bare keys where they map to ordinary pixel-editor",
      "actions. Press `?` in the editor for the same table without leaving the",
      "terminal.",
      "",
      "The bindings avoid terminal-ambiguous chords such as `Ctrl+Shift+letter`,",
      "`Ctrl+digit`, `Ctrl+[` / `Ctrl+]`, and `Alt+[`, because the current terminal",
      "input path does not receive those as distinct key presses.",
    ]

    for section in populatedSections {
      lines.append("")
      lines.append("## \(section.title)")
      lines.append("")
      lines.append(contentsOf: table(for: section))
      for note in section.notes {
        lines.append("")
        lines.append(contentsOf: wrap(note, width: 79))
      }
    }

    return lines.joined(separator: "\n") + "\n"
  }

  /// A GitHub-flavoured table with padded columns, so the raw file reads
  /// as well as the rendered one.
  private static func table(for section: KeyBindingSection) -> [String] {
    let rows = entries(in: section).map { ("`\($0.display)`", $0.label) }
    let shortcutWidth = max("Shortcut".count, rows.map(\.0.count).max() ?? 0)
    let actionWidth = max("Action".count, rows.map(\.1.count).max() ?? 0)

    func row(_ shortcut: String, _ action: String) -> String {
      "| " + pad(shortcut, to: shortcutWidth) + " | " + pad(action, to: actionWidth) + " |"
    }

    var lines = [
      row("Shortcut", "Action"),
      "| " + String(repeating: "-", count: shortcutWidth)
        + " | " + String(repeating: "-", count: actionWidth) + " |",
    ]
    lines.append(contentsOf: rows.map(row))
    return lines
  }

  private static func pad(_ text: String, to width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
  }

  /// Greedy word wrap. The notes are authored as one long line in the
  /// catalog so their source stays readable; the doc wants prose that
  /// fits the same margin the rest of the repo's Markdown uses.
  private static func wrap(_ text: String, width: Int) -> [String] {
    var lines: [String] = []
    var current = ""
    for word in text.split(separator: " ", omittingEmptySubsequences: true) {
      if current.isEmpty {
        current = String(word)
      } else if current.count + 1 + word.count <= width {
        current += " " + word
      } else {
        lines.append(current)
        current = String(word)
      }
    }
    if !current.isEmpty {
      lines.append(current)
    }
    return lines
  }
}
