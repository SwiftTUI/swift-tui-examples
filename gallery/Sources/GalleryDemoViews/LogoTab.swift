import SwiftTUIRuntime

/// Initial gallery tab: the SwiftTUI mark becomes a brick-breaker field.
///
/// The bricks are the original source pixels from the logo, with each source
/// pixel rendered as two horizontal half-block terminal cells. The ball reuses
/// the gallery physics toy's drag/release, gravity, and boundary-bounce model,
/// then removes any logo source pixel it crosses.
struct LogoTab: View {
  @State private var ballState = FullScreenToyPhysics.State()
  @State private var brokenBrickIDs: Set<Int> = []
  @State private var didSeedInitialPosition = false
  @State private var isDragging = false
  @State private var dragTranslation = Vector.zero
  @State private var didDropCurrentDrag = false

  var body: some View {
    GeometryReader { proxy in
      let bounds = proxy.size
      let metrics = proxy.cellPixelMetrics
      let fieldBounds = FullScreenToyPhysics.fieldBounds(from: bounds)
      let current = FullScreenToyPhysics.displayPosition(
        for: ballState,
        dragOffset: .zero,
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
      .onChanged { value in
        guard !didDropCurrentDrag else {
          return
        }
        if !isDragging {
          FullScreenToyPhysics.stop(&ballState)
          dragTranslation = .zero
          isDragging = true
        }

        var nextBall = ballState
        var nextBrokenBricks = brokenBrickIDs
        let outcome = LogoBreakerGame.drag(
          &nextBall,
          brokenBrickIDs: &nextBrokenBricks,
          to: Vector(
            dx: value.translation.dx - dragTranslation.dx,
            dy: value.translation.dy - dragTranslation.dy
          ),
          in: bounds,
          metrics: metrics
        )
        switch outcome {
        case .tracking:
          ballState = nextBall
          brokenBrickIDs = nextBrokenBricks
          dragTranslation = value.translation
        case .dropped:
          ballState = nextBall
          brokenBrickIDs = nextBrokenBricks
          dragTranslation = .zero
          isDragging = false
          didDropCurrentDrag = true
        }
      }
      .onEnded { value in
        defer {
          dragTranslation = .zero
          isDragging = false
          didDropCurrentDrag = false
        }
        guard !didDropCurrentDrag else {
          return
        }
        FullScreenToyPhysics.applyReleaseVelocity(
          to: &ballState,
          velocity: value.velocity,
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
    let previousBall = ballBody(for: previous, in: bounds, metrics: metrics)

    FullScreenToyPhysics.step(&state, in: bounds, metrics: metrics)

    let nextBall = ballBody(for: state, in: bounds, metrics: metrics)
    guard let collision = firstCollision(
      from: previousBall,
      to: nextBall,
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
      for: previousBall.moved(
        dx: (nextBall.center.x - previousBall.center.x) * collision.time,
        dy: (nextBall.center.y - previousBall.center.y) * collision.time
      )
    )
    reflectVelocity(
      &state.velocity,
      normal: collision.normal,
      yScale: previousBall.yScale
    )
    state = FullScreenToyPhysics.clamped(state, in: bounds, metrics: metrics)

    return state != previous || brokenBrickIDs.count != oldBrokenCount
  }

  @discardableResult
  static func drag(
    _ state: inout FullScreenToyPhysics.State,
    brokenBrickIDs: inout Set<Int>,
    from currentTranslation: Vector = .zero,
    to proposedTranslation: Vector,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> LogoBreakerDragOutcome {
    let startBall = ballBody(
      for: draggedState(
        state,
        translation: currentTranslation,
        in: bounds,
        metrics: metrics
      ),
      in: bounds,
      metrics: metrics
    )
    let endBall = ballBody(
      for: draggedState(
        state,
        translation: proposedTranslation,
        in: bounds,
        metrics: metrics
      ),
      in: bounds,
      metrics: metrics
    )

    guard let collision = firstCollision(
      from: startBall,
      to: endBall,
      brokenBrickIDs: brokenBrickIDs,
      logoOrigin: logoOrigin(in: bounds)
    ) else {
      state = draggedState(
        state,
        translation: proposedTranslation,
        in: bounds,
        metrics: metrics
      )
      FullScreenToyPhysics.stop(&state)
      return .tracking
    }

    for hit in collision.hits {
      brokenBrickIDs.insert(hit.brick.id)
    }
    state.position = fixedPosition(
      for: startBall.moved(
        dx: (endBall.center.x - startBall.center.x) * collision.time,
        dy: (endBall.center.y - startBall.center.y) * collision.time
      )
    )
    FullScreenToyPhysics.stop(&state)
    state = FullScreenToyPhysics.clamped(state, in: bounds, metrics: metrics)
    return .dropped
  }

  private static func draggedState(
    _ state: FullScreenToyPhysics.State,
    translation: Vector,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> FullScreenToyPhysics.State {
    var translated = state
    translated.position.x += Int(
      (translation.dx * Double(FullScreenToyPhysics.fixedScale)).rounded()
    )
    translated.position.y += Int(
      (translation.dy * Double(FullScreenToyPhysics.fixedScale)).rounded()
    )
    return FullScreenToyPhysics.clamped(
      translated,
      in: bounds,
      metrics: metrics
    )
  }

  private static func ballBody(
    for state: FullScreenToyPhysics.State,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> LogoBreakerBall {
    let position = FullScreenToyPhysics.displayPosition(
      for: state,
      dragOffset: .zero,
      in: bounds,
      metrics: metrics
    )
    let geometry = ballGeometry(at: position, metrics: metrics)
    return LogoBreakerBall(
      center: geometry.center,
      radiusX: geometry.radiusX,
      radiusY: geometry.radiusY
    )
  }

  private static func firstCollision(
    from startBall: LogoBreakerBall,
    to endBall: LogoBreakerBall,
    brokenBrickIDs: Set<Int>,
    logoOrigin: CellPoint
  ) -> LogoBreakerCollision? {
    let dx = endBall.center.x - startBall.center.x
    let dy = endBall.center.y - startBall.center.y
    let hits = LogoArt.bricks.compactMap { brick -> LogoBreakerSweptHit? in
      guard !brokenBrickIDs.contains(brick.id) else {
        return nil
      }
      return sweptHit(
        from: startBall,
        dx: dx,
        dy: dy,
        x: logoOrigin.x + brick.x,
        y: logoOrigin.y + brick.y,
        width: brick.width,
        height: brick.height
      ).map {
        LogoBreakerSweptHit(brick: brick, time: $0.time, normal: $0.normal)
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
      normal: collisionNormal(for: firstHits, dx: dx, dy: dy, yScale: startBall.yScale),
      hits: firstHits
    )
  }

  private static func sweptHit(
    from ball: LogoBreakerBall,
    dx: Double,
    dy: Double,
    x: Int,
    y: Int,
    width: Int,
    height: Int
  ) -> (time: Double, normal: LogoBreakerVector)? {
    let brick = LogoBreakerRect(
      minX: Double(x),
      minY: Double(y),
      maxX: Double(x + width),
      maxY: Double(y + height)
    )
    return sweptCircleHit(from: ball, dx: dx, dy: dy, obstacle: brick)
  }

  private static func sweptCircleHit(
    from ball: LogoBreakerBall,
    dx: Double,
    dy: Double,
    obstacle: LogoBreakerRect
  ) -> (time: Double, normal: LogoBreakerVector)? {
    let yScale = ball.yScale
    let radius = ball.radiusX
    let start = LogoBreakerVector(
      x: ball.center.x,
      y: ball.center.y * yScale
    )
    let delta = LogoBreakerVector(x: dx, y: dy * yScale)
    let rect = obstacle.scaledY(by: yScale)
    var candidates: [(time: Double, normal: LogoBreakerVector)] = []

    if let normal = circleRectNormal(center: start, radius: radius, rect: rect),
      isMovingTowardObstacle(delta: delta, normal: normal)
    {
      candidates.append((time: 0, normal: normal))
    }

    if delta.x > collisionEpsilon {
      addFaceCandidate(
        time: (rect.minX - radius - start.x) / delta.x,
        normal: LogoBreakerVector(x: -1, y: 0),
        coordinate: start.y,
        delta: delta.y,
        range: rect.minY...rect.maxY,
        movement: delta,
        candidates: &candidates
      )
    } else if delta.x < -collisionEpsilon {
      addFaceCandidate(
        time: (rect.maxX + radius - start.x) / delta.x,
        normal: LogoBreakerVector(x: 1, y: 0),
        coordinate: start.y,
        delta: delta.y,
        range: rect.minY...rect.maxY,
        movement: delta,
        candidates: &candidates
      )
    }

    if delta.y > collisionEpsilon {
      addFaceCandidate(
        time: (rect.minY - radius - start.y) / delta.y,
        normal: LogoBreakerVector(x: 0, y: -1),
        coordinate: start.x,
        delta: delta.x,
        range: rect.minX...rect.maxX,
        movement: delta,
        candidates: &candidates
      )
    } else if delta.y < -collisionEpsilon {
      addFaceCandidate(
        time: (rect.maxY + radius - start.y) / delta.y,
        normal: LogoBreakerVector(x: 0, y: 1),
        coordinate: start.x,
        delta: delta.x,
        range: rect.minX...rect.maxX,
        movement: delta,
        candidates: &candidates
      )
    }

    for corner in [
      LogoBreakerCorner(point: LogoBreakerVector(x: rect.minX, y: rect.minY), xSign: -1, ySign: -1),
      LogoBreakerCorner(point: LogoBreakerVector(x: rect.maxX, y: rect.minY), xSign: 1, ySign: -1),
      LogoBreakerCorner(point: LogoBreakerVector(x: rect.minX, y: rect.maxY), xSign: -1, ySign: 1),
      LogoBreakerCorner(point: LogoBreakerVector(x: rect.maxX, y: rect.maxY), xSign: 1, ySign: 1),
    ] {
      addCornerCandidates(
        start: start,
        delta: delta,
        radius: radius,
        corner: corner,
        candidates: &candidates
      )
    }

    return candidates
      .filter { isValidCollisionTime($0.time) }
      .min { lhs, rhs in lhs.time < rhs.time }
  }

  private static func addFaceCandidate(
    time: Double,
    normal: LogoBreakerVector,
    coordinate: Double,
    delta: Double,
    range: ClosedRange<Double>,
    movement: LogoBreakerVector,
    candidates: inout [(time: Double, normal: LogoBreakerVector)]
  ) {
    guard isValidCollisionTime(time) else {
      return
    }
    let hitCoordinate = coordinate + delta * time
    guard hitCoordinate >= range.lowerBound - collisionEpsilon,
      hitCoordinate <= range.upperBound + collisionEpsilon,
      isMovingTowardObstacle(delta: movement, normal: normal)
    else {
      return
    }
    candidates.append((time: max(0, time), normal: normal))
  }

  private static func addCornerCandidates(
    start: LogoBreakerVector,
    delta: LogoBreakerVector,
    radius: Double,
    corner: LogoBreakerCorner,
    candidates: inout [(time: Double, normal: LogoBreakerVector)]
  ) {
    let offset = start - corner.point
    let a = delta.dot(delta)
    guard a > collisionEpsilon else {
      return
    }
    let b = 2 * offset.dot(delta)
    let c = offset.dot(offset) - radius * radius
    let discriminant = b * b - 4 * a * c
    guard discriminant >= -collisionEpsilon else {
      return
    }

    let root = max(0, discriminant).squareRoot()
    let roots = [
      (-b - root) / (2 * a),
      (-b + root) / (2 * a),
    ].sorted()
    for time in roots where isValidCollisionTime(time) {
      let center = start + delta * time
      guard corner.contains(center) else {
        continue
      }
      guard let normal = (center - corner.point).normalized,
        isMovingTowardObstacle(delta: delta, normal: normal)
      else {
        continue
      }
      candidates.append((time: max(0, time), normal: normal))
    }
  }

  private static func circleRectNormal(
    center: LogoBreakerVector,
    radius: Double,
    rect: LogoBreakerRect
  ) -> LogoBreakerVector? {
    let closest = LogoBreakerVector(
      x: min(max(center.x, rect.minX), rect.maxX),
      y: min(max(center.y, rect.minY), rect.maxY)
    )
    let offset = center - closest
    let distanceSquared = offset.dot(offset)
    guard distanceSquared <= radius * radius + collisionEpsilon else {
      return nil
    }
    if let normal = offset.normalized {
      return normal
    }

    let nearestFace = [
      (distance: abs(center.x - rect.minX), normal: LogoBreakerVector(x: -1, y: 0)),
      (distance: abs(rect.maxX - center.x), normal: LogoBreakerVector(x: 1, y: 0)),
      (distance: abs(center.y - rect.minY), normal: LogoBreakerVector(x: 0, y: -1)),
      (distance: abs(rect.maxY - center.y), normal: LogoBreakerVector(x: 0, y: 1)),
    ].min { lhs, rhs in lhs.distance < rhs.distance }
    return nearestFace?.normal
  }

  private static func reflectVelocity(
    _ velocity: inout FullScreenToyPhysics.FixedVelocity,
    normal: LogoBreakerVector,
    yScale: Double
  ) {
    guard let normal = normal.normalized else {
      return
    }
    let scaledVelocity = LogoBreakerVector(
      x: Double(velocity.x),
      y: Double(velocity.y) * yScale
    )
    let incoming = scaledVelocity.dot(normal)
    guard incoming < 0 else {
      return
    }

    let restitution = Double(FullScreenToyPhysics.wallBounceNumerator)
      / Double(FullScreenToyPhysics.wallBounceDenominator)
    let reflected = scaledVelocity - normal * ((1 + restitution) * incoming)
    velocity.x = Int(reflected.x.rounded())
    velocity.y = Int((reflected.y / yScale).rounded())
  }

  private static func collisionNormal(
    for hits: [LogoBreakerSweptHit],
    dx: Double,
    dy: Double,
    yScale: Double
  ) -> LogoBreakerVector {
    let combined = hits.reduce(LogoBreakerVector.zero) { partial, hit in
      partial + hit.normal
    }
    if let normal = combined.normalized {
      return normal
    }

    let movement = LogoBreakerVector(x: -dx, y: -dy * yScale)
    return movement.normalized ?? LogoBreakerVector(x: 0, y: -1)
  }

  private static func fixedPosition(
    for ball: LogoBreakerBall
  ) -> FullScreenToyPhysics.FixedPoint {
    FullScreenToyPhysics.FixedPoint(
      x: Int(
        ((ball.center.x - ball.radiusX) * Double(FullScreenToyPhysics.fixedScale))
          .rounded()
      ),
      y: Int(
        ((ball.center.y - ball.radiusY) * Double(FullScreenToyPhysics.fixedScale))
          .rounded()
      )
    )
  }

  private static func isMovingTowardObstacle(
    delta: LogoBreakerVector,
    normal: LogoBreakerVector
  ) -> Bool {
    delta.dot(normal) < -collisionEpsilon
  }

  private static func isValidCollisionTime(_ time: Double) -> Bool {
    time >= -collisionEpsilon && time <= 1 + collisionEpsilon
  }

  private static let collisionEpsilon = 0.000_001
}

private struct LogoBreakerBall: Equatable, Sendable {
  let center: Point
  let radiusX: Double
  let radiusY: Double

  var yScale: Double {
    guard radiusY > 0 else {
      return 1
    }
    return radiusX / radiusY
  }

  func moved(dx: Double, dy: Double) -> LogoBreakerBall {
    LogoBreakerBall(
      center: Point(x: center.x + dx, y: center.y + dy),
      radiusX: radiusX,
      radiusY: radiusY
    )
  }
}

private struct LogoBreakerVector: Equatable, Sendable {
  let x: Double
  let y: Double

  static let zero = LogoBreakerVector(x: 0, y: 0)

  var normalized: LogoBreakerVector? {
    let length = dot(self).squareRoot()
    guard length > 0.000_001 else {
      return nil
    }
    return LogoBreakerVector(x: x / length, y: y / length)
  }

  func dot(_ other: LogoBreakerVector) -> Double {
    x * other.x + y * other.y
  }

  static func + (lhs: LogoBreakerVector, rhs: LogoBreakerVector) -> LogoBreakerVector {
    LogoBreakerVector(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
  }

  static func - (lhs: LogoBreakerVector, rhs: LogoBreakerVector) -> LogoBreakerVector {
    LogoBreakerVector(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
  }

  static func * (lhs: LogoBreakerVector, rhs: Double) -> LogoBreakerVector {
    LogoBreakerVector(x: lhs.x * rhs, y: lhs.y * rhs)
  }
}

private struct LogoBreakerCorner: Equatable, Sendable {
  let point: LogoBreakerVector
  let xSign: Int
  let ySign: Int

  func contains(_ center: LogoBreakerVector) -> Bool {
    let xMatches = xSign < 0
      ? center.x <= point.x + 0.000_001
      : center.x >= point.x - 0.000_001
    let yMatches = ySign < 0
      ? center.y <= point.y + 0.000_001
      : center.y >= point.y - 0.000_001
    return xMatches && yMatches
  }
}

private struct LogoBreakerRect: Equatable, Sendable {
  let minX: Double
  let minY: Double
  let maxX: Double
  let maxY: Double

  func scaledY(by scale: Double) -> LogoBreakerRect {
    LogoBreakerRect(
      minX: minX,
      minY: minY * scale,
      maxX: maxX,
      maxY: maxY * scale
    )
  }
}

enum LogoBreakerDragOutcome: Equatable, Sendable {
  case tracking
  case dropped
}

private struct LogoBreakerSweptHit: Equatable, Sendable {
  let brick: LogoBrick
  let time: Double
  let normal: LogoBreakerVector
}

private struct LogoBreakerCollision: Equatable, Sendable {
  let time: Double
  let normal: LogoBreakerVector
  let hits: [LogoBreakerSweptHit]
}

private struct LogoBreakerDrawing: CanvasDrawing, Equatable {
  let logoOrigin: CellPoint
  let brokenBrickIDs: Set<Int>
  let ballCenter: Point
  let ballRadiusX: Double
  let ballRadiusY: Double

  func draw(into context: inout CanvasContext) {
    for brick in LogoArt.bricks where !brokenBrickIDs.contains(brick.id) {
      for cell in brick.cells {
        draw(cell, into: &context)
      }
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
