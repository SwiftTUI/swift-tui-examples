import SwiftTUIRuntime

/// Initial gallery tab: the SwiftTUI mark becomes a brick-breaker field.
///
/// The bricks are the original source pixels from the logo, each rendered as two
/// horizontal half-block terminal cells. The ball is a plain `PhysicsBody` from
/// the reusable ``ArcadePhysics`` core: it falls under gravity, bounces off the
/// field walls, can be dragged and flung, and removes any logo brick it sweeps
/// through. `LogoBreakerGame` is the thin game layer that composes the field
/// simulation (`PhysicsIntegrator`) with the obstacle-collision primitive
/// (`SweptCircle`).
struct LogoTab: View {
  @State private var ball = LogoBreakerGame.makeInitialBody()
  @State private var brokenBrickIDs: Set<Int> = []
  @State private var didSeedInitialPosition = false
  @State private var isDragging = false
  @State private var dragTranslation = Vector.zero

  var body: some View {
    GeometryReader { proxy in
      let bounds = proxy.size
      let metrics = proxy.cellPixelMetrics
      let fieldBounds = LogoBreakerGame.fieldBounds(from: bounds)
      let cellCenter = LogoBreakerGame.displayCenter(for: ball, in: fieldBounds, metrics: metrics)
      let geometry = LogoBreakerGame.ballGeometry(at: cellCenter, metrics: metrics)
      let drawing = LogoBreakerDrawing(
        logoOrigin: LogoBreakerGame.logoOrigin(in: fieldBounds),
        brokenBrickIDs: brokenBrickIDs,
        ballCenter: geometry.center,
        ballRadiusX: geometry.radiusX,
        ballRadiusY: geometry.radiusY,
        isGrabbed: isDragging
      )
      let ballRect = CellRect(
        origin: Point(
          x: cellCenter.x - geometry.radiusX,
          y: cellCenter.y - geometry.radiusY
        ).snapped(.toNearestOrAwayFromZero),
        size: CellSize(
          width: LogoBreakerGame.ballDiameter,
          height: geometry.cellHeight
        )
      )

      Canvas(drawing, grid: .braille2x4)
        .foregroundStyle(.cyan)
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .background(Color.black)
        .contentShape(ballRect)
        .gesture(dragGesture(in: fieldBounds, metrics: metrics))
        .task(id: LogoBreakerGame.BoundsID(size: fieldBounds)) { @MainActor in
          await runGameLoop(in: fieldBounds, metrics: metrics)
        }
    }
    .border(.tint, set: .rounded)
  }

  private func dragGesture(
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> some Gesture {
    DragGesture()
      .onChanged { value in
        if !isDragging {
          LogoBreakerGame.stop(&ball)
          dragTranslation = .zero
          isDragging = true
        }

        var nextBall = ball
        var nextBrokenBricks = brokenBrickIDs
        let increment = Vector(
          dx: value.translation.dx - dragTranslation.dx,
          dy: value.translation.dy - dragTranslation.dy
        )
        let outcome = LogoBreakerGame.drag(
          &nextBall,
          brokenBrickIDs: &nextBrokenBricks,
          by: increment,
          in: bounds,
          metrics: metrics
        )
        switch outcome {
        case .tracking, .hitBrick:
          ball = nextBall
          brokenBrickIDs = nextBrokenBricks
          dragTranslation = value.translation
        }
      }
      .onEnded { value in
        defer {
          dragTranslation = .zero
          isDragging = false
        }
        LogoBreakerGame.release(
          &ball,
          gestureVelocity: value.velocity,
          in: bounds,
          metrics: metrics
        )
      }
  }

  @MainActor
  private func runGameLoop(
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) async {
    if !didSeedInitialPosition {
      ball = LogoBreakerGame.spawnBody(in: bounds, metrics: metrics)
      didSeedInitialPosition = true
    } else {
      ball = LogoBreakerGame.clampedBody(ball, in: bounds, metrics: metrics)
    }

    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: LogoBreakerGame.tickNanoseconds)
      guard !isDragging else {
        continue
      }

      var nextBall = ball
      var nextBrokenBricks = brokenBrickIDs
      let didChange = LogoBreakerGame.step(
        &nextBall,
        brokenBrickIDs: &nextBrokenBricks,
        in: bounds,
        metrics: metrics
      )
      guard didChange else {
        continue
      }
      ball = nextBall
      brokenBrickIDs = nextBrokenBricks
    }
  }
}

