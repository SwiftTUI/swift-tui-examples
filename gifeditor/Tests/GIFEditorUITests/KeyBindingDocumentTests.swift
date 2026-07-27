import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// `docs/KEYBINDINGS.md` is generated, and this is what makes that claim
/// enforceable rather than aspirational.
///
/// Reads the checked-in file; writes nothing. When it fails, the fix is
/// `Scripts/generate-keybindings-doc.sh` — never a hand edit, which is
/// exactly the failure this exists to produce.
@MainActor
@Suite("GIF editor keybinding docs")
struct KeyBindingDocumentTests {
  /// The checked-in doc, located from this file rather than the working
  /// directory, which `swift test` does not promise.
  static var documentURL: URL {
    URL(fileURLWithPath: #filePath)  // …/Tests/GIFEditorUITests/<this file>
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()  // …/gifeditor
      .appendingPathComponent("docs")
      .appendingPathComponent("KEYBINDINGS.md")
  }

  @Test("the checked-in doc matches what the catalog generates")
  func checkedInDocumentMatchesTheCatalog() throws {
    let url = Self.documentURL
    #expect(
      FileManager.default.fileExists(atPath: url.path),
      "docs/KEYBINDINGS.md is missing; run Scripts/generate-keybindings-doc.sh"
    )
    let onDisk = try String(contentsOf: url, encoding: .utf8)
    let generated = KeyBindingCatalog.markdownDocument

    guard onDisk != generated else { return }

    // Name the first line that differs. A whole-file diff in a test
    // failure message is unreadable, and "they differ" is not actionable.
    let onDiskLines = onDisk.components(separatedBy: "\n")
    let generatedLines = generated.components(separatedBy: "\n")
    let firstDifference = zip(onDiskLines, generatedLines).enumerated()
      .first { $0.element.0 != $0.element.1 }
    let detail: String
    if let firstDifference {
      detail = """
        line \(firstDifference.offset + 1):
          on disk:   \(firstDifference.element.0)
          generated: \(firstDifference.element.1)
        """
    } else {
      detail =
        "the file has \(onDiskLines.count) lines; the catalog generates \(generatedLines.count)"
    }

    Issue.record(
      """
      docs/KEYBINDINGS.md has drifted from KeyBindingCatalog — \(detail)

      Run Scripts/generate-keybindings-doc.sh. The doc is generated; edit \
      the catalog, not the Markdown.
      """
    )
  }

  /// The doc says so itself, so the next person editing it is told
  /// before they get as far as a failing test.
  @Test("the checked-in doc is marked as generated")
  func checkedInDocumentCarriesTheGeneratedBanner() throws {
    let onDisk = try String(contentsOf: Self.documentURL, encoding: .utf8)
    #expect(onDisk.contains(KeyBindingCatalog.generatedFileBanner))
  }

  /// Every command reaches the doc, and reaches it under the chord the
  /// editor is bound to. The drift test above pins the file to the
  /// renderer; this pins the renderer to the catalog, so a rendering bug
  /// that dropped a whole section could not be laundered into "generated
  /// output, therefore correct".
  @Test("every catalog command appears in the generated doc")
  func generatedDocumentCoversEveryCommand() {
    let generated = KeyBindingCatalog.markdownDocument
    for entry in KeyBindingCatalog.entries {
      #expect(
        generated.contains("`\(entry.display)`"),
        "\(entry.command.rawValue): \(entry.display) is missing from the generated doc"
      )
      #expect(
        generated.contains(entry.label),
        "\(entry.command.rawValue): its label is missing from the generated doc"
      )
    }
    for section in KeyBindingCatalog.populatedSections {
      #expect(generated.contains("## \(section.title)"))
    }
  }

  /// The three things the doc was wrong about before it was generated,
  /// pinned by name.
  ///
  /// Redundant with the coverage check above only for as long as nobody
  /// edits the catalog; these are the specific regressions — a
  /// viewport section that was never written down, a palette chord added
  /// without a doc row, and a `Save` / `Save As` pair described as two
  /// spellings of one verb — and they are worth failing loudly.
  @Test("the doc describes the keys it used to omit or mis-state")
  func documentCoversThePreviouslyStaleAreas() throws {
    let onDisk = try String(contentsOf: Self.documentURL, encoding: .utf8)

    // Viewport: bare zoom keys and Alt+arrow panning.
    #expect(onDisk.contains("Zoom out one step"))
    #expect(onDisk.contains("Fit the whole canvas to the window"))
    #expect(onDisk.contains("`Alt+←`"))
    // The palette editor chord.
    #expect(onDisk.contains("`Ctrl+P`"))
    // The file lifecycle, with Save and Save As as distinct verbs.
    #expect(onDisk.contains("`Ctrl+Alt+N`"))
    #expect(onDisk.contains("`Ctrl+O`"))
    #expect(onDisk.contains("`Ctrl+E`"))
    #expect(onDisk.contains("Save As"))
    #expect(
      !onDisk.contains("Open save sheet"),
      "Ctrl+S and Alt+S are Save and Save As, not two spellings of one sheet"
    )
  }
}
