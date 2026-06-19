import SwiftTUIRuntime

// A small, self-contained 2D arcade-physics core: a circular body that falls
// under gravity, bounces off the walls of a rectangular field, slides to rest
// on the floor, and reports continuous (swept) collisions against axis-aligned
// obstacles. It is deliberately game-agnostic — a brick-breaker, a bouncing
// pet, a falling-ball toy, or a simple pinball can all be built on top by
// composing `PhysicsIntegrator` (the field simulation) with `SweptCircle` (the
// obstacle-collision primitive). Copy this file as the seed of a new game.
//
// Design choices worth keeping if you adapt it:
//
//  * Everything simulates in an **isotropic world space** where one unit is one
//    terminal cell *width* on both axes. Terminal cells are roughly twice as
//    tall as they are wide, so motion would look squashed if we simulated in
//    raw cell coordinates. Instead, `WorldSpace` applies that aspect correction
//    exactly once at the boundary, and the integrator and collision math never
//    have to think about it — a circle is a true circle in here.
//
//  * The integrator is **fixed-timestep semi-implicit (symplectic) Euler**:
//    velocity is advanced before position. That ordering is energy-stable for a
//    bouncing ball; plain ("explicit") Euler pumps energy in every tick and a
//    ball would bounce *higher* over time and never settle.
//
//  * **Rest is a fixed point reached by assignment, not arithmetic.** When a
//    floor-supported body is slow enough, its velocity is set to exactly zero
//    and its position snapped to the exact floor constant. The next `step` then
//    returns a byte-identical body, which lets a frame-eliding host stop
//    redrawing a ball that has come to rest (CPU drops to zero). Letting gravity
//    and a bounce "cancel out" instead would leave a sub-ulp residue and spin
//    the render loop forever.
//
//    Settling is scoped to the **field floor only** — that is the one surface
//    `PhysicsIntegrator` knows how to rest a body against. A body left resting
//    on a `SweptCircle` *obstacle* does NOT auto-settle: gravity keeps pulling
//    it into the obstacle and the bounce keeps pushing it back, so it
//    micro-bounces forever and the host never stops redrawing. If your game has
//    obstacles a body can come to rest on (shelves, a pong paddle, an unbroken
//    brick), either consume the obstacle on contact (as the LogoBreaker game
//    deletes a brick the instant it is hit) or settle the body yourself: when a
//    *supporting* contact (its normal opposes gravity) is slower than
//    `restSpeed`, zero the normal-axis velocity and snap the center to exactly
//    `radius` from the obstacle face — the same rest-by-assignment the floor
//    uses.

/// Tunable physical parameters, in isotropic world units (one unit = one cell
/// width) and seconds. All values are plain ratios or accelerations with
/// physical meaning, so they can be tuned by feel without touching the math.
struct PhysicsConfig: Sendable, Equatable {
  /// Downward acceleration, world units per second squared. Because it is an
  /// acceleration (not a per-tick impulse) the trajectory is identical at any
  /// tick rate.
  var gravity = 80.0

  /// Fraction of normal-axis speed kept after bouncing off a side wall or the
  /// ceiling. `0` is dead, `1` is perfectly elastic. Must stay below `1`.
  var wallRestitution = 0.78

  /// Fraction of normal-axis speed kept after bouncing off the floor. Kept a
  /// little lower than the walls so vertical bounces decay and the body settles
  /// in finite time. Must stay below `1`.
  var floorRestitution = 0.62

  /// Coulomb-style floor friction coefficient. While the body rests on the
  /// floor its horizontal speed loses `friction * gravity * dt` each tick — a
  /// constant deceleration that brings it to an exact stop in finite ticks
  /// (unlike multiplicative damping, which only ever approaches zero).
  var friction = 0.18

  /// Speed (world units per second) below which a floor-supported body is
  /// snapped to rest. Must exceed `settleImpulse` (one tick of gravity) or the
  /// body can never settle — every tick would re-add more speed than the
  /// threshold removes, and the host's frame-elision never fires. See
  /// ``isSettleable``; `PhysicsIntegrator.step` asserts it in debug builds.
  var restSpeed = 6.0