/// The brick-breaker game built on the reusable ``ArcadePhysics`` core. It owns
/// the logo geometry, converts between terminal cells and the simulation's
/// world space, and composes `PhysicsIntegrator` (field) with `SweptCircle`
/// (bricks). All physical tuning lives in ``config``.
enum LogoBreakerGame {
  /// Ball width in terminal cells. The radius is half this, in world units.
  static let ballDiameter = 6
  /// Game-loop tick. The physics `dt` is derived from it so they stay in sync.
  static let tickNanoseconds: UInt64 = 40_000_000

  /// Physics tuning for this game. `dt` matches the loop tick exactly.
  static let config: PhysicsConfig = {
    var config = PhysicsConfig.arcade
    config.dt = Double(tickNanoseconds) / 1_000_000_000
    return config
  }()

  /// Ball radius in isotropic world units (cell widths).
  static var ballRadius: Double { Double(ballDiameter) / 2 }

  /// Initial launch velocity (world units/sec): up and gently to the right.
  private static let launchVelocity = Vector(dx: 16, dy: -60)

  /// Restarts the game loop when the playfield size changes.
  struct BoundsID: Hashable {
    let width: Int
    let height: Int

    init(size: CellSize) {
      width = size.width
      height = size.height
    }
  }

  static func fieldBounds(from bounds: CellSize) -> CellSize {
    bounds
  }

  /// Top-left cell of the centered logo within the field.
  static func logoOrigin(in bounds: CellSize) -> CellPoint {
    CellPoint(
      x: max(0, (bounds.width - LogoArt.cellWidth) / 2),
      y: max(0, min(2, (bounds.height - LogoArt.cellHeight) / 4))
    )
  }

  /// The ball before its position has been seeded by the game loop. Clamped
  /// into the field at render time, so a `.zero` position renders at the
  /// top-left corner.
  static func makeInitialBody() -> PhysicsBody {
    PhysicsBody(position: .zero, velocity: .zero, radius: ballRadius)
  }

  /// A fresh ball at the bottom-center of the field with its launch velocity.
  static func spawnBody(in bounds: CellSize, metrics: CellPixelMetrics) -> PhysicsBody {
    let world = WorldSpace(metrics: metrics)
    let field = field(in: bounds, world: world)
    let limits = field.centerBounds(radius: ballRadius)
    return PhysicsBody(
      position: Point(x: field.bounds.maxX / 2, y: limits.maxY),
      velocity: launchVelocity,
      radius: ballRadius
    )
  }

