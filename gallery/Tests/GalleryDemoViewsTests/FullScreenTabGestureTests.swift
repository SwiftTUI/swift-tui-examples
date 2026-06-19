import Foundation
@_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite(.serialized)
struct LogoBreakerGestureTests {

  // MARK: - ArcadePhysics core + LogoBreaker game unit tests

  @Test("spawn places the ball at the bottom-center with an upward launch")
  func spawnPlacesBallAtBottomCenter() {
    let bounds = CellSize(width: 40, height: 12)
    let metrics = CellPixelMetrics.estimated
    let world = WorldSpace(metrics: metrics)
    let field = LogoBreakerGame.field(in: bounds, world: world)
    let limits = field.centerBounds(radius: LogoBreakerGame.ballRadius)

    let ball = LogoBreakerGame.spawnBody(in: bounds, metrics: metrics)

    #expect(ball.position.x == field.bounds.maxX / 2)
    #expect(ball.position.y == limits.maxY)
    #expect(ball.velocity.dx > 0)
    #expect(ball.velocity.dy < 0)
    #expect(ball.radius == LogoBreakerGame.ballRadius)
  }

  @Test("gravity pulls the ball down and it bounces up off the floor")
  func gravityBouncesOffFloor() {
    let bounds = CellSize(width: 40, height: 12)
    let world = WorldSpace(metrics: .estimated)
    let field = LogoBreakerGame.field(in: bounds, world: world)
    let limits = field.centerBounds(radius: LogoBreakerGame.ballRadius)
    var body = PhysicsBody(
      position: Point(x: limits.maxX / 2, y: limits.maxY - 0.5),
      velocity: Vector(dx: 0, dy: 40),
      radius: LogoBreakerGame.ballRadius
    )

    PhysicsIntegrator.step(&body, in: field, config: LogoBreakerGame.config)

    #expect(body.position.y <= limits.maxY)
    #expect(body.velocity.dy < 0)
  }

  @Test("the ball reflects off the right wall")
  func reflectsOffRightWall() {
    let bounds = CellSize(width: 40, height: 12)
    let world = WorldSpace(metrics: .estimated)
    let field = LogoBreakerGame.field(in: bounds, world: world)
    let limits = field.centerBounds(radius: LogoBreakerGame.ballRadius)
    var body = PhysicsBody(
      position: Point(x: limits.maxX - 0.5, y: (limits.minY + limits.maxY) / 2),
      velocity: Vector(dx: 40, dy: 0),
      radius: LogoBreakerGame.ballRadius
    )

    PhysicsIntegrator.step(&body, in: field, config: LogoBreakerGame.config)

    #expect(body.position.x == limits.maxX)
    #expect(body.velocity.dx < 0)
  }

  @Test("release converts gesture velocity (cells/sec) into world velocity")
  func releaseConvertsGestureVelocity() {
    let bounds = CellSize(width: 40, height: 12)
    let metrics = CellPixelMetrics.estimated
    var body = PhysicsBody(position: Point(x: 5, y: 5), radius: LogoBreakerGame.ballRadius)

    LogoBreakerGame.release(
      &body,
      gestureVelocity: Vector(dx: 100, dy: -50),
      in: bounds,
      metrics: metrics
    )

    // Aspect ratio 2.0: the vertical component scales by the cell aspect; the
    // horizontal component passes through unchanged.
    #expect(body.velocity == Vector(dx: 100, dy: -100))
    #expect(body.position == Point(x: 5, y: 5))
  }

  @Test("stopping the ball clears its velocity but not its position")
  func stoppingClearsVelocity() {
    var body = PhysicsBody(
      position: Point(x: 12, y: 24),
      velocity: Vector(dx: 40, dy: -18),
      radius: LogoBreakerGame.ballRadius
    )

    LogoBreakerGame.stop(&body)

    #expect(body.position == Point(x: 12, y: 24))
    #expect(body.velocity == .zero)
  }

