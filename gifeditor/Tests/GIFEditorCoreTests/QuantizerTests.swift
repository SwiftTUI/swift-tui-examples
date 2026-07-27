import Foundation
import Testing

@testable import GIFEditorCore

/// Unit tests for the median-cut quantizer itself. Every case here is
/// built from literal colors rather than a GIF, so a failure names the
/// rule that broke instead of the file that exposed it.
/// `ImportQuantizationTests` covers the same code through `GIFLoader`.
@Suite("Quantizer")
struct QuantizerTests {

  // MARK: - Lossless path

  @Test("A palette that already fits is reproduced exactly")
  func belowTheCeilingIsLossless() {
    // 200 distinct colors spread across the cube, deliberately *not* in
    // sorted order, so a quantizer that leaned on input order would show.
    let colors: [EditorColor] = (0..<200).map { (i: Int) -> EditorColor in
      let red: Int = (i &* 61) % 256
      let green: Int = (i &* 149) % 256
      let blue: Int = (i &* 7) % 256
      return EditorColor(red: UInt8(red), green: UInt8(green), blue: UInt8(blue))
    }
    #expect(Set(colors).count == 200)

    let frame: [EditorColor?] = colors.map { $0 }
    let result = Quantizer.quantize(
      frames: [frame],
      size: PixelSize(width: 200, height: 1)
    )

    #expect(result.isLossless)
    #expect(result.opaqueColorCount == 200)
    #expect(result.palette.usedCount == 201)
    #expect(result.palette[ColorPalette.transparentSlot] == .transparent)
    #expect(Set(result.palette.usedColors.dropFirst()) == Set(colors))

    // Every pixel round-trips bit-exactly.
    for (pixel, source) in zip(result.frames[0], colors) {
      guard let slot = pixel else {
        Issue.record("opaque pixel came back transparent")
        continue
      }
      #expect(result.palette[slot] == source)
    }
  }

  @Test("Transparent pixels stay transparent and cost no palette slot")
  func transparencyIsFree() {
    let frame: [EditorColor?] = [.black, nil, .white, nil]
    let result = Quantizer.quantize(frames: [frame], size: PixelSize(width: 4, height: 1))
    #expect(result.opaqueColorCount == 2)
    #expect(result.frames[0][1] == nil)
    #expect(result.frames[0][3] == nil)
    #expect(result.frames[0][0] != nil)
  }

  // MARK: - Determinism

  @Test("Quantizing the same input twice yields byte-identical palettes")
  func repeatedRunsAgree() {
    let frames = [gradientFrame(count: 900, seed: 3)]
    let first = Quantizer.palette(histogram: Quantizer.histogram(of: frames), maxColors: 255)
    let second = Quantizer.palette(histogram: Quantizer.histogram(of: frames), maxColors: 255)
    #expect(first == second)
    #expect(first.count == 255)
  }

  @Test("The palette does not depend on the order pixels arrive in")
  func pixelOrderDoesNotMatter() {
    let frame = gradientFrame(count: 900, seed: 11)
    let shuffled: [EditorColor?] = frame.reversed()
    let straight = Quantizer.palette(histogram: Quantizer.histogram(of: [frame]))
    let reversed = Quantizer.palette(histogram: Quantizer.histogram(of: [shuffled]))
    #expect(straight == reversed)
  }

  @Test("The palette does not depend on the order frames arrive in")
  func frameOrderDoesNotMatter() {
    // Three frames with disjoint color ranges: under a
    // first-N-colors-encountered scheme the palette is whichever frames
    // came first, so permuting them has to change the answer.
    let low = gradientFrame(count: 400, seed: 1)
    let mid = gradientFrame(count: 400, seed: 2)
    let high = gradientFrame(count: 400, seed: 3)

    let forward = Quantizer.palette(histogram: Quantizer.histogram(of: [low, mid, high]))
    let reversed = Quantizer.palette(histogram: Quantizer.histogram(of: [high, mid, low]))
    let rotated = Quantizer.palette(histogram: Quantizer.histogram(of: [mid, high, low]))

    #expect(forward == reversed)
    #expect(forward == rotated)
    #expect(forward.count == 255)
  }

