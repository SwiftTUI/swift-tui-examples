import Foundation

/// Deterministic color reduction for the import path.
///
/// A GIF can carry up to 256 colors *per frame*, so the union across an
/// animation routinely exceeds the one shared palette the editor's
/// document model allows. `Quantizer` picks the ≤255 opaque colors that
/// palette should hold (slot 0 stays reserved for transparency) and maps
/// every source pixel onto them.
///
/// The algorithm is median cut over the union of all composited frames.
/// Two properties matter more than image quality here:
///
/// * **Order independence.** The palette is a function of the *set* of
///   colors and their pixel populations, never of the order frames or
///   pixels arrive in. The scheme this replaced kept the first 255
///   distinct colors it saw, so a GIF whose interesting colors appeared
///   late got a palette built entirely from its first frame's
///   background.
/// * **Determinism.** Golden tests pin palette bytes, so every choice —
///   which channel to split, where to split it, which box to split next,
///   and the order of the emitted palette — is resolved by an explicit
///   total order. No comparison depends on `Dictionary` iteration order
///   or on `sort`'s instability.
///
/// ## Tie-breaking, in one place
///
/// 1. **Which channel to split:** the one with the widest range in the
///    box. Ties resolve **R → G → B** (red beats green and blue; green
///    beats blue).
/// 2. **Where to split:** at the **population median** — the smallest
///    prefix of the channel-sorted box holding at least half its pixels.
///    When populations are uniform this reduces exactly to the count
///    median with the **lower index** on an even count.
/// 3. **Sort order inside a box:** `(channel value, packed RGB)`. Packed
///    RGB is unique per entry, so the comparison is a total order and
///    `sort`'s instability cannot leak through.
/// 4. **Which box to split next:** the largest **population**. Ties
///    resolve to the box with the smaller start offset in the
///    packed-RGB-sorted entry array — a position that never depends on
///    input order.
/// 5. **Emitted palette order:** ascending packed RGB, so the palette is
///    a function of the chosen colors alone and not of the split
///    sequence that found them.
///
/// ## Population, not box count
///
/// Both the "which box next" choice and the split point are weighted by
/// **pixel population**, not by the number of distinct colors in the
/// box. The alternative — split the box holding the most distinct
/// colors, at its count median — spends palette slots on however many
/// distinct values an image happens to contain, so a thousand
/// near-identical anti-aliasing colors covering 2% of the canvas outvote
/// a flat fill covering half of it. Population weighting spends slots
/// where the pixels are, which is what a viewer sees. The cost is that a
/// small but visually important accent can be under-served; that is the
/// trade this import path accepts, and dithering is the escape hatch.
///
/// Quantization runs over **distinct colors weighted by population**,
/// never over raw pixels: the union of 20 frames at 256×256 is ~1.3M
/// pixels but at most a few hundred distinct colors for a GIF source, so
/// the histogram is built once and the median cut is cheap.
public enum Quantizer {

  // MARK: - Options

  /// How source colors are mapped onto the reduced palette.
  public enum Dithering: String, Hashable, Sendable, Codable {
    /// Each pixel takes its nearest palette color. Hard edges, no
    /// added texture — the default, because pixel art is the common
    /// import and dithering destroys its flat fills.
    case none
    /// Floyd–Steinberg error diffusion in serpentine scan order.
    case floydSteinberg
  }

  /// Import-time quantization settings.
  public struct Options: Hashable, Sendable {
    /// Upper bound on *opaque* palette entries. Slot 0 stays reserved
    /// for transparency, so the resulting palette uses at most
    /// `maxColors + 1` slots.
    public var maxColors: Int
    /// Defaults to ``Dithering/none`` per the import binding decision.
    public var dithering: Dithering

    public init(
      maxColors: Int = ColorPalette.capacity - 1,
      dithering: Dithering = .none
    ) {
      self.maxColors = max(1, min(maxColors, ColorPalette.capacity - 1))
      self.dithering = dithering
    }

    public static let `default` = Options()
  }

  /// A quantized import: the shared palette plus one index array per
  /// frame, in the order the frames were handed in.
  public struct Result: Hashable, Sendable {
    public let palette: ColorPalette
    /// Row-major palette indices per frame; `nil` is transparent.
    public let frames: [[PaletteIndex?]]
    /// How many opaque colors the quantizer emitted. Palette slots
    /// `1...opaqueColorCount` hold them; slot 0 is the transparent
    /// sentinel and anything past that is padding.
    public let opaqueColorCount: Int
    /// `true` when the source fit inside `maxColors` and every pixel
    /// therefore maps to its exact color.
    public let isLossless: Bool
  }