  /// `body` with its center clamped inside the field.
  static func clampedBody(
    _ body: PhysicsBody,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> PhysicsBody {
    let world = WorldSpace(metrics: metrics)
    let field = field(in: bounds, world: world)
    var clamped = body
    clamped.position = clampedPosition(body.position, in: field, radius: body.radius)
    return clamped
  }

  /// The ball center to draw, in cell space, clamped into the field.
  static func displayCenter(
    for body: PhysicsBody,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> Point {
    let world = WorldSpace(metrics: metrics)
    let field = field(in: bounds, world: world)
    let clamped = clampedPosition(body.position, in: field, radius: body.radius)
    return world.toCell(clamped)
  }

  /// The ball's cell-space drawing geometry: a circle drawn as an ellipse whose
  /// vertical radius is compressed by the cell aspect ratio so it reads round.
  static func ballGeometry(at center: Point, metrics: CellPixelMetrics) -> BallGeometry {
    BallGeometry(
      center: center,
      radiusX: ballRadius,
      radiusY: ballRadius / metrics.aspectRatio,
      cellHeight: ballCellHeight(metrics: metrics)
    )
  }

  /// Height of the ball footprint in whole cells.
  static func ballCellHeight(metrics: CellPixelMetrics) -> Int {
    max(1, Int((Double(ballDiameter) / metrics.aspectRatio).rounded()))
  }

  /// Advances the ball one tick: field simulation, then brick collisions.
  @discardableResult
  static func step(
    _ body: inout PhysicsBody,
    brokenBrickIDs: inout Set<Int>,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> Bool {
    let previous = body
    let oldBrokenCount = brokenBrickIDs.count
    let world = WorldSpace(metrics: metrics)
    let field = field(in: bounds, world: world)
    let logoOrigin = logoOrigin(in: bounds)

    PhysicsIntegrator.step(&body, in: field, config: config)

    let delta = body.position - previous.position
    if let collision = firstBrickCollision(
      center: previous.position,
      radius: body.radius,
      delta: delta,
      brokenBrickIDs: brokenBrickIDs,
      logoOrigin: logoOrigin,
      world: world
    ) {
      let reflected = SweptCircle.reflect(
        body.velocity,
        normal: collision.normal,
        restitution: config.wallRestitution
      )
      // React only to a genuine swept or approaching contact. A `time == 0`
      // overlap where the velocity is *not* approaching means the ball is merely
      // resting in contact with a brick — breaking it then would delete a brick
      // with no motion and, because the broken count changed, keep the otherwise
      // byte-identical rest frame from being elided.
      if collision.time > 0 || reflected != body.velocity {
        for id in collision.hitIDs {
          brokenBrickIDs.insert(id)
        }
        body.position = clampedPosition(
          previous.position + delta * collision.time,
          in: field,
          radius: body.radius
        )
        body.velocity = reflected
      }
    }

    return body != previous || brokenBrickIDs.count != oldBrokenCount
  }

  /// Drags the ball by an incremental cell-space translation. Sweeps the move
  /// against the bricks: a clear move commits (velocity stays zero); a move that
  /// crosses a brick breaks the first one reached while keeping the active drag
  /// captured until the pointer is released.
  @discardableResult
  static func drag(
    _ body: inout PhysicsBody,
    brokenBrickIDs: inout Set<Int>,
    by cellTranslation: Vector,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> LogoBreakerDragOutcome {
    let world = WorldSpace(metrics: metrics)
    let field = field(in: bounds, world: world)
    let logoOrigin = logoOrigin(in: bounds)

    let start = body.position
    let target = clampedPosition(
      start + world.toWorld(cellTranslation),
      in: field,
      radius: body.radius
    )
    let delta = target - start

    if let collision = firstBrickCollision(
      center: start,
      radius: body.radius,
      delta: delta,
      brokenBrickIDs: brokenBrickIDs,
      logoOrigin: logoOrigin,
      world: world
    ) {
      for id in collision.hitIDs {
        brokenBrickIDs.insert(id)
      }
      body.position = clampedPosition(
        start + delta * collision.time,
        in: field,
        radius: body.radius
      )
      body.velocity = .zero
      return .hitBrick
    }

    body.position = target
    body.velocity = .zero
    return .tracking
  }

  /// Converts a release gesture's velocity (cells/sec) into the ball's world
  /// velocity (world units/sec) and clamps the ball into the field.
  static func release(
    _ body: inout PhysicsBody,
    gestureVelocity: Vector,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) {
    let world = WorldSpace(metrics: metrics)
    body = clampedBody(body, in: bounds, metrics: metrics)
    body.velocity = world.toWorld(gestureVelocity)
  }

  /// Halts the ball (used when a drag begins).
  static func stop(_ body: inout PhysicsBody) {
    body.velocity = .zero
  }

  /// The field as a world-space play area.
  static func field(in bounds: CellSize, world: WorldSpace) -> Playfield {
    let worldHeight = world.toWorld(Point(x: 0, y: Double(bounds.height))).y
    return Playfield(
      bounds: AABB(minX: 0, minY: 0, maxX: Double(bounds.width), maxY: worldHeight)
    )
  }

  private static func clampedPosition(
    _ point: Point,
    in field: Playfield,
    radius: Double
  ) -> Point {
    let limits = field.centerBounds(radius: radius)
    return Point(
      x: min(max(limits.minX, point.x), limits.maxX),
      y: min(max(limits.minY, point.y), limits.maxY)
    )
  }

  /// Earliest brick the swept ball touches, with all bricks hit at that instant.
  /// The min-time search and simultaneous-hit normal clustering are the core's
  /// `SweptCircle.firstContact(against:)`; this only maps obstacle indices back
  /// to brick IDs.
  private static func firstBrickCollision(
    center: Point,
    radius: Double,
    delta: Vector,
    brokenBrickIDs: Set<Int>,
    logoOrigin: CellPoint,
    world: WorldSpace
  ) -> BrickCollision? {
    let candidates = LogoArt.bricks.filter { !brokenBrickIDs.contains($0.id) }
    let boxes = candidates.map { brickAABB($0, logoOrigin: logoOrigin, world: world) }
    guard
      let hit = SweptCircle.firstContact(
        center: center,
        radius: radius,
        delta: delta,
        against: boxes
      )
    else {
      return nil
    }
    return BrickCollision(
      time: hit.contact.time,
      normal: hit.contact.normal,
      hitIDs: hit.indices.map { candidates[$0].id }
    )
  }

  private static func brickAABB(
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
}

/// The ball's cell-space drawing geometry.
struct BallGeometry: Equatable, Sendable {
  let center: Point
  let radiusX: Double
  let radiusY: Double
  let cellHeight: Int
}

/// Outcome of a drag step.
enum LogoBreakerDragOutcome: Equatable, Sendable {
  case tracking
  case hitBrick
}

private struct BrickCollision: Equatable, Sendable {
  let time: Double
  let normal: Vector
  let hitIDs: [Int]
}

private struct LogoBreakerDrawing: CanvasDrawing, Equatable {
  let logoOrigin: CellPoint
  let brokenBrickIDs: Set<Int>
  let ballCenter: Point
  let ballRadiusX: Double
  let ballRadiusY: Double
  /// Whether the ball is currently held by a drag; lights the ball up white as
  /// grab feedback.
  let isGrabbed: Bool

  func draw(into context: inout CanvasContext) {
    for brick in LogoArt.bricks where !brokenBrickIDs.contains(brick.id) {
      for cell in brick.cells {
        draw(cell, into: &context)
      }
    }

    context.foreground = isGrabbed ? .white : .cyan
    context.fillEllipse(
      center: ballCenter,
      radiusX: ballRadiusX,
      radiusY: ballRadiusY
    )
  }

  private func draw(
    _ brick: LogoBrickCell,
    into context: inout CanvasContext
  ) {
    let location = CellPoint(
      x: logoOrigin.x + brick.x,
      y: logoOrigin.y + brick.y
    )
    switch (brick.top, brick.bottom) {
    case (nil, nil):
      return
    case (let top?, let bottom?) where top == bottom:
      context.fillCell(top, at: location)
    case (let top?, let bottom?):
      context.setCell(
        at: location,
        character: "▀",
        foreground: top,
        background: bottom
      )
    case (let top?, nil):
      context.setCell(
        at: location,
        character: "▀",
        foreground: top
      )
    case (nil, let bottom?):
      context.setCell(
        at: location,
        character: "▄",
        foreground: bottom
      )
    }
  }
}