  /// Tolerance for "the body is touching the floor", in world units. This is the
  /// field-contact tolerance only; obstacle CCD uses `SweptCircle.timeEpsilon`
  /// (dimensionless) and `SweptCircle.geomEpsilon` (world units), which live on
  /// different scales — tuning this does not affect obstacle hits.
  var contactEpsilon = 1e-6

  /// Fixed simulation timestep, seconds. One `step` advances the world by `dt`.
  /// Keep this independent of how often the game loop actually ticks.
  var dt = 0.040

  /// The downward speed gravity adds in a single tick. A floor-supported body
  /// cannot settle unless `restSpeed` exceeds this.
  var settleImpulse: Double { gravity * dt }

  /// Whether a body can ever come to rest with these parameters. If `false`, a
  /// resting body micro-bounces forever and a frame-eliding host never idles.
  var isSettleable: Bool { restSpeed > settleImpulse }

  /// Sensible defaults for a snappy arcade feel.
  static let arcade = PhysicsConfig()
}

/// A circular rigid body. `position` is the **center** in isotropic world
/// space; `radius` is also in world units (cell widths).
struct PhysicsBody: Sendable, Equatable {
  var position: Point
  var velocity: Vector
  var radius: Double

  init(position: Point, velocity: Vector = .zero, radius: Double) {
    self.position = position
    self.velocity = velocity
    self.radius = radius
  }
}

/// An axis-aligned bounding box in world space: the field, an obstacle, a brick.
struct AABB: Sendable, Equatable {
  var minX: Double
  var minY: Double
  var maxX: Double
  var maxY: Double
}

/// A rectangular play area. `bounds` is the raw field extent; the integrator
/// insets it by the body radius so the body *center* stays inside.
struct Playfield: Sendable, Equatable {
  var bounds: AABB

  /// The region the body center may occupy, i.e. `bounds` shrunk by `radius` on
  /// every side. Collapses to the field center if the body is wider than the
  /// field (a degenerate but harmless case).
  func centerBounds(radius: Double) -> AABB {
    AABB(
      minX: bounds.minX + radius,
      minY: bounds.minY + radius,
      maxX: max(bounds.minX + radius, bounds.maxX - radius),
      maxY: max(bounds.minY + radius, bounds.maxY - radius)
    )
  }
}

/// Converts between terminal **cell space** (what views, the `Canvas`, and
/// gestures use) and isotropic **world space** (what the simulation uses).
///
/// One world unit is one cell *width*. A cell is `aspect` (~2.0) times taller
/// than it is wide, so a vertical cell coordinate becomes `aspect` world units;
/// the inverse divides. This is the *only* place the aspect ratio is read —
/// keep it that way and the rest of the engine stays cleanly isotropic.
struct WorldSpace: Sendable, Equatable {
  let aspect: Double

  init(aspect: Double) {
    assert(aspect > 0, "aspect ratio must be positive")
    self.aspect = max(0.0001, aspect)
  }

  init(metrics: CellPixelMetrics) {
    self.init(aspect: metrics.aspectRatio)
  }

  func toWorld(_ point: Point) -> Point { Point(x: point.x, y: point.y * aspect) }
  func toCell(_ point: Point) -> Point { Point(x: point.x, y: point.y / aspect) }

  /// Velocities and displacements convert with the *same* forward multiply as
  /// positions — a cell-space downward speed is `aspect` times faster in world
  /// space, not slower.
  func toWorld(_ vector: Vector) -> Vector { Vector(dx: vector.dx, dy: vector.dy * aspect) }
  func toCell(_ vector: Vector) -> Vector { Vector(dx: vector.dx, dy: vector.dy / aspect) }

  /// Maps a cell-space rectangle (origin + size) into a world-space `AABB`.
  func toWorld(cellX x: Double, cellY y: Double, width: Double, height: Double) -> AABB {
    AABB(minX: x, minY: y * aspect, maxX: x + width, maxY: (y + height) * aspect)
  }
}