  @Test("The emitted palette is sorted by packed RGB")
  func paletteIsSortedByPackedRGB() {
    let colors = Quantizer.palette(
      histogram: Quantizer.histogram(of: [gradientFrame(count: 900, seed: 5)])
    )
    let packed = colors.map {
      (UInt32($0.red) << 16) | (UInt32($0.green) << 8) | UInt32($0.blue)
    }
    #expect(packed == packed.sorted())
  }

  // MARK: - Tie-breaking

  @Test("A red/green range tie splits on red")
  func widestChannelTieResolvesToRed() {
    // r range == g range == 30, b range == 0.
    let histogram: [EditorColor: Int] = [
      EditorColor(red: 0, green: 0, blue: 0): 1,
      EditorColor(red: 0, green: 30, blue: 0): 1,
      EditorColor(red: 30, green: 0, blue: 0): 1,
      EditorColor(red: 30, green: 30, blue: 0): 1,
    ]
    // Splitting red groups by red and averages green; splitting green
    // would produce (15,0,0) / (15,30,0) instead.
    #expect(
      Quantizer.palette(histogram: histogram, maxColors: 2) == [
        EditorColor(red: 0, green: 15, blue: 0),
        EditorColor(red: 30, green: 15, blue: 0),
      ]
    )
  }

  @Test("A green/blue range tie splits on green")
  func widestChannelTieResolvesGreenBeforeBlue() {
    // r range == 0, g range == b range == 30.
    let histogram: [EditorColor: Int] = [
      EditorColor(red: 0, green: 0, blue: 0): 1,
      EditorColor(red: 0, green: 0, blue: 30): 1,
      EditorColor(red: 0, green: 30, blue: 0): 1,
      EditorColor(red: 0, green: 30, blue: 30): 1,
    ]
    // Splitting blue would produce (0,15,0) / (0,15,30).
    #expect(
      Quantizer.palette(histogram: histogram, maxColors: 2) == [
        EditorColor(red: 0, green: 0, blue: 15),
        EditorColor(red: 0, green: 30, blue: 15),
      ]
    )
  }

  @Test("An even-count median takes the lower index")
  func evenCountMedianTakesTheLowerIndex() {
    let histogram: [EditorColor: Int] = [
      EditorColor(red: 0, green: 0, blue: 0): 1,
      EditorColor(red: 10, green: 0, blue: 0): 1,
      EditorColor(red: 20, green: 0, blue: 0): 1,
      EditorColor(red: 30, green: 0, blue: 0): 1,
    ]
    // Lower index → {0,10} and {20,30}. The upper index would give
    // {0,10,20} → (10,0,0) and {30} → (30,0,0).
    #expect(
      Quantizer.palette(histogram: histogram, maxColors: 2) == [
        EditorColor(red: 5, green: 0, blue: 0),
        EditorColor(red: 25, green: 0, blue: 0),
      ]
    )
  }

  // MARK: - Population weighting

  @Test("A dominant color keeps its own slot against a crowd of noise")
  func populationOutweighsDistinctColorCount() {
    // Three near-identical noise colors against one color covering
    // ~99.7% of the pixels. Splitting by distinct-color count would put
    // the dominant color in a box with a noise color and smear it;
    // splitting by population gives it a box of its own.
    let dominant = EditorColor(red: 200, green: 200, blue: 200)
    let histogram: [EditorColor: Int] = [
      dominant: 1000,
      EditorColor(red: 0, green: 0, blue: 0): 1,
      EditorColor(red: 0, green: 0, blue: 10): 1,
      EditorColor(red: 0, green: 0, blue: 20): 1,
    ]
    let colors = Quantizer.palette(histogram: histogram, maxColors: 2)
    #expect(colors.contains(dominant))
    #expect(colors == [EditorColor(red: 0, green: 0, blue: 10), dominant])
  }

  // MARK: - Dithering

  @Test("Dithering is off by default")
  func ditheringDefaultsToOff() {
    #expect(Quantizer.Options().dithering == .none)
    #expect(Quantizer.Options.default.dithering == .none)

    let frames = [greyRamp(width: 16, height: 16)]
    let size = PixelSize(width: 16, height: 16)
    let byDefault = Quantizer.quantize(
      frames: frames,
      size: size,
      options: Quantizer.Options(maxColors: 2)
    )
    let explicit = Quantizer.quantize(
      frames: frames,
      size: size,
      options: Quantizer.Options(maxColors: 2, dithering: .none)
    )
    #expect(byDefault.frames == explicit.frames)
  }

  @Test("Dithering changes the output and stays deterministic")
  func ditheringChangesOutputDeterministically() {
    let frames = [greyRamp(width: 16, height: 16)]
    let size = PixelSize(width: 16, height: 16)
    let plain = Quantizer.quantize(
      frames: frames,
      size: size,
      options: Quantizer.Options(maxColors: 2)
    )
    let dithered = Quantizer.quantize(
      frames: frames,
      size: size,
      options: Quantizer.Options(maxColors: 2, dithering: .floydSteinberg)
    )
    let ditheredAgain = Quantizer.quantize(
      frames: frames,
      size: size,
      options: Quantizer.Options(maxColors: 2, dithering: .floydSteinberg)
    )

    // Same palette either way — dithering changes the mapping, never
    // the color selection.
    #expect(plain.palette == dithered.palette)
    #expect(plain.frames != dithered.frames)
    #expect(dithered.frames == ditheredAgain.frames)

    // Error diffusion has to mix both palette entries into rows that the
    // hard-threshold pass renders as a single flat run.
    let midRow = Array(dithered.frames[0][(8 * 16)..<(9 * 16)])
    #expect(Set(midRow).count == 2)
  }

  @Test("Dithering error does not diffuse across frame boundaries")
  func ditheringDoesNotLeakBetweenFrames() {
    // A flat frame whose color sits between the two palette entries, so
    // it accumulates error rather than resolving exactly. The palette is
    // order-independent, so the only thing that could make this frame
    // render differently in the two positions is error carried over from
    // whichever frame preceded it.
    let size = PixelSize(width: 16, height: 16)
    let noisy = greyRamp(width: 16, height: 16)
    let flat: [EditorColor?] = Array(
      repeating: EditorColor(red: 100, green: 100, blue: 100),
      count: size.area
    )
    let options = Quantizer.Options(maxColors: 2, dithering: .floydSteinberg)

    let flatSecond = Quantizer.quantize(frames: [noisy, flat], size: size, options: options)
    let flatFirst = Quantizer.quantize(frames: [flat, noisy], size: size, options: options)

    #expect(flatSecond.palette == flatFirst.palette)
    #expect(flatSecond.frames[1] == flatFirst.frames[0])
    #expect(flatSecond.frames[0] == flatFirst.frames[1])
  }

  // MARK: - Fixtures

  /// `count` distinct colors on a diagonal sweep through the RGB cube.
  /// `seed` shifts the sweep so two calls produce disjoint color ranges.
  private func gradientFrame(count: Int, seed: Int) -> [EditorColor?] {
    (0..<count).map { (i: Int) -> EditorColor? in
      let t: Int = i &+ seed &* 977
      let red: Int = (t &* 3) % 256
      let green: Int = (t &* 5) % 256
      let blue: Int = (t &* 11) % 256
      return EditorColor(red: UInt8(red), green: UInt8(green), blue: UInt8(blue))
    }
  }

  /// A horizontal grey ramp — the classic case where a two-color palette
  /// looks banded undithered and smooth dithered.
  private func greyRamp(width: Int, height: Int) -> [EditorColor?] {
    (0..<(width * height)).map { (i: Int) -> EditorColor? in
      let level: Int = (i % width) &* 255 / max(1, width - 1)
      return EditorColor(red: UInt8(level), green: UInt8(level), blue: UInt8(level))
    }
  }
}