  @Test("dragging commits the grabbed position without applying gravity")
  func dragCommitsGrabbedPositionWithoutPhysics() {
    let bounds = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let world = WorldSpace(metrics: metrics)
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    var body = PhysicsBody(
      position: Point(x: 20, y: 60),
      velocity: Vector(dx: 0, dy: 100),
      radius: LogoBreakerGame.ballRadius
    )

    let outcome = LogoBreakerGame.drag(
      &body,
      brokenBrickIDs: &brokenBrickIDs,
      by: Vector(dx: 3, dy: -5),
      in: bounds,
      metrics: metrics
    )

    let step = world.toWorld(Vector(dx: 3, dy: -5))
    #expect(outcome == .tracking)
    #expect(body.position == Point(x: 20 + step.dx, y: 60 + step.dy))
    #expect(body.velocity == .zero)
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

  @Test("stepping the ball into a brick removes it and reflects upward")
  func stepBreaksIntersectedBrick() throws {
    let bounds = CellSize(width: 80, height: 24)
    let metrics = CellPixelMetrics.estimated
    let world = WorldSpace(metrics: metrics)
    let logoOrigin = LogoBreakerGame.logoOrigin(in: bounds)
    let ballHeight = LogoBreakerGame.ballCellHeight(metrics: metrics)
    let target = try #require(LogoArt.bricks.first { $0.y > ballHeight })
    let box = brickBox(target, logoOrigin: logoOrigin, world: world)
    let radius = LogoBreakerGame.ballRadius
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(target.id)
    var body = PhysicsBody(
      position: Point(x: (box.minX + box.maxX) / 2, y: box.minY - radius - 0.5),
      velocity: Vector(dx: 0, dy: 30),
      radius: radius
    )

    _ = LogoBreakerGame.step(
      &body,
      brokenBrickIDs: &brokenBrickIDs,
      in: bounds,
      metrics: metrics
    )

    #expect(brokenBrickIDs.contains(target.id))
    #expect(body.velocity.dy < 0)
  }

  @Test("the circle ignores a brick that only overlaps its bounding-box corner")
  func circleIgnoresBoundingBoxCornerOverlap() throws {
    let bounds = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let world = WorldSpace(metrics: metrics)
    let logoOrigin = LogoBreakerGame.logoOrigin(in: bounds)
    let target = try #require(LogoArt.bricks.first { $0.y >= 6 && $0.x >= 4 })
    let box = brickBox(target, logoOrigin: logoOrigin, world: world)
    let radius = LogoBreakerGame.ballRadius
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(target.id)
    // The bounding box overlaps the brick corner, but the circle's curve does
    // not reach it (distance to the corner exceeds the radius).
    var body = PhysicsBody(
      position: Point(x: box.minX - radius * 0.9, y: box.minY - radius * 0.9),
      radius: radius
    )

    let outcome = LogoBreakerGame.drag(
      &body,
      brokenBrickIDs: &brokenBrickIDs,
      by: .zero,
      in: bounds,
      metrics: metrics
    )

    #expect(outcome == .tracking)
    #expect(!brokenBrickIDs.contains(target.id))
  }

  @Test("a glancing corner hit adds horizontal momentum")
  func cornerHitAddsHorizontalMomentum() throws {
    let bounds = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let world = WorldSpace(metrics: metrics)
    let logoOrigin = LogoBreakerGame.logoOrigin(in: bounds)
    let target = try #require(LogoArt.bricks.first { $0.y >= 8 && $0.x >= 4 })
    let box = brickBox(target, logoOrigin: logoOrigin, world: world)
    let radius = LogoBreakerGame.ballRadius
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(target.id)
    // Just left of the brick's top-left corner, falling straight down: the
    // curved corner deflects the ball up and to the left.
    var body = PhysicsBody(
      position: Point(x: box.minX - radius * 0.25, y: box.minY - radius - 1),
      velocity: Vector(dx: 0, dy: 40),
      radius: radius
    )

    _ = LogoBreakerGame.step(
      &body,
      brokenBrickIDs: &brokenBrickIDs,
      in: bounds,
      metrics: metrics
    )

    #expect(brokenBrickIDs.contains(target.id))
    #expect(body.velocity.dx < 0)
    #expect(body.velocity.dy < 0)
  }

  @Test("a fast move sweeps to the first reachable brick, not the far one")
  func sweepsFastMovementToFirstReachableBrick() throws {
    let bounds = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let world = WorldSpace(metrics: metrics)
    let logoOrigin = LogoBreakerGame.logoOrigin(in: bounds)
    let ballHeight = LogoBreakerGame.ballCellHeight(metrics: metrics)
    let pair = try #require(firstReachableBrickPair(ballHeight: ballHeight))
    let nearBox = brickBox(pair.near, logoOrigin: logoOrigin, world: world)
    let farBox = brickBox(pair.far, logoOrigin: logoOrigin, world: world)
    let radius = LogoBreakerGame.ballRadius
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(pair.near.id)
    brokenBrickIDs.remove(pair.far.id)
    let centerY = nearBox.minY - radius - 1
    // Fast enough that a naive (non-swept) move would pass through both bricks.
    let velocityY = ((farBox.maxY - centerY) + radius + 10) / LogoBreakerGame.config.dt
    var body = PhysicsBody(
      position: Point(x: (nearBox.minX + nearBox.maxX) / 2, y: centerY),
      velocity: Vector(dx: 0, dy: velocityY),
      radius: radius
    )

    _ = LogoBreakerGame.step(
      &body,
      brokenBrickIDs: &brokenBrickIDs,
      in: bounds,
      metrics: metrics
    )

    #expect(brokenBrickIDs.contains(pair.near.id))
    #expect(!brokenBrickIDs.contains(pair.far.id))
    #expect(body.velocity.dy < 0)
  }

  @Test("dragging through bricks breaks the first reachable one and drops the drag")
  func dragDropsAtFirstReachableBrick() throws {
    let bounds = CellSize(width: 80, height: 40)
    let metrics = CellPixelMetrics.estimated
    let world = WorldSpace(metrics: metrics)
    let logoOrigin = LogoBreakerGame.logoOrigin(in: bounds)
    let ballHeight = LogoBreakerGame.ballCellHeight(metrics: metrics)
    let pair = try #require(firstReachableBrickPair(ballHeight: ballHeight))
    let nearBox = brickBox(pair.near, logoOrigin: logoOrigin, world: world)
    let farBox = brickBox(pair.far, logoOrigin: logoOrigin, world: world)
    let radius = LogoBreakerGame.ballRadius
    var brokenBrickIDs = Set(LogoArt.bricks.map(\.id))
    brokenBrickIDs.remove(pair.near.id)
    brokenBrickIDs.remove(pair.far.id)
    let centerY = nearBox.minY - radius - 1
    var body = PhysicsBody(
      position: Point(x: (nearBox.minX + nearBox.maxX) / 2, y: centerY),
      radius: radius
    )
    // Drag straight down, far enough (in cells) to pass both bricks.
    let dragCells = ((farBox.maxY - centerY) + radius + 10) / world.aspect

    let outcome = LogoBreakerGame.drag(
      &body,
      brokenBrickIDs: &brokenBrickIDs,
      by: Vector(dx: 0, dy: dragCells),
      in: bounds,
      metrics: metrics
    )

    #expect(outcome == .dropped)
    #expect(brokenBrickIDs.contains(pair.near.id))
    #expect(!brokenBrickIDs.contains(pair.far.id))
    #expect(body.velocity == .zero)
  }

  @Test("a resting ball is a fixed point: stepping leaves it byte-identical")
  func restingBallIsAFixedPoint() {
    let bounds = CellSize(width: 40, height: 12)
    let world = WorldSpace(metrics: .estimated)
    let field = LogoBreakerGame.field(in: bounds, world: world)
    let limits = field.centerBounds(radius: LogoBreakerGame.ballRadius)
    var body = PhysicsBody(
      position: Point(x: (limits.minX + limits.maxX) / 2, y: limits.maxY),
      velocity: .zero,
      radius: LogoBreakerGame.ballRadius
    )
    let before = body

    let changed = PhysicsIntegrator.step(&body, in: field, config: LogoBreakerGame.config)

    #expect(changed == false)
    #expect(body == before)
  }

  @Test("a launched ball settles to an exact rest within a bounded budget")
  func launchedBallSettlesToRest() {
    let bounds = CellSize(width: 40, height: 12)
    let world = WorldSpace(metrics: .estimated)
    let field = LogoBreakerGame.field(in: bounds, world: world)
    var body = LogoBreakerGame.spawnBody(in: bounds, metrics: .estimated)

    var settledAfter: Int?
    for tick in 0..<2000 {
      let changed = PhysicsIntegrator.step(&body, in: field, config: LogoBreakerGame.config)
      if !changed {
        settledAfter = tick
        break
      }
    }

    #expect(settledAfter != nil, "the ball should come to rest within 2000 ticks")

    // Once settled, the loop must see no further change so it can elide frames.
    let before = body
    let changed = PhysicsIntegrator.step(&body, in: field, config: LogoBreakerGame.config)
    #expect(changed == false)
    #expect(body == before)
  }

  @Test("a brick the resting ball merely touches is not deleted, and the frame elides")
  func restingBallDoesNotDeleteTouchedBrick() throws {
    // A short field so the logo reaches the floor: a ball at rest there can end
    // up touching a surviving brick. Stepping must NOT delete it (no approach,
    // no motion) and must report no change so the host elides the rest frame.
    let bounds = CellSize(width: 40, height: 12)
    let metrics = CellPixelMetrics.estimated
    let world = WorldSpace(metrics: metrics)
    let field = LogoBreakerGame.field(in: bounds, world: world)
    let logoOrigin = LogoBreakerGame.logoOrigin(in: bounds)
    let limits = field.centerBounds(radius: LogoBreakerGame.ballRadius)
    let radius = LogoBreakerGame.ballRadius

    func restCenter(over box: AABB) -> Point {
      Point(x: min(max(limits.minX, (box.minX + box.maxX) / 2), limits.maxX), y: limits.maxY)
    }
    let target = try #require(
      LogoArt.bricks.first { brick in
        let box = brickBox(brick, logoOrigin: logoOrigin, world: world)
        return SweptCircle.overlapNormal(center: restCenter(over: box), radius: radius, box: box)
          != nil
      },
      "test geometry must place a brick under the resting ball")

    var brokenBrickIDs: Set<Int> = []
    var body = PhysicsBody(
      position: restCenter(over: brickBox(target, logoOrigin: logoOrigin, world: world)),
      velocity: .zero,
      radius: radius
    )
    let before = body

    let changed = LogoBreakerGame.step(
      &body,
      brokenBrickIDs: &brokenBrickIDs,
      in: bounds,
      metrics: metrics
    )

    #expect(brokenBrickIDs.isEmpty, "a resting ball must not delete bricks it merely touches")
    #expect(changed == false, "a resting ball touching a brick must still elide its frame")
    #expect(body == before)
  }

