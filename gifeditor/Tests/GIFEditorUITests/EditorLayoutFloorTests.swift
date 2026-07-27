import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// Where the editor stops fitting, measured rather than remembered.
///
/// ``EditorLayoutFloor/minimumWidth`` is a constant, and a constant describing
/// a layout is a claim that goes stale the moment somebody widens a panel. So
/// every number in it is checked here against what the layout system actually
/// answers when it is asked to fit the editor into nothing — which is the only
/// authority on the question.
///
/// The measurements deliberately hold `terminalSize` wide while proposing a
/// narrow box. Those are two different questions and the guard depends on
/// their being different: `terminalSize` is what
/// ``EditorLayoutFloor/fits(_:)`` reads, and the proposal is what the layout
/// is squeezed by. Pinning the first open is what lets these measure the
/// editor's stack instead of the message that replaces it.
@MainActor
@Suite("GIF editor layout floor")
struct EditorLayoutFloorTests {
  @Test("the menu bar is the constraint the floor claims it is")
  func menuBarIsTheBindingConstraint() {
    let model = viewModel()
    let measured = floorWidth(
      MenuBarView(
        openMenu: .constant(nil),
        model: model,
        showsToolDock: .constant(true),
        showsRightPanel: .constant(true),
        showsTimeline: .constant(true),
        pixelGridMode: .constant(.verticalHalfBlock),
        isResizeSheetPresented: .constant(false),
        refresh: {}
      ),
      id: "menubar"
    )
    #expect(
      measured == EditorLayoutFloor.menuBarWidth,
      """
      the menu bar's narrowest layout is \(measured) columns, not \
      \(EditorLayoutFloor.menuBarWidth). A menu trigger was added, renamed or \
      restyled — update EditorLayoutFloor.menuBarWidth to what the layout \
      system now says, and check it is still wider than bodyRowWidth.
      """
    )
    #expect(
      EditorLayoutFloor.minimumWidth == EditorLayoutFloor.menuBarWidth,
      "the body row (\(EditorLayoutFloor.bodyRowWidth)) has overtaken the menu bar"
    )
  }

  @Test("the editor's own narrowest layout is the floor")
  func theEditorCannotShrinkPastTheFloor() {
    let measured = floorWidth(editor(), id: "editor")
    #expect(
      measured == EditorLayoutFloor.minimumWidth,
      """
      EditorView lays out no narrower than \(measured) columns, but the floor \
      says \(EditorLayoutFloor.minimumWidth). Below its own floor the editor \
      stops shrinking and starts overflowing the terminal, which is the state \
      TerminalTooSmallView exists to replace.
      """
    )
  }

  /// The claim underneath the whole guard: at the floor the editor fills the
  /// terminal exactly, and one column below it does not shrink to match.
  @Test("one column under the floor, the layout overflows instead of shrinking")
  func belowTheFloorTheLayoutOverflows() {
    let atFloor = surfaceWidth(
      proposedWidth: EditorLayoutFloor.minimumWidth,
      id: "at-floor"
    )
    #expect(atFloor == EditorLayoutFloor.minimumWidth)

    let underFloor = surfaceWidth(
      proposedWidth: EditorLayoutFloor.minimumWidth - 1,
      id: "under-floor"
    )
    #expect(
      underFloor > EditorLayoutFloor.minimumWidth - 1,
      "the editor fitted a terminal narrower than its floor, so the floor is wrong"
    )
  }

  @Test("the fit check answers the floor and not a column either side of it")
  func fitsMatchesTheFloor() {
    let floor = EditorLayoutFloor.minimumWidth
    #expect(EditorLayoutFloor.fits(CellSize(width: floor, height: 24)))
    #expect(EditorLayoutFloor.fits(CellSize(width: floor + 1, height: 24)))
    #expect(!EditorLayoutFloor.fits(CellSize(width: floor - 1, height: 24)))
    #expect(!EditorLayoutFloor.fits(CellSize(width: 0, height: 24)))
    // Height is deliberately not a term — see the note on EditorLayoutFloor.
    #expect(EditorLayoutFloor.fits(CellSize(width: floor, height: 1)))
  }

  // MARK: - The too-small screen

  @Test("the too-small screen says what is wrong and what would fix it")
  func tooSmallScreenIsInformative() {
    let text = render(
      TerminalTooSmallView(
        available: CellSize(width: 40, height: 12),
        requiredWidth: EditorLayoutFloor.minimumWidth
      ),
      width: 40,
      height: 12,
      id: "content"
    )
    #expect(text.contains("Terminal too small"))
    #expect(text.contains("\(EditorLayoutFloor.minimumWidth) columns"))
    #expect(text.contains("40×12"), "the screen must report the size the terminal actually is")
  }

  /// The one screen guaranteed to be shown in a terminal too narrow for the
  /// editor is also the one that must not overflow it. Checked at the widest
  /// size it can appear at (one under the floor) and at the narrowest size
  /// worth claiming to support.
  @Test("the too-small screen fits every terminal it can appear in")
  func tooSmallScreenNeverOverflows() {
    for width in [EditorLayoutFloor.minimumWidth - 1, 40, 24, 20] {
      let text = render(
        TerminalTooSmallView(
          available: CellSize(width: width, height: 10),
          requiredWidth: EditorLayoutFloor.minimumWidth
        ),
        width: width,
        height: 10,
        id: "fit-\(width)"
      )
      let widest =
        text.split(separator: "\n", omittingEmptySubsequences: false)
        .map(\.count).max() ?? 0
      #expect(widest <= width, "the too-small screen ran off a \(width)-column terminal")
    }
  }

  /// The 80-column budget, which every visible part of the editor answers to.
  /// The too-small screen can only appear below 64 columns, so this is the
  /// belt-and-braces half: even if it somehow rendered at 80 it would not be
  /// the thing that broke the budget.
  @Test("nothing new overruns the 80-column budget")
  func newChromeStaysInsideTheEightyColumnBudget() {
    let message = render(
      TerminalTooSmallView(
        available: CellSize(width: 80, height: 24),
        requiredWidth: EditorLayoutFloor.minimumWidth
      ),
      width: 80,
      height: 24,
      id: "budget-message"
    )
    #expect(
      message.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy {
        $0.count <= 80
      })

    // The palette grid's collision markers replace blank cells rather than
    // claiming new ones, so a fully-colliding palette on a 256-color
    // terminal must render the whole editor at exactly its old width.
    for fidelity in EditorColorFidelity.allCases {
      let text = render(
        editor(fidelity: fidelity),
        width: 80,
        height: 24,
        id: "budget-editor-\(fidelity.rawValue)"
      )
      #expect(
        text.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy {
          $0.count <= 80
        },
        "the editor overran 80 columns under \(fidelity.rawValue) color fidelity"
      )
      // Not vacuous: this really is the editor and not the too-small screen.
      #expect(text.contains("Palette"))
    }
  }

  // MARK: - Harness

  private func editor(fidelity: EditorColorFidelity = .full) -> EditorView {
    EditorView(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 8, height: 8)),
      stateDirectory: Self.throwawayStateDirectory,
      colorFidelity: fidelity
    )
  }

  private func viewModel() -> EditorViewModel {
    EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 8, height: 8)),
      stateDirectory: Self.throwawayStateDirectory
    )
  }

  /// The narrowest layout `view` can produce: propose one column and read
  /// back what it insisted on instead.
  private func floorWidth(_ view: some View, id: String) -> Int {
    surface(view, proposal: ProposedSize(width: 1, height: 60), id: "floor-\(id)").size.width
  }

  private func surfaceWidth(proposedWidth: Int, id: String) -> Int {
    surface(
      editor(),
      proposal: ProposedSize(width: proposedWidth, height: 28),
      id: id
    ).size.width
  }

  private func surface(
    _ view: some View,
    proposal: ProposedSize,
    id: String
  ) -> RasterSurface {
    var environment = EnvironmentValues()
    // Wide on purpose: this measures the editor's stack, not the fit gate in
    // front of it.
    environment.terminalSize = CellSize(width: 200, height: 60)
    return DefaultRenderer().render(
      view,
      context: ResolveContext(
        identity: Identity(components: ["gifeditor.layout-floor.\(id)"]),
        environmentValues: environment
      ),
      proposal: proposal
    ).rasterSurface
  }

  private func render(
    _ view: some View,
    width: Int,
    height: Int,
    id: String
  ) -> String {
    var environment = EnvironmentValues()
    environment.terminalSize = CellSize(width: width, height: height)
    return DefaultRenderer().render(
      view,
      context: ResolveContext(
        identity: Identity(components: ["gifeditor.layout-floor.render.\(id)"]),
        environmentValues: environment
      ),
      proposal: ProposedSize(width: width, height: height)
    ).rasterSurface.lines.joined(separator: "\n")
  }

  /// A directory no test writes to — it exists so constructing a view model
  /// cannot read the developer's real `~/.config/halfcell/` recents list.
  private static let throwawayStateDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-layout-floor-\(UUID().uuidString)")
}