  // MARK: - Entry point

  /// Quantizes composited frames into a shared palette and index arrays.
  ///
  /// `frames` are composited RGB frames — `nil` marks a transparent
  /// pixel — and every frame must have `size.area` elements.
  public static func quantize(
    frames: [[EditorColor?]],
    size: PixelSize,
    options: Options = .default
  ) -> Result {
    let histogram = histogram(of: frames)
    let opaque = palette(histogram: histogram, maxColors: options.maxColors)
    let palette = ColorPalette(colors: [.transparent] + opaque)

    // Exact matches short-circuit the nearest-color scan, and on the
    // lossless path they *are* the whole mapping.
    var exact: [EditorColor: PaletteIndex] = [:]
    exact.reserveCapacity(opaque.count)
    for (offset, color) in opaque.enumerated() {
      exact[color] = PaletteIndex(offset + 1)
    }

    let mapped: [[PaletteIndex?]] = frames.map { frame in
      switch options.dithering {
      case .none:
        var resolver = Resolver(palette: palette, exact: exact)
        return frame.map { color in
          guard let color else { return nil }
          return resolver.index(for: color)
        }
      case .floydSteinberg:
        // A resolver per frame keeps its memo table bounded, and the
        // error buffer inside `floydSteinberg` is allocated per frame
        // so diffusion can never reach across a frame boundary.
        var resolver = Resolver(palette: palette, exact: exact)
        return floydSteinberg(frame: frame, size: size, resolver: &resolver)
      }
    }

    return Result(
      palette: palette,
      frames: mapped,
      opaqueColorCount: opaque.count,
      isLossless: histogram.count <= options.maxColors
    )
  }

  // MARK: - Histogram

  /// Pixel population per distinct opaque color across every frame.
  ///
  /// Transparent pixels carry no color and are not counted; they map to
  /// the reserved slot without consulting the palette at all.
  public static func histogram(of frames: [[EditorColor?]]) -> [EditorColor: Int] {
    var counts: [EditorColor: Int] = [:]
    for frame in frames {
      for pixel in frame {
        guard let pixel, pixel.alpha > 0 else { continue }
        // Normalize alpha so a source that varies it cannot split one
        // RGB triple across several histogram buckets.
        counts[EditorColor(red: pixel.red, green: pixel.green, blue: pixel.blue), default: 0] += 1
      }
    }
    return counts
  }

  // MARK: - Median cut

  /// The ≤`maxColors` opaque colors median cut selects for a histogram,
  /// ascending by packed RGB.
  ///
  /// When the histogram already fits, this returns its colors verbatim —
  /// the import is then lossless by construction, which is the property
  /// every ≤255-color GIF round-trip depends on.
  public static func palette(
    histogram: [EditorColor: Int],
    maxColors: Int = ColorPalette.capacity - 1
  ) -> [EditorColor] {
    let limit = max(1, min(maxColors, ColorPalette.capacity - 1))

    // Sorting by packed RGB here is what makes everything downstream
    // reproducible: `Dictionary` iteration order is unspecified and
    // varies between runs of the same binary.
    var entries = histogram.map { Entry(color: $0.key, population: $0.value) }
    entries.sort { $0.packed < $1.packed }
    guard entries.count > limit else { return entries.map(\.color) }

    let totalPopulation = entries.reduce(0) { $0 + $1.population }
    var boxes = [Box(start: 0, end: entries.count, population: totalPopulation)]
    while boxes.count < limit, let target = indexOfBoxToSplit(boxes) {
      let (lower, upper) = split(box: boxes[target], entries: &entries)
      boxes[target] = lower
      boxes.append(upper)
    }

    var colors = boxes.map { representative(of: $0, in: entries) }
    colors.sort { Entry.pack($0) < Entry.pack($1) }
    return colors
  }

  /// The box to split next: greatest population, ties to the smaller
  /// start offset. Single-color boxes are unsplittable and skipped.
  private static func indexOfBoxToSplit(_ boxes: [Box]) -> Int? {
    var best: Int?
    for (index, box) in boxes.enumerated() where box.count > 1 {
      guard let current = best else {
        best = index
        continue
      }
      let incumbent = boxes[current]
      if box.population > incumbent.population
        || (box.population == incumbent.population && box.start < incumbent.start)
      {
        best = index
      }
    }
    return best
  }

