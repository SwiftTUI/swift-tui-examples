import Foundation

/// Conway's Game of Life grid with toroidal (wraparound) boundary.
///
/// Backed by a single fixed-capacity `[Bool]` buffer so resizing the
/// visible window does not allocate. Steps are double-buffered into a
/// scratch buffer to avoid the classic in-place-update bug where a
/// neighbor lookup reads a value the current pass already mutated.
@MainActor
struct LifeGrid {
  /// Maximum dimensions. Sized so that even a generous terminal at
  /// braille zoom (`width * 2 × height * 4`) fits without bouncing the
  /// allocator on every resize.
  static let maxWidth = 320
  static let maxHeight = 160
  static let capacity = maxWidth * maxHeight

  private(set) var width: Int
  private(set) var height: Int
  private var cells: [Bool]
  private var scratch: [Bool]

  /// Number of `step()` invocations since the last `clear()` or seed.
  private(set) var generation: Int = 0
  private(set) var population: Int = 0

  init(width: Int = 96, height: Int = 32) {
    self.width = min(max(width, 1), Self.maxWidth)
    self.height = min(max(height, 1), Self.maxHeight)
    self.cells = Array(repeating: false, count: Self.capacity)
    self.scratch = Array(repeating: false, count: Self.capacity)
  }

  /// Resizes the *visible* grid. Existing cells in the surviving region
  /// are preserved; cells outside the new region are cleared. The
  /// underlying buffer is fixed-size so no allocation happens.
  mutating func resize(width newWidth: Int, height newHeight: Int) {
    let newWidth = min(max(newWidth, 1), Self.maxWidth)
    let newHeight = min(max(newHeight, 1), Self.maxHeight)
    guard newWidth != width || newHeight != height else { return }

    // Clear cells that fall outside the new visible region so a
    // subsequent enlarge does not resurrect stale state from a
    // previous size.
    for y in 0..<Self.maxHeight {
      for x in 0..<Self.maxWidth {
        let index = y * Self.maxWidth + x
        if x >= newWidth || y >= newHeight, cells[index] {
          cells[index] = false
          population -= 1
        }
      }
    }

    width = newWidth
    height = newHeight
  }

  func at(_ x: Int, _ y: Int) -> Bool {
    guard x >= 0, x < width, y >= 0, y < height else { return false }
    return cells[y * Self.maxWidth + x]
  }

