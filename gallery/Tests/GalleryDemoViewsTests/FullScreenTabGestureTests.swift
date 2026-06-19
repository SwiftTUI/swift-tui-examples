import Foundation
@_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite(.serialized)
struct LogoBreakerGestureTests {

  @Test("fullscreen toy starts at bottom center with its initial launch velocity")
  func spawnStateStartsAtBottomCenter() {
    let terminalSize = CellSize(width: 40, height: 12)
    let playfield = FullScreenToyPhysics.fieldBounds(from: terminalSize)
    let floor = FullScreenToyPhysics.maximumOrigin(in: playfield, metrics: .estimated)

    let state = FullScreenToyPhysics.spawnState(in: playfield, metrics: .estimated)

    #expect(state.position.x == floor.x / 2)
    #expect(state.position.y == floor.y)
    #expect(state.velocity.x == FullScreenToyPhysics.initialLaunchX)
    #expect(state.velocity.y == FullScreenToyPhysics.initialLaunchY)
  }

  @Test("fullscreen toy physics applies gravity and bounces off the floor")
  func physicsBouncesOffFloor() {
    let terminalSize = CellSize(width: 40, height: 12)
    let floor = FullScreenToyPhysics.maximumOrigin(in: terminalSize, metrics: .estimated)
    var state = FullScreenToyPhysics.State(
      position: .init(x: 10 * FullScreenToyPhysics.fixedScale, y: floor.y - 1),
      velocity: .init(x: 0, y: 10)
    )

    FullScreenToyPhysics.step(&state, in: terminalSize, metrics: .estimated)

    #expect(state.position.y == floor.y)
    #expect(state.velocity.y < 0)
  }

  @Test("fullscreen toy physics reflects from the right wall")
  func physicsReflectsOffRightWall() {
    let terminalSize = CellSize(width: 40, height: 12)
    let wall = FullScreenToyPhysics.maximumOrigin(in: terminalSize, metrics: .estimated)
    var state = FullScreenToyPhysics.State(
      position: .init(x: wall.x - 2, y: 4 * FullScreenToyPhysics.fixedScale),
      velocity: .init(x: 6, y: 0)
    )

    FullScreenToyPhysics.step(&state, in: terminalSize, metrics: .estimated)

    #expect(state.position.x == wall.x)
    #expect(state.velocity.x < 0)
  }

  @Test("fullscreen toy release converts gesture velocity into physics velocity")
  func releaseConvertsGestureVelocity() {
    let terminalSize = CellSize(width: 40, height: 12)
    var state = FullScreenToyPhysics.State()

    FullScreenToyPhysics.applyRelease(
      to: &state,
      translation: .zero,
      velocity: Vector(dx: 100, dy: -50),
      in: terminalSize,
      metrics: .estimated
    )

    #expect(state.velocity == .init(x: 64, y: -16))
  }

  @Test("fullscreen toy release velocity does not move an already committed drag")
  func releaseVelocityDoesNotMoveCommittedDrag() {
    let terminalSize = CellSize(width: 40, height: 12)
    var state = FullScreenToyPhysics.State(
      position: .init(x: 12, y: 24),
      velocity: .zero
    )

    FullScreenToyPhysics.applyReleaseVelocity(
      to: &state,
      velocity: Vector(dx: 100, dy: -50),
      in: terminalSize,
      metrics: .estimated
    )

    #expect(state.position == .init(x: 12, y: 24))
    #expect(state.velocity == .init(x: 64, y: -16))
  }

  @Test("beginning a ball drag clears existing velocity")
  func beginningDragClearsExistingVelocity() {
    var state = FullScreenToyPhysics.State(
      position: .init(x: 12, y: 24),
      velocity: .init(x: 40, y: -18)
    )

    FullScreenToyPhysics.stop(&state)

    #expect(state.position == .init(x: 12, y: 24))
    #expect(state.velocity == .zero)
  }