  /// Splits one box in place, returning the lower and upper halves.
  private static func split(box: Box, entries: inout [Entry]) -> (Box, Box) {
    let range = box.start..<box.end
    var minima = (r: Int(UInt8.max), g: Int(UInt8.max), b: Int(UInt8.max))
    var maxima = (r: 0, g: 0, b: 0)
    for i in range {
      let color = entries[i].color
      minima.r = min(minima.r, Int(color.red))
      minima.g = min(minima.g, Int(color.green))
      minima.b = min(minima.b, Int(color.blue))
      maxima.r = max(maxima.r, Int(color.red))
      maxima.g = max(maxima.g, Int(color.green))
      maxima.b = max(maxima.b, Int(color.blue))
    }
    let spans = (r: maxima.r - minima.r, g: maxima.g - minima.g, b: maxima.b - minima.b)

    // Widest channel; ties resolve R → G → B.
    let channel: Channel
    if spans.r >= spans.g, spans.r >= spans.b {
      channel = .red
    } else if spans.g >= spans.b {
      channel = .green
    } else {
      channel = .blue
    }

    // `(channel value, packed RGB)` is a total order because packed RGB
    // is unique per entry, so the sort's instability never shows.
    var slice = Array(entries[range])
    slice.sort { lhs, rhs in
      let a = channel.value(of: lhs.color)
      let b = channel.value(of: rhs.color)
      return a == b ? lhs.packed < rhs.packed : a < b
    }
    entries.replaceSubrange(range, with: slice)

    // Population median. `(population + 1) / 2` is the lower-index
    // median when populations are uniform.
    let target = (box.population + 1) / 2
    var cumulative = 0
    var lowerEnd = box.start
    for i in range {
      cumulative += entries[i].population
      if cumulative >= target {
        lowerEnd = i
        break
      }
    }
    // Both halves must be non-empty; a dominant leading color would
    // otherwise swallow the whole box.
    lowerEnd = min(max(lowerEnd, box.start), box.end - 2)

    var lowerPopulation = 0
    for i in box.start...lowerEnd {
      lowerPopulation += entries[i].population
    }
    return (
      Box(start: box.start, end: lowerEnd + 1, population: lowerPopulation),
      Box(start: lowerEnd + 1, end: box.end, population: box.population - lowerPopulation)
    )
  }

  /// A box's color: the population-weighted mean of its members, rounded
  /// half up. A single-color box therefore reproduces that color exactly.
  private static func representative(of box: Box, in entries: [Entry]) -> EditorColor {
    var sums = (r: 0, g: 0, b: 0)
    var population = 0
    for i in box.start..<box.end {
      let entry = entries[i]
      sums.r += Int(entry.color.red) * entry.population
      sums.g += Int(entry.color.green) * entry.population
      sums.b += Int(entry.color.blue) * entry.population
      population += entry.population
    }
    guard population > 0 else { return .black }
    func mean(_ sum: Int) -> UInt8 {
      UInt8(clamping: (2 * sum + population) / (2 * population))
    }
    return EditorColor(red: mean(sums.r), green: mean(sums.g), blue: mean(sums.b))
  }

  // MARK: - Floyd–Steinberg

