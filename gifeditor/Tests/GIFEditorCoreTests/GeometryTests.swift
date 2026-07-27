import Testing

@testable import GIFEditorCore

/// The two members that replaced the open-coded canvas rect and the
/// per-cell `PixelPoint` construction in the tool scan loops.
///
/// Both were written out by hand at every call site — `PixelRect(x: 0,
/// y: 0, width: buffer.size.width, height: buffer.size.height)` in five
/// places, and a point built purely to ask whether two integers were in
/// range. Neither is a behaviour change, so what these pin is the
/// *equivalence*: the shared member has to mean exactly what the copies
/// meant, on every shape including the degenerate ones.
@Suite("Geometry — bounds and loose-coordinate containment")
struct GeometryTests {

  @Test(
    "bounds is the rect the call sites used to write out",
    arguments: [(1, 1), (4, 3), (3, 4), (16, 16), (256, 1)]
  )
  func boundsMatchesTheOpenCodedRect(width: Int, height: Int) {
    let size = PixelSize(width: width, height: height)
    let openCoded = PixelRect(x: 0, y: 0, width: size.width, height: size.height)
    #expect(size.bounds == openCoded)
    #expect(PixelBuffer(size: size).bounds == openCoded)
    // A transposed literal is the mistake the member exists to prevent,
    // so a non-square case must be able to see it.
    #expect(size.bounds.size.width == width)
    #expect(size.bounds.size.height == height)
  }

  /// Swept rather than sampled: the loose-coordinate overload is the one
  /// the hot loops now call, and an off-by-one on any edge would be a
  /// painted or missing pixel at the boundary of every clipped tool.
  @Test("contains(x:y:) agrees with contains(_:) over a swept neighbourhood")
  func looseCoordinateContainmentAgrees() {
    let rects = [
      PixelRect(x: 0, y: 0, width: 1, height: 1),
      PixelRect(x: 2, y: 1, width: 3, height: 2),
      PixelRect(x: -1, y: -2, width: 4, height: 5),
    ]
    for rect in rects {
      for y in (rect.minY - 2)...(rect.maxY + 2) {
        for x in (rect.minX - 2)...(rect.maxX + 2) {
          #expect(
            rect.contains(x: x, y: y) == rect.contains(PixelPoint(x: x, y: y)),
            "(\(x), \(y)) in \(rect)"
          )
        }
      }
    }
  }

  @Test("a buffer's bounds contains exactly its own pixels")
  func bufferBoundsMatchesItsAddressableCells() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 3))
    for y in -1...3 {
      for x in -1...5 {
        #expect(
          buffer.bounds.contains(x: x, y: y) == buffer.size.contains(PixelPoint(x: x, y: y)),
          "(\(x), \(y))"
        )
      }
    }
  }
}
