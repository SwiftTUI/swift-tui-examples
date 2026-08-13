import SwiftTUI
import Testing

@testable import GalleryDemoViews

/// The A5 cell-for-cell equivalence battery (control-style plan
/// 2026-08-12-002).
///
/// These surfaces are captured against the **pre-migration** gallery
/// palette. When the gallery's `CommandPaletteList` moves into SwiftTUI as
/// the internal default rendering, the same fixtures must reproduce them
/// byte-for-byte — that is what "cell-for-cell equivalent" has to mean to
/// be a measurement rather than a claim.
///
/// The fixtures drive the *declaration* path (`paletteCommand(...)`
/// contributions absorbed by `paletteSheet(...)`) rather than constructing
/// `CommandPaletteList` directly, for two reasons: `ActivePaletteCommand`
/// has a `package` initializer, so a test outside the framework cannot
/// synthesise a command list at all; and the contribution side survives A5
/// untouched, so only the declaration line changes across the migration
/// (content closure → contentless) while every assertion below stays put.
@MainActor
@Suite("Command palette equivalence")
struct CommandPaletteEquivalenceTests {
  private static func render(_ view: some View, width: Int, height: Int) -> String {
    var environment = EnvironmentValues()
    environment.terminalSize = .init(width: width, height: height)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: Identity(components: ["PaletteEquivalence"]),
        environmentValues: environment
      ),
      proposal: .init(width: .finite(width), height: .finite(height))
    )
    var lines = artifacts.rasterSurface.lines.map { line -> String in
      var trimmed = Substring(line)
      while trimmed.last == " " { trimmed.removeLast() }
      return String(trimmed)
    }
    while lines.last?.isEmpty == true { lines.removeLast() }
    return lines.joined(separator: "\n")
  }

  /// No contributions at all — the "no commands" message.
  private struct EmptyScope: View {
    var body: some View {
      Panel(id: "palette-host") { Text("base") }
        .paletteSheet("Commands", isPresented: .constant(true)) { active in
          CommandPaletteList(commands: active, dismiss: {})
        }
    }
  }

  /// A described command, a bare command, and a disabled one.
  private struct MixedScope: View {
    var body: some View {
      Panel(id: "palette-host") { Text("base") }
        .paletteCommand(
          name: "Open Counter",
          description: "Jump to the counter tab",
          action: {}
        )
        .paletteCommand(name: "Open Todo", action: {})
        .paletteCommand(name: "Disabled Command", isEnabled: false, action: {})
        .paletteSheet("Commands", isPresented: .constant(true)) { active in
          CommandPaletteList(commands: active, dismiss: {})
        }
    }
  }

  /// Two commands sharing a label, distinguished only by description.
  private struct DuplicateLabelScope: View {
    var body: some View {
      Panel(id: "palette-host") { Text("base") }
        .paletteCommand(name: "Open", description: "first", action: {})
        .paletteCommand(name: "Open", description: "second", action: {})
        .paletteSheet("Commands", isPresented: .constant(true)) { active in
          CommandPaletteList(commands: active, dismiss: {})
        }
    }
  }

  private static let emptyScopeSurface = """


      ╭──────────────────────────────────────────────────────╮
      │Filter commands…                                      │
      ╰──────────────────────────────────────────────────────╯
      ────────────────────────────────────────────────────────

      No commands in the current scope.











    ────────────────────────────────────────────────────────────
    """

  private static let mixedScopeSurface = """


      ╭──────────────────────────────────────────────────────╮
      │Filter commands…                                      │
      ╰──────────────────────────────────────────────────────╯
      ────────────────────────────────────────────────────────
       > Open Counter                  Jump to the counter tab
         Open Todo
         Disabled Command










    ────────────────────────────────────────────────────────────
    """

  private static let duplicateLabelSurface = """


      ╭──────────────────────────────────────────────────────╮
      │Filter commands…                                      │
      ╰──────────────────────────────────────────────────────╯
      ────────────────────────────────────────────────────────
       > Open                                            first
         Open                                           second











    ────────────────────────────────────────────────────────────
    """

  private static let narrowSurface = """


      ╭───────────────────────────
      │Filter commands…
      ╰───────────────────────────
      ────────────────────────────
       > Open Counter    Jump to t
         Open Todo
         Disabled Command










    ──────────────────────────────
    """

  @Test("an empty scope renders the no-commands message")
  func emptyScopeIsCellForCellStable() {
    #expect(Self.render(EmptyScope(), width: 60, height: 20) == Self.emptyScopeSurface)
  }

  @Test("described, bare, and disabled rows render cell-for-cell")
  func mixedScopeIsCellForCellStable() {
    #expect(Self.render(MixedScope(), width: 60, height: 20) == Self.mixedScopeSurface)
  }

  @Test("duplicate labels stay distinct rows in contribution order")
  func duplicateLabelsAreCellForCellStable() {
    #expect(
      Self.render(DuplicateLabelScope(), width: 60, height: 20)
        == Self.duplicateLabelSurface
    )
  }

  @Test("a narrow terminal truncates descriptions, not rows")
  func narrowIsCellForCellStable() {
    #expect(Self.render(MixedScope(), width: 30, height: 20) == Self.narrowSurface)
  }
}