/// The field simulation: advances a `PhysicsBody` one fixed timestep under
/// gravity, resolves the field walls/floor/ceiling, applies floor friction, and
/// settles the body to an exact rest state. Obstacle collisions are *not*
/// handled here — compose them with `SweptCircle` so each game can choose its
/// own reaction (break a brick, award a point, ricochet).
enum PhysicsIntegrator {
  /// Advances `body` by one tick. Returns `true` if the body changed, so a host
  /// can elide a frame when a resting body produces no motion.
  @discardableResult
  static func step(
    _ body: inout PhysicsBody,
    in field: Playfield,
    config: PhysicsConfig
  ) -> Bool {
    assert(
      config.isSettleable,
      "restSpeed (\(config.restSpeed)) must exceed one tick of gravity "
        + "(gravity*dt = \(config.settleImpulse)) or a body can never settle"
    )
    let previous = body
    let limits = field.centerBounds(radius: body.radius)
    let floorY = limits.maxY

    // Rest is reached by direct assignment so the body becomes a byte-identical
    // fixed point (see the file header). Doing this before any arithmetic is
    // what prevents sub-ulp drift from spinning a frame-eliding loop forever.
    if isResting(body, in: field, config: config) {
      body.velocity = .zero
      body.position.y = floorY
      return body != previous
    }

    // "On the floor" means touching it and not moving away from it: a body
    // launched or bouncing *upward* off the floor is airborne and keeps gravity.
    let onFloor = body.position.y >= floorY - config.contactEpsilon && body.velocity.dy >= 0

    // Semi-implicit Euler: velocity first, then position. Gravity is gated off
    // while the body is supported so a settled body never accumulates speed.
    if onFloor {
      applyFloorFriction(&body, config: config)
    } else {
      body.velocity.dy += config.gravity * config.dt
    }
    body.position.x += body.velocity.dx * config.dt
    body.position.y += body.velocity.dy * config.dt

    resolveBounds(&body, limits: limits, config: config)

    // A soft landing settles immediately rather than micro-bouncing.
    if isResting(body, in: field, config: config) {
      body.velocity = .zero
      body.position.y = floorY
    }
    return body != previous
  }

  /// Whether `body` is supported by the floor and slow enough to sleep.
  static func isResting(
    _ body: PhysicsBody,
    in field: Playfield,
    config: PhysicsConfig
  ) -> Bool {
    let limits = field.centerBounds(radius: body.radius)
    return body.position.y >= limits.maxY - config.contactEpsilon
      && abs(body.velocity.dy) <= config.restSpeed
      && abs(body.velocity.dx) <= config.restSpeed
  }

  /// Constant-deceleration (Coulomb) floor friction on the horizontal axis. The
  /// `abs(next) < restSpeed` cutoff guarantees the body reaches exactly zero in
  /// finite ticks, which the rest snap relies on.
  private static func applyFloorFriction(_ body: inout PhysicsBody, config: PhysicsConfig) {
    let vx = body.velocity.dx
    guard vx != 0 else { return }
    let decel = config.friction * config.gravity * config.dt
    let next = (abs(vx) - decel) * (vx < 0 ? -1 : 1)
    body.velocity.dx = (abs(vx) <= decel || abs(next) < config.restSpeed) ? 0 : next
  }

  /// Clamps the body center inside the field and reflects velocity off whichever
  /// walls it crossed, with restitution. A tiny rebound is absorbed to zero so
  /// the body can settle.
  private static func resolveBounds(_ body: inout PhysicsBody, limits: AABB, config: PhysicsConfig)
  {
    if body.position.x < limits.minX {
      body.position.x = limits.minX
      body.velocity.dx = rebound(body.velocity.dx, config.wallRestitution, config.restSpeed)
    } else if body.position.x > limits.maxX {
      body.position.x = limits.maxX
      body.velocity.dx = rebound(body.velocity.dx, config.wallRestitution, config.restSpeed)
    }
    if body.position.y < limits.minY {
      body.position.y = limits.minY
      body.velocity.dy = rebound(body.velocity.dy, config.wallRestitution, config.restSpeed)
    } else if body.position.y > limits.maxY {
      body.position.y = limits.maxY
      body.velocity.dy = rebound(body.velocity.dy, config.floorRestitution, config.restSpeed)
    }
  }

