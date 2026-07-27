import Foundation

/// A pixel coordinate inside the canvas, with `(0, 0)` at the top-left.
public struct PixelPoint: Hashable, Sendable, Codable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  public static let zero = PixelPoint(x: 0, y: 0)
}

/// Width × height of a pixel canvas. Always positive.
public struct PixelSize: Hashable, Sendable, Codable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    precondition(width > 0 && height > 0, "PixelSize must be positive")
    self.width = width
    self.height = height
  }

  public var area: Int { width * height }

  /// The same extent with its axes swapped — the shape a quarter turn of
  /// this one produces.
  ///
  /// Spelled once here because `PixelSize(width: height, height: width)`
  /// is a literal whose two arguments are exactly the transposition the
  /// compiler cannot check, and because the rotate path needs it in three
  /// places that must agree.
  public var transposed: PixelSize {
    PixelSize(width: height, height: width)
  }

  /// This extent as a rect anchored at the origin — the "whole canvas"
  /// every clipping operation intersects against.
  ///
  /// It was open-coded as `PixelRect(x: 0, y: 0, width: …, height: …)`
  /// at half a dozen call sites, which is five chances to transpose the
  /// two dimensions in a literal the compiler cannot check.
  public var bounds: PixelRect {
    PixelRect(x: 0, y: 0, width: width, height: height)
  }

  public func contains(_ point: PixelPoint) -> Bool {
    point.x >= 0 && point.y >= 0 && point.x < width && point.y < height
  }

  public func indexOf(_ point: PixelPoint) -> Int {
    point.y * width + point.x
  }

  public func point(at index: Int) -> PixelPoint {
    PixelPoint(x: index % width, y: index / width)
  }
}

extension PixelSize {
  /// Hardened decoding. `width` and `height` are the two numbers every
  /// other bound in the model is derived from — ``indexOf(_:)`` and
  /// ``point(at:)`` divide by `width`, and ``area`` is what every buffer
  /// allocation is sized to — so this is where an untrusted file gets
  /// checked, not where it gets trusted.
  ///
  /// The order matters: the per-axis limit is applied *before* the area
  /// is multiplied out, so a header claiming 100000 x 100000 is refused
  /// without ever computing (let alone allocating) 10^10 elements.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let width = try container.decode(Int.self, forKey: .width)
    let height = try container.decode(Int.self, forKey: .height)

    guard width > 0, height > 0 else {
      throw ProjectDecodeError.invalidCanvasSize(width: width, height: height)
    }
    guard
      width <= ProjectFile.maximumCanvasDimension,
      height <= ProjectFile.maximumCanvasDimension,
      width * height <= ProjectFile.maximumCanvasArea
    else {
      throw ProjectDecodeError.canvasTooLarge(
        width: width,
        height: height,
        dimensionLimit: ProjectFile.maximumCanvasDimension,
        areaLimit: ProjectFile.maximumCanvasArea
      )
    }

    self.init(width: width, height: height)
  }

  /// Spelled out so the synthesized `encode(to:)` and the hardened
  /// `init(from:)` above are provably reading the same two keys.
  private enum CodingKeys: String, CodingKey {
    case width
    case height
  }
}

/// Inclusive-exclusive rectangular region in pixel space.
public struct PixelRect: Hashable, Sendable, Codable {
  public var origin: PixelPoint
  public var size: PixelSize

  public init(origin: PixelPoint, size: PixelSize) {
    self.origin = origin
    self.size = size
  }

  public init(x: Int, y: Int, width: Int, height: Int) {
    self.init(origin: PixelPoint(x: x, y: y), size: PixelSize(width: width, height: height))
  }

  public var minX: Int { origin.x }
  public var minY: Int { origin.y }
  public var maxX: Int { origin.x + size.width }
  public var maxY: Int { origin.y + size.height }

  /// Membership in loose coordinates.
  ///
  /// The scan loops walk `x` and `y` as plain `Int`s, so the point-taking
  /// overload made them build a ``PixelPoint`` per cell purely to ask a
  /// question about two numbers — and, on the clipped cells, throw it
  /// away again.
  public func contains(x: Int, y: Int) -> Bool {
    x >= minX && x < maxX && y >= minY && y < maxY
  }

  public func contains(_ point: PixelPoint) -> Bool {
    contains(x: point.x, y: point.y)
  }

  /// Intersection of two rects, normalized into the smaller bounds.
  /// Returns `nil` when they don't overlap.
  public func intersected(with other: PixelRect) -> PixelRect? {
    let left = max(minX, other.minX)
    let top = max(minY, other.minY)
    let right = min(maxX, other.maxX)
    let bottom = min(maxY, other.maxY)
    guard right > left && bottom > top else { return nil }
    return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  /// The smallest rect that fully contains both points (inclusive).
  public static func bounding(_ a: PixelPoint, _ b: PixelPoint) -> PixelRect {
    let x0 = min(a.x, b.x)
    let y0 = min(a.y, b.y)
    let x1 = max(a.x, b.x)
    let y1 = max(a.y, b.y)
    return PixelRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
  }
}