  @Test("the settle invariant restSpeed > gravity*dt is mechanically checkable")
  func settleInvariantIsCheckable() {
    #expect(PhysicsConfig.arcade.isSettleable)
    #expect(LogoBreakerGame.config.isSettleable)

    var mistuned = PhysicsConfig.arcade
    mistuned.gravity = 200
    mistuned.restSpeed = 6
    #expect(mistuned.settleImpulse == 8)
    #expect(!mistuned.isSettleable, "restSpeed 6 cannot absorb an 8/tick gravity impulse")
  }

  @Test("the multi-box sweep returns the nearer box, and clusters flush hits")
  func multiBoxSweepPicksNearestAndClustersTies() throws {
    let near = AABB(minX: 0, minY: 10, maxX: 10, maxY: 12)
    let far = AABB(minX: 0, minY: 30, maxX: 10, maxY: 32)
    let radius = 1.0

    // Swept straight down from above both: the nearer box is hit first.
    let nearest = try #require(
      SweptCircle.firstContact(
        center: Point(x: 5, y: 0),
        radius: radius,
        delta: Vector(dx: 0, dy: 40),
        against: [near, far]
      ))
    #expect(nearest.indices == [0])
    #expect(nearest.contact.normal.dy < 0)

    // Two adjacent boxes whose top faces are flush at the same height are hit
    // together; combining their up-normals keeps the reflection vertical instead
    // of biasing toward one face.
    let left = AABB(minX: 0, minY: 10, maxX: 5, maxY: 12)
    let right = AABB(minX: 5, minY: 10, maxX: 10, maxY: 12)
    let flush = try #require(
      SweptCircle.firstContact(
        center: Point(x: 5, y: 0),
        radius: radius,
        delta: Vector(dx: 0, dy: 40),
        against: [left, right]
      ))
    #expect(Set(flush.indices) == [0, 1])
    #expect(abs(flush.contact.normal.dx) < 1e-9)
    #expect(flush.contact.normal.dy < 0)
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
      Int((Double(LogoBreakerGame.ballDiameter) / metrics.aspectRatio).rounded())
    )

    // Locate the ball's interaction region by its distinctive size
    // (diameter × ballHeight). Other regions in the snapshot are the
    // surrounding chrome (toolbar, palette command, etc.) which have
    // different dimensions.
    let ballSize = CellSize(
      width: LogoBreakerGame.ballDiameter,
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

private func brickBox(
  _ brick: LogoBrick,
  logoOrigin: CellPoint,
  world: WorldSpace
) -> AABB {
  world.toWorld(
    cellX: Double(logoOrigin.x + brick.x),
    cellY: Double(logoOrigin.y + brick.y),
    width: Double(brick.width),
    height: Double(brick.height)
  )
}

private func firstReachableBrickPair(
  ballHeight: Int
) -> (near: LogoBrick, far: LogoBrick)? {
  let columns = Dictionary(grouping: LogoArt.bricks, by: { $0.x })
  return columns.values.compactMap { cells -> (near: LogoBrick, far: LogoBrick)? in
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
