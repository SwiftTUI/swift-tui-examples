import SwiftTUIRuntime

/// Initial gallery tab: the SwiftTUI mark becomes a brick-breaker field.
///
/// The bricks are the same half-block terminal cells the old landing tab used
/// for the logo. The ball reuses the gallery physics toy's drag/release,
/// gravity, and boundary-bounce model, then removes any logo cell it crosses.
struct LogoTab: View {
  @State private var ballState = FullScreenToyPhysics.State()
  @State private var brokenBrickIDs: Set<Int> = []
  @State private var didSeedInitialPosition = false
  @State private var isDragging = false
  @GestureState private var dragOffset = Vector.zero

  var body: some View {
    GeometryReader { proxy in
      let bounds = proxy.size
      let metrics = proxy.cellPixelMetrics
      let fieldBounds = FullScreenToyPhysics.fieldBounds(from: bounds)
      let current = FullScreenToyPhysics.displayPosition(
        for: ballState,
        dragOffset: dragOffset,
        in: fieldBounds,
        metrics: metrics
      )
      let ballGeometry = LogoBreakerGame.ballGeometry(
        at: current,
        metrics: metrics
      )
      let drawing = LogoBreakerDrawing(
        logoOrigin: LogoBreakerGame.logoOrigin(in: fieldBounds),
        brokenBrickIDs: brokenBrickIDs,
        ballCenter: ballGeometry.center,
        ballRadiusX: ballGeometry.radiusX,
        ballRadiusY: ballGeometry.radiusY
      )
      let ballRect = CellRect(
        origin: current.snapped(.toNearestOrAwayFromZero),
        size: CellSize(
          width: FullScreenToyPhysics.diameter,
          height: ballGeometry.cellHeight
        )
      )

      Canvas(drawing, grid: .braille2x4)
        .foregroundStyle(.cyan)
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .background(Color.black)
        .contentShape(ballRect)
        .gesture(dragGesture(in: fieldBounds, metrics: metrics))
        .task(id: FullScreenToyPhysics.BoundsID(size: fieldBounds)) { @MainActor in
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
      .updating($dragOffset) { value, state, _ in
        state = value.translation
      }
      .onChanged { _ in
        isDragging = true
      }
      .onEnded { value in
        FullScreenToyPhysics.applyRelease(
          to: &ballState,
          translation: value.translation,
          velocity: value.velocity,
          in: bounds,
          metrics: metrics
        )
        isDragging = false
      }
  }

  @MainActor
  private func runGameLoop(
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) async {
    if !didSeedInitialPosition {
      ballState = FullScreenToyPhysics.spawnState(in: bounds, metrics: metrics)
      didSeedInitialPosition = true
    } else {
      ballState = FullScreenToyPhysics.clamped(ballState, in: bounds, metrics: metrics)
    }

    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: FullScreenToyPhysics.tickNanoseconds)
      guard !isDragging else {
        continue
      }

      var nextBall = ballState
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
      ballState = nextBall
      brokenBrickIDs = nextBrokenBricks
    }
  }
}

struct LogoBreakerGame {
  struct BallGeometry: Equatable, Sendable {
    let center: Point
    let radiusX: Double
    let radiusY: Double
    let cellHeight: Int
  }

  static func logoOrigin(in bounds: CellSize) -> CellPoint {
    CellPoint(
      x: max(0, (bounds.width - LogoArt.cellWidth) / 2),
      y: max(0, min(2, (bounds.height - LogoArt.cellHeight) / 4))
    )
  }

  static func ballGeometry(
    at position: Point,
    metrics: CellPixelMetrics
  ) -> BallGeometry {
    let cellHeight = ballCellHeight(metrics: metrics)
    let radiusX = Double(FullScreenToyPhysics.diameter) / 2
    let radiusY = Double(cellHeight) / 2
    return BallGeometry(
      center: Point(x: position.x + radiusX, y: position.y + radiusY),
      radiusX: radiusX,
      radiusY: radiusY,
      cellHeight: cellHeight
    )
  }

  static func ballCellHeight(metrics: CellPixelMetrics) -> Int {
    max(
      1,
      Int((Double(FullScreenToyPhysics.diameter) / metrics.aspectRatio).rounded())
    )
  }

