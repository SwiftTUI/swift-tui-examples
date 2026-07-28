import Foundation
import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

/// Where the editor stops fitting, measured rather than remembered.
///
/// ``EditorLayoutFloor`` is a wall of constants, and a constant describing a
/// layout is a claim that goes stale the moment somebody widens a panel or
/// adds a row to one. So every number in it is checked here against what the
/// layout system actually answers — which is the only authority on the
/// question.
///
/// The two axes are asked different questions, because they *are* different
/// questions:
///
/// * **Width** is measured by squeezing: propose one column and read back the
///   width the editor insisted on instead. The layout genuinely refuses to go
///   narrower, so its refusal is the floor.
/// * **Height** cannot be measured that way. A stack's minimum lets rules
///   collapse to nothing and lets the last child overdraw a border, so the
///   height at which the surface stops shrinking is a height at which rows
///   have already been lost — which is exactly how a 28-row editor came to be
///   presented into a 24-row terminal for as long as it was. So height is
///   measured region by region, each one asked how tall it is when it is
///   whole (`.fixedSize(vertical:)`), and the floor is the sum.
///
/// The width measurements deliberately hold `terminalSize` large while
/// proposing a narrow box. Those are two different questions and the guard
/// depends on their being different: `terminalSize` is what
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

  // MARK: - Height, region by region

  /// Every term of ``EditorLayoutFloor/minimumHeight(at:)``, re-measured at
  /// both densities against the region it claims to describe.
  ///
  /// A failure here is not a broken layout — it is a layout that changed
  /// height without the floor being told, which is how the editor last ended
  /// up taller than the terminal it runs in.
  @Test(
    "every region is exactly as tall as the floor says", arguments: EditorLayoutDensity.allCases)
  func regionHeightsAreWhatTheFloorClaims(density: EditorLayoutDensity) {
    let model = viewModel()
    // A layer list filled past its window, because the floor is quoted for
    // the tallest inspector a document can produce, not the emptiest.
    let crowded = viewModel(layers: density.visibleLayerRows + 3)

    expectHeight(
      of: MenuBarView(
        openMenu: .constant(nil),
        model: model,
        showsToolDock: .constant(true),
        showsRightPanel: .constant(true),
        showsTimeline: .constant(true),
        pixelGridMode: .constant(.verticalHalfBlock),
        isResizeSheetPresented: .constant(false),
        refresh: {}
      ),
      width: 80,
      pinned: EditorLayoutFloor.menuBarHeight,
      region: "menu bar",
      density: density
    )

    expectHeight(
      of: ToolOptionsBar(model: model, refresh: {}, density: density),
      width: 80,
      pinned: EditorLayoutFloor.toolOptionsBarHeight(at: density),
      region: "tool options bar",
      density: density
    )

    expectHeight(
      of: ToolboxView(
        tool: model.tool,
        primaryColor: model.document.palette[model.primaryColorIndex],
        secondaryColor: model.document.palette[model.secondaryColorIndex],
        model: model,
        refresh: {},
        density: density
      ),
      width: 12,
      pinned: EditorLayoutFloor.toolDockHeight(at: density),
      region: "tool dock",
      density: density
    )

    expectHeight(
      of: inspector(model: crowded, density: density),
      width: InspectorColumnView.width,
      pinned: EditorLayoutFloor.inspectorHeight(at: density),
      region: "right inspector",
      density: density
    )

    expectHeight(
      of: TimelineView(
        frames: timelineFrames(density: density),
        currentFrameIndex: 0,
        model: model,
        refresh: {}
      ),
      width: 80,
      pinned: EditorLayoutFloor.timelineHeight(at: density),
      region: "timeline strip",
      density: density
    )

    expectHeight(
      of: EditorStatusStripView(message: "", readout: "F1/1  [0,0]  L1/1  B1  1x  half-cell"),
      width: 80,
      pinned: EditorLayoutFloor.statusStripHeight,
      region: "status strip",
      density: density
    )
  }

  /// The floor is a sum, and this is the sum. Kept separate from the
  /// per-region check so a failure says whether a *region* moved or whether
  /// the arithmetic over them did.
  @Test("the floor is the sum of its regions", arguments: EditorLayoutDensity.allCases)
  func theFloorIsTheSumOfItsRegions(density: EditorLayoutDensity) {
    let rules = density.drawsRedundantRules ? 1 : 0
    let sum =
      EditorLayoutFloor.menuBarHeight
      + EditorLayoutFloor.toolOptionsBarHeight(at: density)
      + max(
        EditorLayoutFloor.toolDockHeight(at: density),
        EditorLayoutFloor.inspectorHeight(at: density)
      )
      + EditorLayoutFloor.timelineHeight(at: density)
      + rules
      + EditorLayoutFloor.statusStripHeight
    #expect(EditorLayoutFloor.minimumHeight(at: density) == sum)
    #expect(
      EditorLayoutFloor.bodyRowHeight(at: density)
        >= EditorLayoutFloor.toolDockHeight(at: density),
      "the tool dock is taller than the body row it sits in"
    )
  }

  /// The floor's whole claim, put to the layout system: at exactly
  /// ``EditorLayoutFloor/minimumHeight`` rows the editor renders exactly that
  /// many, with every region whole.
  @Test("at the height floor the editor lays out with nothing clipped")
  func theEditorFitsItsOwnHeightFloor() {
    let height = EditorLayoutFloor.minimumHeight
    let lines = render(
      crowdedEditor(),
      width: 80,
      height: height,
      id: "height-floor"
    )
    #expect(
      lines.count == height,
      "the editor rendered \(lines.count) rows into its own \(height)-row floor"
    )

    let text = lines.joined(separator: "\n")
    // Every region, top to bottom.
    #expect(text.contains("File ▾"), "the menu bar is missing")
    #expect(text.contains("Pen"), "the tool options bar is missing")
    #expect(text.contains("Palette"), "the inspector is missing")
    #expect(text.contains("Frames"), "the timeline is missing")
    #expect(text.contains("Ready"), "the status strip is missing")
    // And the regions that are lists are whole, not clipped at the bottom:
    // the last dock icon, and the inspector's own last row.
    for tool in ActiveTool.allCases {
      #expect(
        text.contains(tool.iconGlyph),
        "\(tool.label)'s dock icon fell off the bottom at the height floor"
      )
    }
    #expect(text.contains("New layer"), "the inspector's last row was clipped")
  }

  /// One row under the floor the editor overflows rather than compressing —
  /// the same claim the width side makes, and the reason the gate has to
  /// exist rather than trusting the stack to cope.
  ///
  /// Measured with the terminal held one row *above* the floor and the
  /// proposal squeezed one row below it. Those are the two different
  /// questions again: the terminal is what picks the density and what the
  /// gate reads, and the proposal is the box the compact layout is being
  /// asked to fit into. Setting both to 21 would measure the too-small
  /// screen, which fits anything.
  @Test("one row under the floor, the layout overflows instead of shrinking")
  func belowTheHeightFloorTheLayoutOverflows() {
    let floor = EditorLayoutFloor.minimumHeight
    let atFloor = squeezed(to: floor, id: "at-height-floor")
    #expect(atFloor == floor, "the compact editor is \(atFloor) rows at its own floor")

    let underFloor = squeezed(to: floor - 1, id: "under-height-floor")
    #expect(
      underFloor > floor - 1,
      "the editor fitted a terminal shorter than its floor, so the floor is wrong"
    )
  }

  @Test("the fit check answers the floor and not a row or column either side of it")
  func fitsMatchesTheFloor() {
    let width = EditorLayoutFloor.minimumWidth
    let height = EditorLayoutFloor.minimumHeight
    #expect(EditorLayoutFloor.fits(CellSize(width: width, height: height)))
    #expect(EditorLayoutFloor.fits(CellSize(width: width + 1, height: height)))
    #expect(EditorLayoutFloor.fits(CellSize(width: width, height: height + 1)))
    #expect(!EditorLayoutFloor.fits(CellSize(width: width - 1, height: height)))
    #expect(!EditorLayoutFloor.fits(CellSize(width: width, height: height - 1)))
    #expect(!EditorLayoutFloor.fits(CellSize(width: 0, height: 0)))
    // The size the editor documents, and the size its own tests run at.
    #expect(EditorLayoutFloor.fits(CellSize(width: 80, height: 24)))
  }

  /// The density switch is derived from the regular layout's own minimum, so
  /// this pins the derivation rather than the number: one row under it the
  /// editor must already be compact, or the regular layout would be offered a
  /// terminal it does not fit in.
  @Test("the density switch is exactly the regular layout's own minimum")
  func densityFollowsTheRegularMinimum() {
    let switchPoint = EditorLayoutFloor.regularMinimumHeight
    #expect(EditorLayoutFloor.density(for: CellSize(width: 200, height: switchPoint)) == .regular)
    #expect(
      EditorLayoutFloor.density(for: CellSize(width: 200, height: switchPoint - 1)) == .compact
    )
    #expect(EditorLayoutFloor.density(for: CellSize(width: 80, height: 24)) == .compact)
    #expect(
      EditorLayoutFloor.minimumHeight < EditorLayoutFloor.regularMinimumHeight,
      "compact is not compact"
    )
    #expect(
      EditorLayoutFloor.minimumHeight <= 24,
      """
      the compact layout needs \(EditorLayoutFloor.minimumHeight) rows, so the \
      80×24 terminal this package documents — and runs its own tests in — is \
      once again short of the editor it is supposed to hold.
      """
    )
  }

  /// The regular layout has to fit its own switch point, or the editor would
  /// swap to it at a height that clips it.
  @Test("the regular layout fits the height it is offered at")
  func theRegularLayoutFitsItsSwitchPoint() {
    let height = EditorLayoutFloor.regularMinimumHeight
    let lines = render(
      crowdedEditor(density: .regular),
      width: 80,
      height: height,
      id: "regular-floor"
    )
    #expect(
      lines.count == height,
      "the regular layout rendered \(lines.count) rows into the \(height) it switches on at"
    )
    let text = lines.joined(separator: "\n")
    #expect(text.contains("Color"), "the regular inspector dropped its color heading")
    #expect(text.contains("New layer"), "the regular inspector's last row was clipped")
  }

  // MARK: - The too-small screen

  @Test("the too-small screen says what is wrong and what would fix it")
  func tooSmallScreenIsInformative() {
    let text = render(
      tooSmallView(available: CellSize(width: 40, height: 12)),
      width: 40,
      height: 12,
      id: "content"
    ).joined(separator: "\n")
    #expect(text.contains("Terminal too small"))
    #expect(text.contains("\(EditorLayoutFloor.minimumWidth) columns"))
    #expect(text.contains("\(EditorLayoutFloor.minimumHeight) rows"))
    #expect(text.contains("40×12"), "the screen must report the size the terminal actually is")
  }

  /// Short in one dimension only, which is the common case at a window edge:
  /// the message has to name the axis the author should drag.
  @Test("the too-small screen names the axis that is short")
  func tooSmallScreenNamesTheAxis() {
    let narrow = render(
      tooSmallView(available: CellSize(width: 40, height: 60)),
      width: 40,
      height: 60,
      id: "narrow"
    ).joined(separator: "\n")
    #expect(narrow.contains("widen it"))

    let short = render(
      tooSmallView(available: CellSize(width: 120, height: 8)),
      width: 120,
      height: 8,
      id: "short"
    ).joined(separator: "\n")
    #expect(short.contains("taller"))
  }

  /// The one screen guaranteed to be shown in a terminal too small for the
  /// editor is also the one that must not overflow it. Checked at the widest
  /// size it can appear at (one under the floor) and at the narrowest size
  /// worth claiming to support.
  @Test("the too-small screen fits every terminal it can appear in")
  func tooSmallScreenNeverOverflows() {
    for width in [EditorLayoutFloor.minimumWidth - 1, 40, 24, 20] {
      let lines = render(
        tooSmallView(available: CellSize(width: width, height: 10)),
        width: width,
        height: 10,
        id: "fit-\(width)"
      )
      let widest = lines.map(\.count).max() ?? 0
      #expect(widest <= width, "the too-small screen ran off a \(width)-column terminal")
      #expect(lines.count <= 10, "the too-small screen ran off a 10-row terminal")
    }
  }

  /// The 80-column budget, which every visible part of the editor answers to.
  /// The too-small screen can only appear below 64 columns, so this is the
  /// belt-and-braces half: even if it somehow rendered at 80 it would not be
  /// the thing that broke the budget.
  @Test("nothing new overruns the 80-column budget")
  func newChromeStaysInsideTheEightyColumnBudget() {
    let message = render(
      tooSmallView(available: CellSize(width: 80, height: 24)),
      width: 80,
      height: 24,
      id: "budget-message"
    )
    #expect(message.allSatisfy { $0.count <= 80 })

    // The palette grid's collision markers replace blank cells rather than
    // claiming new ones, so a fully-colliding palette on a 256-color
    // terminal must render the whole editor at exactly its old width.
    for fidelity in EditorColorFidelity.allCases {
      let lines = render(
        editor(fidelity: fidelity),
        width: 80,
        height: 24,
        id: "budget-editor-\(fidelity.rawValue)"
      )
      #expect(
        lines.allSatisfy { $0.count <= 80 },
        "the editor overran 80 columns under \(fidelity.rawValue) color fidelity"
      )
      // Not vacuous: this really is the editor and not the too-small screen.
      #expect(lines.joined().contains("Palette"))
    }
  }

  // MARK: - Harness

  private func editor(
    fidelity: EditorColorFidelity = .full,
    layers: Int = 1,
    frames: Int = 1
  ) -> EditorView {
    EditorView(
      document: Self.document(layers: layers, frames: frames),
      stateDirectory: Self.throwawayStateDirectory,
      colorFidelity: fidelity
    )
  }

  /// The document the floor is quoted for: a layer list filled past its
  /// window and a frame strip long enough to scroll. Every other document
  /// produces an editor that is the same height or shorter, which is what
  /// makes the floor a floor rather than a description of a blank canvas.
  private func crowdedEditor(density: EditorLayoutDensity = .compact) -> EditorView {
    editor(layers: density.visibleLayerRows + 3, frames: 12)
  }

  private func viewModel(layers: Int = 1) -> EditingSession {
    EditingSession(document: Self.document(layers: layers, frames: 1))
  }

  private static func document(layers: Int, frames: Int) -> GIFDocument {
    let size = GIFEditorCore.PixelSize(width: 8, height: 8)
    guard layers > 1 || frames > 1 else { return GIFDocument.blank(size: size) }
    let frame = EditorFrame(
      layers: (0..<max(1, layers)).map {
        EditorLayer(name: "Layer \($0 + 1)", pixels: PixelBuffer(size: size))
      },
      delayCentiseconds: 10
    )
    return GIFDocument(size: size, frames: Array(repeating: frame, count: max(1, frames)))
  }

  private func inspector(
    model: EditingSession,
    density: EditorLayoutDensity
  ) -> InspectorColumnView {
    InspectorColumnView(
      primaryColor: model.document.palette[model.primaryColorIndex],
      secondaryColor: model.document.palette[model.secondaryColorIndex],
      palette: model.document.palette,
      primaryIndex: model.primaryColorIndex,
      secondaryIndex: model.secondaryColorIndex,
      layers: model.currentFrame.layers,
      selectedLayerIndex: model.currentLayerIndex,
      model: model,
      refresh: {},
      fidelity: .full,
      density: density
    )
  }

  /// Enough frames that the strip has to scroll, because a strip that scrolls
  /// grows an indicator row and the floor is quoted for the taller of the
  /// two. Twelve is comfortably past the handful that fit across 80 columns.
  private func timelineFrames(density: EditorLayoutDensity) -> [TimelineFrame] {
    let side = density.timelineThumbnailSide
    return (0..<12).map { _ in
      TimelineFrame(
        thumbnail: TimelineFrame.Thumbnail(
          width: side,
          height: side,
          pixels: Array(repeating: EditorColor?.none, count: side * side)
        ),
        delayCentiseconds: 10
      )
    }
  }

  private func tooSmallView(available: CellSize) -> TerminalTooSmallView {
    TerminalTooSmallView(
      available: available,
      requiredWidth: EditorLayoutFloor.minimumWidth,
      requiredHeight: EditorLayoutFloor.minimumHeight
    )
  }

  /// How tall `view` is when it is whole.
  ///
  /// Two halves, and both are load-bearing. `.fixedSize(vertical:)` asks the
  /// region for its *ideal* height, which is the only honest answer to "how
  /// tall are you" — without it a `Spacer` or a scroll view stretches to
  /// whatever was proposed, and with a squeezed proposal instead the stack
  /// would hand back a minimum in which rules have collapsed and the last row
  /// is overdrawing a border. Proposing one row is then what stops the
  /// renderer padding the surface out to the proposal: a surface is as tall
  /// as the taller of the view and the box it was offered.
  private func expectHeight(
    of view: some View,
    width: Int,
    pinned: Int,
    region: String,
    density: EditorLayoutDensity,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let measured = render(
      view.fixedSize(horizontal: false, vertical: true),
      width: width,
      height: 1,
      id: "height-\(region)-\(density)"
    ).count
    #expect(
      measured == pinned,
      """
      the \(region) is \(measured) rows tall at \(density) density, not \
      \(pinned). Update EditorLayoutFloor to what the layout system now says \
      — the editor's height floor is the sum of these, and a term that drifts \
      is a terminal the editor overflows without saying so.
      """,
      sourceLocation: sourceLocation
    )
  }

  /// The narrowest layout `view` can produce: propose one column and read
  /// back what it insisted on instead.
  private func floorWidth(_ view: some View, id: String) -> Int {
    surface(view, proposal: ProposedSize(width: 1, height: 60), id: "floor-\(id)").size.width
  }

  /// The height the compact editor insists on when squeezed into
  /// `proposedHeight` rows. The environment's terminal stays one row above
  /// the floor so the fit gate is out of the way and the density is the
  /// compact one being measured.
  private func squeezed(to proposedHeight: Int, id: String) -> Int {
    var environment = EnvironmentValues()
    environment.terminalSize = CellSize(width: 200, height: EditorLayoutFloor.minimumHeight)
    return DefaultRenderer().render(
      crowdedEditor(),
      context: ResolveContext(
        identity: Identity(components: ["gifeditor.layout-floor.\(id)"]),
        environmentValues: environment
      ),
      proposal: ProposedSize(width: 80, height: proposedHeight)
    ).rasterSurface.size.height
  }

  private func surfaceWidth(proposedWidth: Int, id: String) -> Int {
    surface(
      editor(),
      proposal: ProposedSize(width: proposedWidth, height: 40),
      id: id
    ).size.width
  }

  private func surface(
    _ view: some View,
    proposal: ProposedSize,
    id: String
  ) -> RasterSurface {
    var environment = EnvironmentValues()
    // Large on purpose: this measures the editor's stack, not the fit gate in
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
  ) -> [String] {
    var environment = EnvironmentValues()
    environment.terminalSize = CellSize(width: width, height: height)
    return DefaultRenderer().render(
      view,
      context: ResolveContext(
        identity: Identity(components: ["gifeditor.layout-floor.render.\(id)"]),
        environmentValues: environment
      ),
      proposal: ProposedSize(width: width, height: height)
    ).rasterSurface.lines
  }

  /// A directory no test writes to — it exists so constructing a view model
  /// cannot read the developer's real `~/.config/halfcell/` recents list.
  private static let throwawayStateDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("halfcell-layout-floor-\(UUID().uuidString)")
}