  @Test("logo breaker drag commits grabbed position without gravity or floor bounce")
  func logoBreakerDragCommitsGrabbedPositionWithoutPhysicsStep() {
    let terminalSize = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let floor = FullScreenToyPhysics.maximumOrigin(in: terminalSize, metrics: metrics)
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    var state = FullScreenToyPhysics.State(
      position: .init(x: 12 * FullScreenToyPhysics.fixedScale, y: floor.y),
      velocity: .init(x: 0, y: 100)
    )

    let outcome = LogoBreakerGame.drag(
      &state,
      brokenBrickIDs: &brokenBrickIDs,
      to: Vector(dx: 3, dy: -5),
      in: terminalSize,
      metrics: metrics
    )

    #expect(outcome == .tracking)
    #expect(
      state.position
        == .init(
          x: 15 * FullScreenToyPhysics.fixedScale,
          y: floor.y - 5 * FullScreenToyPhysics.fixedScale
        )
    )
    #expect(state.velocity == .zero)
  }

  @Test("logo breaker derives breakable bricks from original logo pixels")
  func logoBreakerUsesOriginalLogoPixelsAsBricks() {
    #expect(LogoArt.sourceWidth == 16)
    #expect(LogoArt.sourceHeight == 16)
    #expect(LogoArt.cellWidth == 32)
    #expect(LogoArt.cellHeight == 16)
    #expect(!LogoArt.bricks.isEmpty)
    #expect(
      LogoArt.bricks.allSatisfy { brick in
        brick.width == 2
          && brick.height == 1
          && brick.x.isMultiple(of: 2)
          && brick.cells.count == 2
          && brick.cells[0].x == brick.x
          && brick.cells[1].x == brick.x + 1
          && brick.cells.allSatisfy { cell in
            cell.y == brick.y && (cell.top != nil || cell.bottom != nil)
          }
      }
    )
    #expect(Set(LogoArt.bricks.map(\.id)).count == LogoArt.bricks.count)
  }

  @Test("logo breaker removes a logo brick and reflects the ball")
  func logoBreakerBreaksIntersectedLogoCell() throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let metrics = CellPixelMetrics.estimated
    let ballHeight = LogoBreakerGame.ballCellHeight(metrics: metrics)
    let logoOrigin = LogoBreakerGame.logoOrigin(in: terminalSize)
    let target = try #require(LogoArt.bricks.first { $0.y > ballHeight })
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(target.id)
    var state = FullScreenToyPhysics.State(
      position: .init(
        x: centeredBallOriginX(over: target, logoOrigin: logoOrigin, metrics: metrics),
        y: (logoOrigin.y + target.y - ballHeight) * FullScreenToyPhysics.fixedScale
      ),
      velocity: .init(x: 0, y: FullScreenToyPhysics.fixedScale)
    )

    _ = LogoBreakerGame.step(
      &state,
      brokenBrickIDs: &brokenBrickIDs,
      in: terminalSize,
      metrics: metrics
    )

    #expect(brokenBrickIDs.contains(target.id))
    #expect(state.velocity.y < 0)
  }

  @Test("logo breaker ignores ball bounding-box corner overlap outside the circle")
  func logoBreakerCircleMissesBoundingBoxOnlyCornerOverlap() throws {
    let terminalSize = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let logoOrigin = LogoBreakerGame.logoOrigin(in: terminalSize)
    let target = try #require(LogoArt.bricks.first { $0.y >= 6 && $0.x >= 4 })
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(target.id)
    let ball = LogoBreakerGame.ballGeometry(at: .zero, metrics: metrics)
    let brickMinX = Double(logoOrigin.x + target.x)
    let brickMinY = Double(logoOrigin.y + target.y)
    var state = FullScreenToyPhysics.State(
      position: fixedBallOrigin(
        center: Point(
          x: brickMinX - ball.radiusX + 0.2,
          y: brickMinY - ball.radiusY + 0.1
        ),
        metrics: metrics
      ),
      velocity: .zero
    )

    let outcome = LogoBreakerGame.drag(
      &state,
      brokenBrickIDs: &brokenBrickIDs,
      to: .zero,
      in: terminalSize,
      metrics: metrics
    )

    #expect(outcome == .tracking)
    #expect(!brokenBrickIDs.contains(target.id))
  }

  @Test("logo breaker circular corner hit adds horizontal momentum")
  func logoBreakerCircularCornerHitAddsHorizontalMomentum() throws {
    let terminalSize = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let logoOrigin = LogoBreakerGame.logoOrigin(in: terminalSize)
    let target = try #require(LogoArt.bricks.first { $0.y >= 8 && $0.x >= 4 })
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(target.id)
    let ball = LogoBreakerGame.ballGeometry(at: .zero, metrics: metrics)
    let brickMinX = Double(logoOrigin.x + target.x)
    let brickMinY = Double(logoOrigin.y + target.y)
    var state = FullScreenToyPhysics.State(
      position: fixedBallOrigin(
        center: Point(
          x: brickMinX - 1,
          y: brickMinY - ball.radiusY - 2.5
        ),
        metrics: metrics
      ),
      velocity: .init(x: 0, y: 4 * FullScreenToyPhysics.fixedScale)
    )

    _ = LogoBreakerGame.step(
      &state,
      brokenBrickIDs: &brokenBrickIDs,
      in: terminalSize,
      metrics: metrics
    )

    #expect(brokenBrickIDs.contains(target.id))
    #expect(state.velocity.x < 0)
    #expect(state.velocity.y < 0)
  }

  @Test("logo breaker sweeps high-speed movement to the first reachable brick")
  func logoBreakerSweepsFastMovementToFirstReachableBrick() throws {
    let terminalSize = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let ballHeight = LogoBreakerGame.ballCellHeight(metrics: metrics)
    let logoOrigin = LogoBreakerGame.logoOrigin(in: terminalSize)
    let columns = Dictionary(grouping: LogoArt.bricks, by: { $0.x })
    let pair = try #require(
      columns.values.compactMap { cells -> (near: LogoBrick, far: LogoBrick)? in
        let sorted = cells.sorted { $0.y < $1.y }
        for index in sorted.indices {
          let near = sorted[index]
          guard near.y > ballHeight + 1 else {
            continue
          }
          guard
            let far = sorted[(index + 1)..<sorted.endIndex].first(where: {
              $0.y >= near.y + ballHeight + 2
            })
          else {
            continue
          }
          return (near, far)
        }
        return nil
      }.first
    )
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(pair.near.id)
    brokenBrickIDs.remove(pair.far.id)
    var state = FullScreenToyPhysics.State(
      position: .init(
        x: centeredBallOriginX(over: pair.near, logoOrigin: logoOrigin, metrics: metrics),
        y: (logoOrigin.y + pair.near.y - ballHeight - 1)
          * FullScreenToyPhysics.fixedScale
      ),
      velocity: .init(
        x: 0,
        y: (pair.far.y - pair.near.y + ballHeight + 3)
          * FullScreenToyPhysics.fixedScale
      )
    )

    _ = LogoBreakerGame.step(
      &state,
      brokenBrickIDs: &brokenBrickIDs,
      in: terminalSize,
      metrics: metrics
    )

    #expect(brokenBrickIDs.contains(pair.near.id))
    #expect(!brokenBrickIDs.contains(pair.far.id))
    #expect(state.velocity.y < 0)
  }

  @Test("dragging through logo bricks breaks the first reachable brick and drops the drag")
  func logoBreakerDragDropsAtFirstReachableBrick() throws {
    let terminalSize = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let ballHeight = LogoBreakerGame.ballCellHeight(metrics: metrics)
    let logoOrigin = LogoBreakerGame.logoOrigin(in: terminalSize)
    let columns = Dictionary(grouping: LogoArt.bricks, by: { $0.x })
    let pair = try #require(
      columns.values.compactMap { cells -> (near: LogoBrick, far: LogoBrick)? in
        let sorted = cells.sorted { $0.y < $1.y }
        for index in sorted.indices {
          let near = sorted[index]
          guard near.y > ballHeight + 1 else {
            continue
          }
          guard
            let far = sorted[(index + 1)..<sorted.endIndex].first(where: {
              $0.y >= near.y + ballHeight + 2
            })
          else {
            continue
          }
          return (near, far)
        }
        return nil
      }.first
    )
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(pair.near.id)
    brokenBrickIDs.remove(pair.far.id)
    var state = FullScreenToyPhysics.State(
      position: .init(
        x: centeredBallOriginX(over: pair.near, logoOrigin: logoOrigin, metrics: metrics),
        y: (logoOrigin.y + pair.near.y - ballHeight - 1)
          * FullScreenToyPhysics.fixedScale
      ),
      velocity: .init(x: 20, y: -12)
    )

    let outcome = LogoBreakerGame.drag(
      &state,
      brokenBrickIDs: &brokenBrickIDs,
      to: Vector(
        dx: 0,
        dy: Double(pair.far.y - pair.near.y + ballHeight + 3)
      ),
      in: terminalSize,
      metrics: metrics
    )

    #expect(outcome == .dropped)
    #expect(brokenBrickIDs.contains(pair.near.id))
    #expect(!brokenBrickIDs.contains(pair.far.id))
    #expect(
      state.position.y
        == (logoOrigin.y + pair.near.y - ballHeight) * FullScreenToyPhysics.fixedScale
    )
    #expect(state.velocity == .zero)
  }

  @Test(
    "ball drag-gesture hit region tracks the visible ball position in absolute coordinates"
  )
  func ballHitRegionIsPlacedAtVisibleBall() throws {
    // Regression test for the bug that caused the gallery Logo Breaker
    // ball gesture to misfire. The ball's `contentShape(_:CellRect)`
    // is supplied in node-local Canvas coordinates; the framework
    // translates it by the Canvas's absolute placed origin. Earlier
    // the rect-based overload skipped that translation, anchoring
    // the hit region at absolute (0, 0) and making the ball
    // undraggable whenever it was rendered anywhere other than the
    // screen origin.
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("LogoBreakerHitRegionPlacement")])
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      LogoTab(),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    // The ball's footprint at the initial render — `toyState =
    // State()` puts it at local (0, 0) within the GeometryReader.
    let metrics = CellPixelMetrics.estimated
    let ballHeight = max(
      1,
      Int((Double(FullScreenToyPhysics.diameter) / metrics.aspectRatio).rounded())
    )

    // Locate the ball's interaction region by its distinctive size
    // (diameter × ballHeight). Other regions in the snapshot are the
    // surrounding chrome (toolbar, palette command, etc.) which have
    // different dimensions.
    let ballSize = CellSize(
      width: FullScreenToyPhysics.diameter,
      height: ballHeight
    )
    let ballRegion = artifacts.semanticSnapshot.interactionRegions.first {
      $0.rect.size == ballSize
    }
    let region = try #require(ballRegion)

    // The hit region must sit fully inside the terminal bounds — if
    // the framework had failed to translate by the Canvas's placed
    // origin, the rect would still anchor at (0, 0) but be off by
    // any chrome offset, and an offset tab would have produced a
    // rect at (0, 0) that doesn't match the visible ball.
    #expect(region.rect.origin.x >= 0)
    #expect(region.rect.origin.x + region.rect.size.width <= terminalSize.width)
    #expect(region.rect.origin.y >= 0)
    #expect(region.rect.origin.y + region.rect.size.height <= terminalSize.height)

    // The region must actually contain its own center — i.e. a
    // press there would fire the gesture. This is the guarantee the
    // pre-fix rect-based contentShape silently lost.
    let center = PointerLocation.cellFallback(
      CellPoint(
        x: region.rect.origin.x + region.rect.size.width / 2,
        y: region.rect.origin.y + region.rect.size.height / 2
      )
    )
    #expect(region.contains(center))
  }

  @Test(
    "fullscreen demo keeps presenting frames while gravity runs",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func gravityLoopSchedulesRuntimeFrames() async throws {
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("LogoBreakerGravityLoop")])
    let host = GestureRecordingHost(size: terminalSize)
    let inputReader = AwaitedTerminalInputReader(
      frameSignal: host.frameSignal,
      stageClock: host.stageClock,
      steps: [
        .awaitCondition {
          deduplicated(host.surfaces).count >= 2
        },
        .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
      ])
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { LogoTab() },
      terminalInputReader: inputReader
    )
    try await inputReader.requireNoWaitFailure()

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.renderedFrames >= 2)

    let uniqueSurfaces = deduplicated(host.surfaces)
    #expect(uniqueSurfaces.count >= 2)
    #expect(uniqueSurfaces.first != uniqueSurfaces.last)
  }

  @Test(
    "dragging the fullscreen demo rectangle updates the rendered surface and commits position",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func draggingRectangleUpdatesAndCommits() async throws {
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("LogoBreakerGestureTest")])
    let view = LogoTab()

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let shapeBounds = try #require(firstShapeBounds(in: initial.placedTree))
    let start = centerPoint(of: shapeBounds)
    let end = Point(x: start.x + 5, y: start.y + 2)

    let host = GestureRecordingHost(size: terminalSize)
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { view },
      eventSchedule: [
        .init(delayNanoseconds: 0, event: .mouse(.init(kind: .down(.primary), location: start))),
        .init(
          delayNanoseconds: 30_000_000,
          event: .mouse(.init(kind: .dragged(.primary), location: end))
        ),
        .init(
          delayNanoseconds: 30_000_000, event: .mouse(.init(kind: .up(.primary), location: end))),
      ]
    )

    #expect(result.exitReason == .inputEnded)
    #expect(host.surfaces.count >= 2)

    let firstFrame = try #require(host.surfaces.first)
    let lastFrame = try #require(host.surfaces.last)
    #expect(
      firstFrame != lastFrame,
      "dragging should change the fullscreen demo surface after release"
    )
  }

  @Test(
    "fullscreen demo rectangle remains draggable after its offset changes",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func draggingRectangleTwiceTracksItsMovedPosition() async throws {
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("LogoBreakerGestureTwiceTest")])
    let view = LogoTab()

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let shapeBounds = try #require(firstShapeBounds(in: initial.placedTree))
    let start = centerPoint(of: shapeBounds)
    let firstEnd = Point(x: start.x + 5, y: start.y + 2)
    let capture = PhysicsSecondDragCapture()

    let host = GestureRecordingHost(size: terminalSize)
    let inputReader = AwaitedTerminalInputReader(
      frameSignal: host.frameSignal,
      stageClock: host.stageClock,
      steps: [
        .event(.mouse(.init(kind: .down(.primary), location: start))),
        .event(
          .mouse(.init(kind: .dragged(.primary), location: firstEnd)),
          delayNanoseconds: 30_000_000
        ),
        .event(
          .mouse(.init(kind: .up(.primary), location: firstEnd)),
          delayNanoseconds: 30_000_000
        ),
        .awaitCondition {
          let surfaces = deduplicated(host.surfaces)
          guard surfaces.count >= 2,
            let bounds = surfaces.last.flatMap(brailleBounds(in:))
          else {
            return false
          }
          capture.secondStart = centerPoint(of: bounds)
          capture.secondEnd = Point(x: capture.secondStart.x + 4, y: capture.secondStart.y + 1)
          return true
        },
        .eventFrom {
          .mouse(.init(kind: .down(.primary), location: capture.secondStart))
        },
        .eventFrom(
          delayNanoseconds: 30_000_000
        ) {
          .mouse(.init(kind: .dragged(.primary), location: capture.secondEnd))
        },
        .eventFrom(
          delayNanoseconds: 30_000_000
        ) {
          .mouse(.init(kind: .up(.primary), location: capture.secondEnd))
        },
        .awaitCondition {
          deduplicated(host.surfaces).count >= 3
        },
      ])
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { view },
      terminalInputReader: inputReader
    )
    try await inputReader.requireNoWaitFailure()

    #expect(result.exitReason == .inputEnded)

    let uniqueSurfaces = deduplicated(host.surfaces)
    #expect(uniqueSurfaces.count >= 3)
    #expect(uniqueSurfaces.first != uniqueSurfaces.last)
  }

  @Test(
    "fullscreen demo resumes physics after drag release",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func draggingRectangleReleaseResumesPhysics() async throws {
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("LogoBreakerReleaseResumesPhysics")])
    let view = LogoTab()

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let shapeBounds = try #require(firstShapeBounds(in: initial.placedTree))
    let start = centerPoint(of: shapeBounds)
    let end = Point(x: start.x + 7, y: start.y + 3)

    let capture = PhysicsReleaseCapture()
    let host = GestureRecordingHost(size: terminalSize)
    let inputReader = AwaitedTerminalInputReader(
      frameSignal: host.frameSignal,
      stageClock: host.stageClock,
      steps: [
        .event(.mouse(.init(kind: .down(.primary), location: start))),
        .event(
          .mouse(.init(kind: .dragged(.primary), location: end)),
          delayNanoseconds: 30_000_000
        ),
        .event(
          .mouse(.init(kind: .up(.primary), location: end)),
          delayNanoseconds: 30_000_000
        ),
        .awaitCondition {
          capture.surfaceCountAtRelease = deduplicated(host.surfaces).count
          return true
        },
        .awaitCondition {
          deduplicated(host.surfaces).count > capture.surfaceCountAtRelease
        },
      ])
    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { view },
      terminalInputReader: inputReader
    )
    try await inputReader.requireNoWaitFailure()

    #expect(result.exitReason == .inputEnded)

    let uniqueSurfaces = deduplicated(host.surfaces)
    #expect(
      uniqueSurfaces.count > capture.surfaceCountAtRelease,
      "expected at least one physics-driven frame after release, not only drag/release frames"
    )
  }

  @Test("fullscreen tab wrapped in a bottom toolbar renders the palette item")
  func fullscreenToolbarRendersPaletteItem() {
    let terminalSize = CellSize(width: 40, height: 12)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      LogoTab()
        .toolbarItem(.init(title: "⌃K Palette", action: {}))
        .panel(id: "gallery")
        .toolbar(style: DefaultBottomToolbarStyle()),
      context: .init(
        identity: Identity(components: [.named("FullScreenToolbarVisibility")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let paletteRows = artifacts.rasterSurface.lines.enumerated().compactMap { index, line in
      line.contains("⌃K Palette") ? index : nil
    }
    #expect(!paletteRows.isEmpty, "expected toolbar row to contain the palette item")
  }

  @Test(
    "fullscreen toolbar stays present in the rendered surface while animation ticks",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func fullscreenToolbarStaysPresentAcrossAnimationFrames() async throws {
    let terminalSize = CellSize(width: 40, height: 12)
    let rootIdentity = Identity(components: [.named("FullScreenToolbarAnimationVisibility")])
    let host = GestureRecordingHost(size: terminalSize)
    let inputReader = AwaitedTerminalInputReader(
      frameSignal: host.frameSignal,
      stageClock: host.stageClock,
      steps: [
        .awaitCondition {
          deduplicated(host.surfaces).count >= 2
        },
        .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
      ])

    let result = try await runHarness(
      host: host,
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: {
        LogoTab()
          .toolbarItem(.init(title: "⌃K Palette", action: {}))
          .panel(id: "gallery")
          .toolbar(style: DefaultBottomToolbarStyle())
      },
      terminalInputReader: inputReader
    )
    try await inputReader.requireNoWaitFailure()

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(!host.surfaces.isEmpty)
    let missingPalette = host.surfaces.enumerated().filter { _, surface in
      !surface.lines.contains { $0.contains("⌃K Palette") }
    }
    #expect(
      missingPalette.isEmpty,
      "expected every rendered surface to retain the palette toolbar item; missing on frames: \(missingPalette.map { $0.0 })"
    )
  }
}

private struct ScheduledInputEvent {
  let delayNanoseconds: UInt64
  let event: InputEvent
}

private enum AwaitedTerminalInputStep {
  case event(InputEvent, delayNanoseconds: UInt64 = 0)
  case eventFrom(
    delayNanoseconds: UInt64 = 0,
    provider: @MainActor () -> InputEvent
  )
  /// Suspends the input script until `predicate` holds, re-evaluated only when
  /// the host presents a new frame (`frameSignal.notify()`) rather than on a
  /// clock — a starved run loop slows the test instead of timing it out.
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class ScheduledTerminalInputReader: TerminalInputReading {
  let schedule: [ScheduledInputEvent]

  init(schedule: [ScheduledInputEvent]) {
    self.schedule = schedule
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let schedule = self.schedule
      let task = Task {
        // Virtual clock: each scheduled delay advances the timestamp stamped
        // onto the event rather than being slept through, so drag-release
        // velocity is deterministic and independent of wall-clock pacing.
        var virtualClock = MonotonicInstant.now()
        for item in schedule {
          virtualClock = virtualClock.advanced(
            by: .nanoseconds(Int64(item.delayNanoseconds))
          )
          continuation.yield(restampedInputEvent(item.event, at: virtualClock))
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

/// Re-stamps a scripted mouse event with a virtual timestamp so the runtime's
/// gesture velocity tracker sees a deterministic inter-event interval. Non-mouse
/// events are returned unchanged.
private func restampedInputEvent(
  _ event: InputEvent,
  at timestamp: MonotonicInstant
) -> InputEvent {
  guard case .mouse(var mouseEvent) = event else {
    return event
  }
  mouseEvent.timestamp = timestamp
  return .mouse(mouseEvent)
}

private actor AwaitedInputWaitFailureRecorder {
  private var failure: StageBudgetExceeded?

  func record(_ failure: StageBudgetExceeded) {
    self.failure = failure
  }

  func requireNoFailure() throws {
    if let failure {
      throw failure
    }
  }
}

private final class AwaitedTerminalInputReader: TerminalInputReading {
  private let steps: [AwaitedTerminalInputStep]
  private let frameSignal: MainActorConditionSignal
  private let stageClock: ManualStageClock
  private let waitBudget: ProgressBudget
  private let waitFailure = AwaitedInputWaitFailureRecorder()

  init(
    frameSignal: MainActorConditionSignal,
    stageClock: ManualStageClock,
    waitBudget: ProgressBudget = ProgressBudget(stages: 240),
    steps: [AwaitedTerminalInputStep]
  ) {
    self.frameSignal = frameSignal
    self.stageClock = stageClock
    self.waitBudget = waitBudget
    self.steps = steps
  }

  @MainActor
  func requireNoWaitFailure() async throws {
    try await waitFailure.requireNoFailure()
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let stageClock = self.stageClock
      let waitBudget = self.waitBudget
      let waitFailure = self.waitFailure
      let task = Task { @MainActor in
        // Virtual clock: a step's delay advances the timestamp stamped onto
        // the event rather than being slept through (see restampedInputEvent).
        var virtualClock = MonotonicInstant.now()
        for (index, step) in steps.enumerated() {
          switch step {
          case .event(let event, let delayNanoseconds):
            virtualClock = virtualClock.advanced(
              by: .nanoseconds(Int64(delayNanoseconds))
            )
            stageClock.advance()
            continuation.yield(restampedInputEvent(event, at: virtualClock))
          case .eventFrom(let delayNanoseconds, let provider):
            virtualClock = virtualClock.advanced(
              by: .nanoseconds(Int64(delayNanoseconds))
            )
            stageClock.advance()
            continuation.yield(restampedInputEvent(provider(), at: virtualClock))
          case .awaitCondition(let predicate):
            do {
              try await frameSignal.wait(
                until: predicate,
                for: "fullscreen awaited input step \(index)",
                within: waitBudget,
                on: stageClock
              )
            } catch let failure as StageBudgetExceeded {
              await waitFailure.record(failure)
              continuation.finish()
              return
            } catch {
              continuation.finish()
              return
            }
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class GestureRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let stageClock = ManualStageClock()
  private(set) var surfaces: [RasterSurface] = []

  /// Notified after every present, so an awaited input step can re-check its
  /// predicate the instant a frame lands instead of polling under a timeout.
  let frameSignal = MainActorConditionSignal()

  init(size: CellSize) {
    self.surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    surfaces.append(surface)
    stageClock.advance()
    // The run loop only ever presents on the MainActor; `assumeIsolated`
    // bridges this nonisolated witness to the MainActor-isolated signal.
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

@MainActor
private final class PhysicsReleaseCapture {
  var surfaceCountAtRelease = 0
}

@MainActor
private final class PhysicsSecondDragCapture {
  var secondStart = Point.zero
  var secondEnd = Point.zero
}

@MainActor
private func runHarness<V: View>(
  host: GestureRecordingHost,
  terminalSize: CellSize,
  rootIdentity: Identity,
  viewBuilder: @escaping () -> V,
  eventSchedule: [ScheduledInputEvent]
) async throws -> RunLoopResult<Int> {
  try await runHarness(
    host: host,
    terminalSize: terminalSize,
    rootIdentity: rootIdentity,
    viewBuilder: viewBuilder,
    terminalInputReader: ScheduledTerminalInputReader(schedule: eventSchedule)
  )
}

@MainActor
private func runHarness<V: View>(
  host: GestureRecordingHost,
  terminalSize: CellSize,
  rootIdentity: Identity,
  viewBuilder: @escaping () -> V,
  terminalInputReader: any TerminalInputReading
) async throws -> RunLoopResult<Int> {
  var env = EnvironmentValues()
  env.terminalSize = terminalSize
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: host,
    terminalInputReader: terminalInputReader,
    signalReader: nil,
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [rootIdentity]
    ),
    environmentValues: env,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in viewBuilder() }
  )
  return try await runLoop.run()
}

private func centerPoint(of rect: CellRect) -> Point {
  Point(
    CellPoint(
      x: rect.origin.x + rect.size.width / 2,
      y: rect.origin.y + rect.size.height / 2
    )
  )
}

private func firstShapeBounds(in node: PlacedNode) -> CellRect? {
  if case .shape = node.drawPayload {
    return node.bounds
  }
  for child in node.children {
    if let match = firstShapeBounds(in: child) {
      return match
    }
  }
  return nil
}

private func brailleBounds(in surface: RasterSurface) -> CellRect? {
  var minX = Int.max
  var minY = Int.max
  var maxX = Int.min
  var maxY = Int.min

  for (y, line) in surface.lines.enumerated() {
    var x = 0
    for scalar in line.unicodeScalars {
      if (0x2800...0x28FF).contains(Int(scalar.value)) {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
      }
      x += 1
    }
  }

  guard minX <= maxX, minY <= maxY else {
    return nil
  }
  return CellRect(
    origin: CellPoint(x: minX, y: minY),
    size: CellSize(width: maxX - minX + 1, height: maxY - minY + 1)
  )
}

private func centeredBallOriginX(
  over brick: LogoBrick,
  logoOrigin: CellPoint,
  metrics: CellPixelMetrics
) -> Int {
  let ball = LogoBreakerGame.ballGeometry(at: .zero, metrics: metrics)
  let centerX = Double(logoOrigin.x + brick.x) + Double(brick.width) / 2
  return fixedCells(centerX - ball.radiusX)
}

private func fixedBallOrigin(
  center: Point,
  metrics: CellPixelMetrics
) -> FullScreenToyPhysics.FixedPoint {
  let ball = LogoBreakerGame.ballGeometry(at: .zero, metrics: metrics)
  return FullScreenToyPhysics.FixedPoint(
    x: fixedCells(center.x - ball.radiusX),
    y: fixedCells(center.y - ball.radiusY)
  )
}

private func fixedCells(_ value: Double) -> Int {
  Int((value * Double(FullScreenToyPhysics.fixedScale)).rounded())
}

private func deduplicated(
  _ surfaces: [RasterSurface]
) -> [RasterSurface] {
  var result: [RasterSurface] = []
  result.reserveCapacity(surfaces.count)
  for surface in surfaces where result.last != surface {
    result.append(surface)
  }
  return result
}