  /// Reverses and scales one velocity component by restitution, absorbing a
  /// sub-threshold rebound to exactly zero. There is deliberately no minimum
  /// magnitude: a floor for the rebound speed would stop the body ever resting.
  private static func rebound(_ component: Double, _ restitution: Double, _ restSpeed: Double)
    -> Double
  {
    let reflected = -component * restitution
    return abs(reflected) < restSpeed ? 0 : reflected
  }
}

/// A continuous collision of a moving circle against a static obstacle.
struct Contact: Sendable, Equatable {
  /// Fraction of the sweep, in `0...1`, at which contact first occurs.
  var time: Double
  /// Unit surface normal at the contact, pointing out of the obstacle toward
  /// the circle.
  var normal: Vector

  /// The circle center at the moment of contact, given the sweep it came from.
  func center(from start: Point, delta: Vector) -> Point {
    start + delta * time
  }
}

/// The earliest contact of a swept circle against a *set* of obstacles, plus the
/// indices of every obstacle hit at that same instant. Ties are clustered and
/// their normals combined so a flush multi-obstacle hit (e.g. a ball striking
/// two adjacent bricks at once) reflects cleanly instead of along one face.
struct ObstacleContact: Sendable, Equatable {
  var contact: Contact
  var indices: [Int]
}

/// Continuous (swept) collision between a moving circle and an axis-aligned box,
/// plus a restitution-aware velocity reflection. Inputs are isotropic world
/// units — there is no per-axis scaling here, which is what makes the math
/// readable.
///
/// The method is a Minkowski sweep: a circle of radius `r` against a box is the
/// same as a *point* (the circle center) against that box expanded by `r` — a
/// rectangle with rounded corners. The straight edges are handled as expanded
/// faces; the rounded corners as ray-versus-circle quadratics.
enum SweptCircle {
  /// Collision times are dimensionless fractions; geometry is in world units.
  /// They get separate tolerances because they live on different scales.
  static let timeEpsilon = 1e-9
  static let geomEpsilon = 1e-9

  /// Contacts whose times are within this fraction of the earliest are treated
  /// as simultaneous (their normals combine).
  static let simultaneousEpsilon = 1e-6

  /// First contact of a circle of `radius` centered at `center`, swept by
  /// `delta`, against `box`. Returns `nil` if the swept circle never touches the
  /// box. An already-overlapping circle reports a `time == 0` contact with a
  /// separation normal *unconditionally* — the caller decides whether to react,
  /// by checking whether the velocity is approaching (see `reflect`).
  static func firstContact(
    center: Point,
    radius: Double,
    delta: Vector,
    against box: AABB
  ) -> Contact? {
    var best: Contact?
    func consider(_ time: Double, _ normal: Vector) {
      guard time >= -timeEpsilon, time <= 1 + timeEpsilon else { return }
      let clamped = max(0, time)
      if best == nil || clamped < best!.time {
        best = Contact(time: clamped, normal: normal)
      }
    }

    if let normal = overlapNormal(center: center, radius: radius, box: box) {
      consider(0, normal)
    }
    addFaceContacts(center: center, radius: radius, delta: delta, box: box, consider: consider)
    addCornerContacts(center: center, radius: radius, delta: delta, box: box, consider: consider)
    return best
  }