  @discardableResult
  static func step(
    _ state: inout FullScreenToyPhysics.State,
    brokenBrickIDs: inout Set<Int>,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> Bool {
    let previous = state
    let previousRect = ballRect(for: previous, in: bounds, metrics: metrics)

    FullScreenToyPhysics.step(&state, in: bounds, metrics: metrics)

    let nextRect = ballRect(for: state, in: bounds, metrics: metrics)
    guard let collision = firstCollision(
      from: previousRect,
      to: nextRect,
      brokenBrickIDs: brokenBrickIDs,
      logoOrigin: logoOrigin(in: bounds)
    ) else {
      return state != previous
    }

    let oldBrokenCount = brokenBrickIDs.count
    for hit in collision.hits {
      brokenBrickIDs.insert(hit.brick.id)
    }
    state.position = fixedPosition(
      for: previousRect.moved(
        dx: (nextRect.minX - previousRect.minX) * collision.time,
        dy: (nextRect.minY - previousRect.minY) * collision.time
      )
    )
    reflectVelocity(
      &state.velocity,
      along: collision.axis,
      deltaX: nextRect.minX - previousRect.minX,
      deltaY: nextRect.minY - previousRect.minY
    )
    state = FullScreenToyPhysics.clamped(state, in: bounds, metrics: metrics)

    return state != previous || brokenBrickIDs.count != oldBrokenCount
  }

  private static func ballRect(
    for state: FullScreenToyPhysics.State,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> LogoBreakerRect {
    let position = FullScreenToyPhysics.displayPosition(
      for: state,
      dragOffset: .zero,
      in: bounds,
      metrics: metrics
    )
    return LogoBreakerRect(
      minX: position.x,
      minY: position.y,
      maxX: position.x + Double(FullScreenToyPhysics.diameter),
      maxY: position.y + Double(ballCellHeight(metrics: metrics))
    )
  }

  private static func firstCollision(
    from startRect: LogoBreakerRect,
    to endRect: LogoBreakerRect,
    brokenBrickIDs: Set<Int>,
    logoOrigin: CellPoint
  ) -> LogoBreakerCollision? {
    let dx = endRect.minX - startRect.minX
    let dy = endRect.minY - startRect.minY
    let hits = LogoArt.brickCells.compactMap { brick -> LogoBreakerSweptHit? in
      guard !brokenBrickIDs.contains(brick.id) else {
        return nil
      }
      return sweptHit(
        from: startRect,
        dx: dx,
        dy: dy,
        x: logoOrigin.x + brick.x,
        y: logoOrigin.y + brick.y
      ).map {
        LogoBreakerSweptHit(brick: brick, time: $0.time, axis: $0.axis)
      }
    }
    guard let firstTime = hits.map(\.time).min() else {
      return nil
    }
    let firstHits = hits.filter { abs($0.time - firstTime) <= 0.000_001 }
    guard !firstHits.isEmpty else {
      return nil
    }
    return LogoBreakerCollision(
      time: firstTime,
      axis: collisionAxis(for: firstHits, dx: dx, dy: dy),
      hits: firstHits
    )
  }

  private static func sweptHit(
    from rect: LogoBreakerRect,
    dx: Double,
    dy: Double,
    x: Int,
    y: Int
  ) -> (time: Double, axis: LogoBreakerCollisionAxis)? {
    let brick = LogoBreakerRect(
      minX: Double(x),
      minY: Double(y),
      maxX: Double(x + 1),
      maxY: Double(y + 1)
    )
    let xRange = sweptAxisRange(
      min: rect.minX,
      max: rect.maxX,
      obstacleMin: brick.minX,
      obstacleMax: brick.maxX,
      delta: dx
    )
    let yRange = sweptAxisRange(
      min: rect.minY,
      max: rect.maxY,
      obstacleMin: brick.minY,
      obstacleMax: brick.maxY,
      delta: dy
    )
    guard let xRange, let yRange else {
      return nil
    }

    let entry = max(xRange.entry, yRange.entry, 0)
    let exit = min(xRange.exit, yRange.exit, 1)
    guard entry <= exit, entry <= 1 else {
      return nil
    }

    let axis: LogoBreakerCollisionAxis
    if xRange.entry == yRange.entry {
      axis = abs(dx) > abs(dy) ? .horizontal : .vertical
    } else {
      axis = xRange.entry > yRange.entry ? .horizontal : .vertical
    }
    return (time: entry, axis: axis)
  }

  private static func sweptAxisRange(
    min: Double,
    max: Double,
    obstacleMin: Double,
    obstacleMax: Double,
    delta: Double
  ) -> (entry: Double, exit: Double)? {
    guard delta != 0 else {
      guard max >= obstacleMin, min <= obstacleMax else {
        return nil
      }
      return (entry: -.infinity, exit: .infinity)
    }

    if delta > 0 {
      return (
        entry: (obstacleMin - max) / delta,
        exit: (obstacleMax - min) / delta
      )
    } else {
      return (
        entry: (obstacleMax - min) / delta,
        exit: (obstacleMin - max) / delta
      )
    }
  }

  private static func reflectVelocity(
    _ velocity: inout FullScreenToyPhysics.FixedVelocity,
    along axis: LogoBreakerCollisionAxis,
    deltaX: Double,
    deltaY: Double
  ) {
    switch axis {
    case .horizontal:
      let direction = deltaX > 0 ? -1 : 1
      velocity.x = reflected(
        velocity.x,
        direction: direction,
        numerator: FullScreenToyPhysics.wallBounceNumerator,
        denominator: FullScreenToyPhysics.wallBounceDenominator
      )
    case .vertical:
      let direction = deltaY > 0 ? -1 : 1
      velocity.y = reflected(
        velocity.y,
        direction: direction,
        numerator: FullScreenToyPhysics.wallBounceNumerator,
        denominator: FullScreenToyPhysics.wallBounceDenominator
      )
    }
  }

  private static func collisionAxis(
    for hits: [LogoBreakerSweptHit],
    dx: Double,
    dy: Double
  ) -> LogoBreakerCollisionAxis {
    if hits.contains(where: { $0.axis == .vertical }),
      !hits.contains(where: { $0.axis == .horizontal })
    {
      return .vertical
    }
    if hits.contains(where: { $0.axis == .horizontal }),
      !hits.contains(where: { $0.axis == .vertical })
    {
      return .horizontal
    }
    return abs(dx) > abs(dy) ? .horizontal : .vertical
  }

  private static func fixedPosition(
    for rect: LogoBreakerRect
  ) -> FullScreenToyPhysics.FixedPoint {
    FullScreenToyPhysics.FixedPoint(
      x: Int((rect.minX * Double(FullScreenToyPhysics.fixedScale)).rounded()),
      y: Int((rect.minY * Double(FullScreenToyPhysics.fixedScale)).rounded())
    )
  }

  private static func reflected(
    _ component: Int,
    direction: Int,
    numerator: Int,
    denominator: Int
  ) -> Int {
    let magnitude = max(1, abs(component) * numerator / denominator)
    return magnitude * direction
  }
}

private struct LogoBreakerRect: Equatable, Sendable {
  let minX: Double
  let minY: Double
  let maxX: Double
  let maxY: Double

  var center: Point {
    Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
  }

  func moved(dx: Double, dy: Double) -> LogoBreakerRect {
    LogoBreakerRect(
      minX: minX + dx,
      minY: minY + dy,
      maxX: maxX + dx,
      maxY: maxY + dy
    )
  }

  func intersectsCell(x: Int, y: Int) -> Bool {
    maxX > Double(x)
      && minX < Double(x + 1)
      && maxY > Double(y)
      && minY < Double(y + 1)
  }
}

private enum LogoBreakerCollisionAxis: Equatable, Sendable {
  case horizontal
  case vertical
}

private struct LogoBreakerSweptHit: Equatable, Sendable {
  let brick: LogoBrickCell
  let time: Double
  let axis: LogoBreakerCollisionAxis
}

private struct LogoBreakerCollision: Equatable, Sendable {
  let time: Double
  let axis: LogoBreakerCollisionAxis
  let hits: [LogoBreakerSweptHit]
}

private struct LogoBreakerDrawing: CanvasDrawing, Equatable {
  let logoOrigin: CellPoint
  let brokenBrickIDs: Set<Int>
  let ballCenter: Point
  let ballRadiusX: Double
  let ballRadiusY: Double

  func draw(into context: inout CanvasContext) {
    for brick in LogoArt.brickCells where !brokenBrickIDs.contains(brick.id) {
      draw(brick, into: &context)
    }

    context.foreground = .cyan
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