  mutating func set(_ x: Int, _ y: Int, _ value: Bool) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let index = y * Self.maxWidth + x
    guard cells[index] != value else { return }
    cells[index] = value
    population += value ? 1 : -1
  }

  mutating func toggle(_ x: Int, _ y: Int) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let index = y * Self.maxWidth + x
    cells[index].toggle()
    population += cells[index] ? 1 : -1
  }

  mutating func clear() {
    for i in 0..<Self.capacity { cells[i] = false }
    population = 0
    generation = 0
  }

  /// Random fill at `density` (0…1). Resets generation counter.
  mutating func randomize(density: Double = 0.28, seed: UInt64? = nil) {
    var rng: any RandomNumberGenerator =
      seed.map { SeededRNG(seed: $0) } ?? SystemRandomNumberGenerator()
    for i in 0..<Self.capacity { cells[i] = false }
    population = 0
    for y in 0..<height {
      for x in 0..<width {
        if Double.random(in: 0..<1, using: &rng) < density {
          set(x, y, true)
        }
      }
    }
    generation = 0
  }

  /// Advance one generation using B3/S23 rules with toroidal wrap.
  mutating func step() {
    if population * 18 < width * height {
      stepSparse()
      return
    }

    let w = width
    let h = height
    let stride = Self.maxWidth
    var nextPopulation = 0

    for y in 0..<h {
      let yUp = (y - 1 + h) % h
      let yDn = (y + 1) % h
      let rowMid = y * stride
      let rowUp = yUp * stride
      let rowDn = yDn * stride

      for x in 0..<w {
        let xLt = (x - 1 + w) % w
        let xRt = (x + 1) % w

        var n = 0
        if cells[rowUp + xLt] { n += 1 }
        if cells[rowUp + x] { n += 1 }
        if cells[rowUp + xRt] { n += 1 }
        if cells[rowMid + xLt] { n += 1 }
        if cells[rowMid + xRt] { n += 1 }
        if cells[rowDn + xLt] { n += 1 }
        if cells[rowDn + x] { n += 1 }
        if cells[rowDn + xRt] { n += 1 }

        let alive = cells[rowMid + x]
        let nextAlive = (alive && (n == 2 || n == 3)) || (!alive && n == 3)
        scratch[rowMid + x] = nextAlive
        if nextAlive {
          nextPopulation += 1
        }
      }
    }

    swap(&cells, &scratch)
    population = nextPopulation
    generation += 1
  }

  private mutating func stepSparse() {
    guard population > 0 else {
      generation += 1
      return
    }

    let stride = Self.maxWidth
    var liveCells: [Int] = []
    liveCells.reserveCapacity(population)
    var candidates = Set<Int>()
    candidates.reserveCapacity(max(16, population * 9))

    for y in 0..<height {
      let row = y * stride
      for x in 0..<width where cells[row + x] {
        let index = row + x
        liveCells.append(index)
        for dy in -1...1 {
          let neighborY = (y + dy + height) % height
          for dx in -1...1 {
            let neighborX = (x + dx + width) % width
            candidates.insert(neighborY * stride + neighborX)
          }
        }
      }
    }

    var nextLiveCells: [Int] = []
    nextLiveCells.reserveCapacity(candidates.count)
    for index in candidates {
      let y = index / stride
      let x = index - y * stride
      let yUp = (y - 1 + height) % height
      let yDn = (y + 1) % height
      let rowMid = y * stride
      let rowUp = yUp * stride
      let rowDn = yDn * stride
      let xLt = (x - 1 + width) % width
      let xRt = (x + 1) % width

      var n = 0
      if cells[rowUp + xLt] { n += 1 }
      if cells[rowUp + x] { n += 1 }
      if cells[rowUp + xRt] { n += 1 }
      if cells[rowMid + xLt] { n += 1 }
      if cells[rowMid + xRt] { n += 1 }
      if cells[rowDn + xLt] { n += 1 }
      if cells[rowDn + x] { n += 1 }
      if cells[rowDn + xRt] { n += 1 }

      let alive = cells[index]
      if (alive && (n == 2 || n == 3)) || (!alive && n == 3) {
        nextLiveCells.append(index)
      }
    }

    for index in liveCells {
      cells[index] = false
    }
    for index in nextLiveCells {
      cells[index] = true
    }
    population = nextLiveCells.count
    generation += 1
  }
}

// MARK: - Seed patterns

extension LifeGrid {
  /// Stamps a glider at (x,y). The glider is the canonical
  /// 5-cell spaceship, useful for visual demos because it never
  /// stabilizes on a finite grid.
  mutating func stampGlider(atX x: Int, y: Int) {
    let pattern: [(Int, Int)] = [
      (1, 0), (2, 1), (0, 2), (1, 2), (2, 2),
    ]
    for (dx, dy) in pattern { set(x + dx, y + dy, true) }
  }

  /// Stamps a small "pulsar"-style oscillator that's pleasant to watch
  /// at any zoom level.
  mutating func stampPulsar(atX x: Int, y: Int) {
    let pattern: [(Int, Int)] = [
      (2, 0), (3, 0), (4, 0),
      (8, 0), (9, 0), (10, 0),
      (0, 2), (5, 2), (7, 2), (12, 2),
      (0, 3), (5, 3), (7, 3), (12, 3),
      (0, 4), (5, 4), (7, 4), (12, 4),
      (2, 5), (3, 5), (4, 5),
      (8, 5), (9, 5), (10, 5),
    ]
    for (dx, dy) in pattern { set(x + dx, y + dy, true) }
  }

  /// Seeds a default arrangement: a couple of gliders and an oscillator,
  /// centered in the visible area. Useful as the demo's default state.
  mutating func seedDefault() {
    clear()
    let cx = max(0, width / 2 - 8)
    let cy = max(0, height / 2 - 6)
    stampGlider(atX: max(2, cx - 16), y: max(2, cy - 4))
    stampGlider(atX: max(2, cx - 12), y: max(2, cy + 6))
    stampPulsar(atX: cx, y: cy)
    generation = 0
  }
}

// MARK: - Deterministic RNG (used for "Random" button so screenshots stay stable when seeded)

private struct SeededRNG: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed != 0 ? seed : 0xdeadbeef_cafebabe
  }

  mutating func next() -> UInt64 {
    // splitmix64
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z &>> 31)
  }
}