  /// First contact of the swept circle against any of `boxes`, with every box
  /// hit at that same earliest instant reported in `indices` and their normals
  /// combined. Returns `nil` if the sweep clears them all. This is the piece
  /// most games re-implement; getting the simultaneous-hit normal right (so the
  /// body does not reflect off one of two flush obstacles into the other) is the
  /// subtle part, so it lives in the core.
  static func firstContact(
    center: Point,
    radius: Double,
    delta: Vector,
    against boxes: [AABB]
  ) -> ObstacleContact? {
    var hits: [(index: Int, contact: Contact)] = []
    for (index, box) in boxes.enumerated() {
      if let contact = firstContact(center: center, radius: radius, delta: delta, against: box) {
        hits.append((index, contact))
      }
    }
    guard let earliest = hits.map(\.contact.time).min() else { return nil }
    let simultaneous = hits.filter { $0.contact.time - earliest <= simultaneousEpsilon }
    let combined = simultaneous.reduce(Vector.zero) { $0 + $1.contact.normal }
    let fallback = (delta * -1).normalized ?? Vector(dx: 0, dy: -1)
    return ObstacleContact(
      contact: Contact(time: earliest, normal: combined.normalized ?? fallback),
      indices: simultaneous.map(\.index)
    )
  }

  /// Reflects `velocity` about a contact `normal`, keeping `restitution` of the
  /// approaching speed and preserving the tangential component. A velocity that
  /// is already separating from the surface is returned unchanged.
  static func reflect(_ velocity: Vector, normal: Vector, restitution: Double) -> Vector {
    guard let unit = normal.normalized else { return velocity }
    let approaching = velocity.dot(unit)
    guard approaching < 0 else { return velocity }
    return velocity - unit * ((1 + restitution) * approaching)
  }

  /// Separation normal if the circle currently overlaps the box, else `nil`.
  static func overlapNormal(center: Point, radius: Double, box: AABB) -> Vector? {
    let closest = Point(
      x: min(max(center.x, box.minX), box.maxX),
      y: min(max(center.y, box.minY), box.maxY)
    )
    let offset = Vector(dx: center.x - closest.x, dy: center.y - closest.y)
    guard offset.lengthSquared <= radius * radius + geomEpsilon else { return nil }
    // Outside-but-touching: push out along the offset. Center inside the box:
    // push out through the nearest face.
    return offset.normalized ?? deepestFaceNormal(center: center, box: box)
  }

  private static func deepestFaceNormal(center: Point, box: AABB) -> Vector {
    let faces: [(depth: Double, normal: Vector)] = [
      (abs(center.x - box.minX), Vector(dx: -1, dy: 0)),
      (abs(box.maxX - center.x), Vector(dx: 1, dy: 0)),
      (abs(center.y - box.minY), Vector(dx: 0, dy: -1)),
      (abs(box.maxY - center.y), Vector(dx: 0, dy: 1)),
    ]
    return faces.min { $0.depth < $1.depth }?.normal ?? Vector(dx: 0, dy: -1)
  }

  /// Contacts against the four expanded faces (the straight edges of the
  /// rounded rectangle). Only the face the body is moving toward can be hit.
  private static func addFaceContacts(
    center: Point,
    radius: Double,
    delta: Vector,
    box: AABB,
    consider: (Double, Vector) -> Void
  ) {
    if delta.dx > geomEpsilon {
      addFace(
        time: (box.minX - radius - center.x) / delta.dx, normal: Vector(dx: -1, dy: 0),
        crossStart: center.y, crossDelta: delta.dy, low: box.minY, high: box.maxY,
        delta: delta, consider: consider)
    } else if delta.dx < -geomEpsilon {
      addFace(
        time: (box.maxX + radius - center.x) / delta.dx, normal: Vector(dx: 1, dy: 0),
        crossStart: center.y, crossDelta: delta.dy, low: box.minY, high: box.maxY,
        delta: delta, consider: consider)
    }
    if delta.dy > geomEpsilon {
      addFace(
        time: (box.minY - radius - center.y) / delta.dy, normal: Vector(dx: 0, dy: -1),
        crossStart: center.x, crossDelta: delta.dx, low: box.minX, high: box.maxX,
        delta: delta, consider: consider)
    } else if delta.dy < -geomEpsilon {
      addFace(
        time: (box.maxY + radius - center.y) / delta.dy, normal: Vector(dx: 0, dy: 1),
        crossStart: center.x, crossDelta: delta.dx, low: box.minX, high: box.maxX,
        delta: delta, consider: consider)
    }
  }