  /// Diffuses each pixel's quantization error into its unvisited
  /// neighbours, in **serpentine** order: even rows run left to right,
  /// odd rows right to left, with the neighbour offsets mirrored to
  /// match. Serpentine avoids the diagonal "worming" a uniform
  /// left-to-right scan leaves in gradients, at no extra cost.
  ///
  /// Error accumulates in fixed point at scale 16, which is exactly the
  /// Floyd–Steinberg denominator — so distributing an error loses
  /// nothing to integer division, and the only rounding is the one
  /// symmetric divide when the error is read back. That keeps the output
  /// identical on every platform.
  ///
  /// The accumulator is local to this call, so error never crosses a
  /// frame boundary. Transparent pixels emit no error and absorb
  /// whatever reached them.
  private static func floydSteinberg(
    frame: [EditorColor?],
    size: PixelSize,
    resolver: inout Resolver
  ) -> [PaletteIndex?] {
    let width = size.width
    let height = size.height
    guard width > 0, height > 0, frame.count == width * height else {
      return frame.map { color in
        guard let color else { return nil }
        return resolver.index(for: color)
      }
    }

    var output = [PaletteIndex?](repeating: nil, count: frame.count)
    var errorRed = [Int](repeating: 0, count: frame.count)
    var errorGreen = [Int](repeating: 0, count: frame.count)
    var errorBlue = [Int](repeating: 0, count: frame.count)

    for y in 0..<height {
      let leftToRight = y % 2 == 0
      let step = leftToRight ? 1 : -1
      let columns =
        leftToRight
        ? stride(from: 0, to: width, by: 1)
        : stride(from: width - 1, to: -1, by: -1)
      for x in columns {
        let index = y * width + x
        guard let source = frame[index] else { continue }

        let red = clampChannel(Int(source.red) + rounded(errorRed[index], by: 16))
        let green = clampChannel(Int(source.green) + rounded(errorGreen[index], by: 16))
        let blue = clampChannel(Int(source.blue) + rounded(errorBlue[index], by: 16))
        let corrected = EditorColor(
          red: UInt8(red),
          green: UInt8(green),
          blue: UInt8(blue)
        )

        let slot = resolver.index(for: corrected)
        output[index] = slot
        let chosen = resolver.palette[slot]
        let deltaRed = red - Int(chosen.red)
        let deltaGreen = green - Int(chosen.green)
        let deltaBlue = blue - Int(chosen.blue)

        // 7/16 ahead, then 3/16, 5/16, 1/16 on the row below. Weights
        // sum to 16, matching the accumulator's scale exactly.
        for (dx, dy, weight) in Self.diffusionKernel {
          let nx = x + dx * step
          let ny = y + dy
          guard nx >= 0, nx < width, ny < height else { continue }
          let target = ny * width + nx
          errorRed[target] += deltaRed * weight
          errorGreen[target] += deltaGreen * weight
          errorBlue[target] += deltaBlue * weight
        }
      }
    }
    return output
  }

  /// `(dx, dy, weight)` offsets, stated for a left-to-right row. `dx` is
  /// multiplied by the scan direction so an odd (right-to-left) row
  /// mirrors the kernel instead of diffusing into pixels it has already
  /// written.
  private static let diffusionKernel: [(Int, Int, Int)] = [
    (1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1),
  ]

  /// Symmetric round-half-away-from-zero. `Int` division truncates
  /// toward zero, which would bias negative error differently from
  /// positive error and make the output depend on a sign.
  private static func rounded(_ numerator: Int, by denominator: Int) -> Int {
    numerator >= 0
      ? (numerator + denominator / 2) / denominator
      : -((-numerator + denominator / 2) / denominator)
  }

  private static func clampChannel(_ value: Int) -> Int {
    min(255, max(0, value))
  }

  // MARK: - Supporting types

  /// A memoized palette lookup. `ColorPalette.nearestIndex(to:)` is a
  /// linear scan over every used slot, and a composited frame asks the
  /// same question for millions of pixels drawn from a handful of
  /// colors.
  private struct Resolver {
    let palette: ColorPalette
    private var memo: [EditorColor: PaletteIndex]

    init(palette: ColorPalette, exact: [EditorColor: PaletteIndex]) {
      self.palette = palette
      self.memo = exact
    }

    mutating func index(for color: EditorColor) -> PaletteIndex {
      let opaque =
        color.alpha == 255
        ? color
        : EditorColor(red: color.red, green: color.green, blue: color.blue)
      if let hit = memo[opaque] { return hit }
      let resolved = palette.nearestIndex(to: opaque)
      memo[opaque] = resolved
      return resolved
    }
  }

  private struct Entry {
    let color: EditorColor
    let population: Int
    let packed: UInt32

    init(color: EditorColor, population: Int) {
      self.color = color
      self.population = population
      self.packed = Self.pack(color)
    }

    /// 0xRRGGBB. Alpha is deliberately excluded — the histogram only
    /// ever holds opaque colors — so the packed value is both the
    /// canonical sort key and a stable identity.
    static func pack(_ color: EditorColor) -> UInt32 {
      (UInt32(color.red) << 16) | (UInt32(color.green) << 8) | UInt32(color.blue)
    }
  }

  /// A half-open slice of the entry array. Splitting only ever reorders
  /// entries *within* a box, so `start`/`end` stay valid for every other
  /// box in the list.
  private struct Box {
    let start: Int
    let end: Int
    let population: Int
    var count: Int { end - start }
  }

  private enum Channel {
    case red, green, blue

    func value(of color: EditorColor) -> UInt8 {
      switch self {
      case .red: return color.red
      case .green: return color.green
      case .blue: return color.blue
      }
    }
  }
}