  private static func addFace(
    time: Double,
    normal: Vector,
    crossStart: Double,
    crossDelta: Double,
    low: Double,
    high: Double,
    delta: Vector,
    consider: (Double, Vector) -> Void
  ) {
    guard time >= -timeEpsilon, time <= 1 + timeEpsilon else { return }
    let crossing = crossStart + crossDelta * time
    guard crossing >= low - geomEpsilon, crossing <= high + geomEpsilon else { return }
    guard delta.dot(normal) < -geomEpsilon else { return }
    consider(time, normal)
  }

  /// Contacts against the four rounded corners (quarter-circle caps): solve when
  /// the moving center is exactly `radius` from a box corner, then keep only the
  /// roots that land in that corner's exterior Voronoi region.
  private static func addCornerContacts(
    center: Point,
    radius: Double,
    delta: Vector,
    box: AABB,
    consider: (Double, Vector) -> Void
  ) {
    let a = delta.lengthSquared
    guard a > geomEpsilon else { return }
    let corners = [
      Point(x: box.minX, y: box.minY),
      Point(x: box.maxX, y: box.minY),
      Point(x: box.minX, y: box.maxY),
      Point(x: box.maxX, y: box.maxY),
    ]
    for corner in corners {
      let offset = center - corner
      let b = 2 * offset.dot(delta)
      let c = offset.lengthSquared - radius * radius
      let discriminant = b * b - 4 * a * c
      guard discriminant >= -geomEpsilon else { continue }
      let root = max(0, discriminant).squareRoot()
      for time in [(-b - root) / (2 * a), (-b + root) / (2 * a)] {
        guard time >= -timeEpsilon, time <= 1 + timeEpsilon else { continue }
        let hit = center + delta * time
        guard isInCornerRegion(hit, corner: corner, box: box) else { continue }
        guard let normal = (hit - corner).normalized else {
          continue
        }
        guard delta.dot(normal) < -geomEpsilon else { continue }
        consider(time, normal)
      }
    }
  }

  /// Whether `hit` is beyond both faces meeting at `corner` — the region where a
  /// rounded corner, not a flat face, is the true closest feature.
  private static func isInCornerRegion(_ hit: Point, corner: Point, box: AABB) -> Bool {
    let outsideX =
      corner.x <= box.minX
      ? hit.x <= corner.x + geomEpsilon
      : hit.x >= corner.x - geomEpsilon
    let outsideY =
      corner.y <= box.minY
      ? hit.y <= corner.y + geomEpsilon
      : hit.y >= corner.y - geomEpsilon
    return outsideX && outsideY
  }
}

/// Vector math used by the physics core. Kept as a local extension so this file
/// stays copy-pasteable without modifying `SwiftTUICore`'s `Vector`.
extension Vector {
  static func + (lhs: Vector, rhs: Vector) -> Vector {
    Vector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
  }

  static func - (lhs: Vector, rhs: Vector) -> Vector {
    Vector(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy)
  }

  static func * (lhs: Vector, scale: Double) -> Vector {
    Vector(dx: lhs.dx * scale, dy: lhs.dy * scale)
  }

  func dot(_ other: Vector) -> Double { dx * other.dx + dy * other.dy }

  var lengthSquared: Double { dx * dx + dy * dy }

  /// The unit vector in this direction, or `nil` for a (near-)zero vector — so
  /// no `NaN` from dividing by zero can ever reach the body state.
  var normalized: Vector? {
    let length = lengthSquared.squareRoot()
    guard length > 1e-12 else { return nil }
    return Vector(dx: dx / length, dy: dy / length)
  }
}

/// Point/displacement arithmetic: advancing a position by a vector, and the
/// displacement between two positions. `Point` is an absolute location;
/// `Vector` is a displacement — keeping them distinct keeps the motion math
/// honest (you cannot add two positions).
extension Point {
  static func + (point: Point, displacement: Vector) -> Point {
    Point(x: point.x + displacement.dx, y: point.y + displacement.dy)
  }

  static func - (lhs: Point, rhs: Point) -> Vector {
    Vector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
  }
}
