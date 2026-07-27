import Foundation
import Testing

@testable import GIFEditorCore

@Suite("ColorPalette")
struct PaletteTests {

  // MARK: - usedCount

  @Test("usedCount round-trips through init(colors:) and padding still fills to 256")
  func usedCountRoundTrips() throws {
    let entries = [
      EditorColor.transparent,
      EditorColor(rgbHex: 0xFF0000),
      EditorColor(rgbHex: 0x00FF00),
    ]
    let palette = ColorPalette(colors: entries)

    #expect(palette.usedCount == 3)
    #expect(palette.usedColors == entries)
    #expect(palette.colors.count == ColorPalette.capacity)
    // Padding still duplicates the last used color, which is what keeps
    // the GIF global color table byte-identical to before usedCount.
    for slot in palette.usedCount..<ColorPalette.capacity {
      #expect(palette.colors[slot] == entries[2])
    }
  }

  @Test("An empty color list still yields a well-formed one-slot palette")
  func emptyPaletteIsWellFormed() throws {
    let palette = ColorPalette(colors: [])
    #expect(palette.usedCount == 1)
    #expect(palette.colors.count == ColorPalette.capacity)
    #expect(palette[ColorPalette.transparentSlot] == .transparent)
  }

  @Test("More colors than capacity clamp to capacity")
  func oversizedInputClamps() throws {
    let entries = (0..<300).map { EditorColor(rgbHex: UInt32($0)) }
    let palette = ColorPalette(colors: entries)
    #expect(palette.usedCount == ColorPalette.capacity)
    #expect(palette.colors.count == ColorPalette.capacity)
    #expect(palette.colors == Array(entries.prefix(ColorPalette.capacity)))
  }

  @Test("The default palette reports its 32 authored slots")
  func defaultPaletteUsedCount() throws {
    #expect(ColorPalette.default.usedCount == 32)
    #expect(ColorPalette.default.colors.count == ColorPalette.capacity)
  }

  // MARK: - nearestIndex (F7)

  @Test("nearestIndex ignores unused slots even when padding holds a much nearer color")
  func nearestIndexIgnoresUnusedSlots() throws {
    var palette = ColorPalette(colors: [
      EditorColor(rgbHex: 0xFF0000),  // red
      EditorColor(rgbHex: 0x008080),  // teal
    ])
    #expect(palette.usedCount == 2)

    // Slot access is raw by design, so an unused slot can hold anything.
    // Before usedCount existed the scan covered all 256 slots and this
    // probe resolved to slot 200.
    let probe = EditorColor(rgbHex: 0x00FF00)
    palette[200] = EditorColor(rgbHex: 0x00FE00)

    #expect(palette[200].distanceSquared(to: probe) < palette[0].distanceSquared(to: probe))
    #expect(palette[200].distanceSquared(to: probe) < palette[1].distanceSquared(to: probe))
    #expect(palette.nearestIndex(to: probe) == 1)
  }

  @Test("nearestIndex agrees with a brute-force scan over the used slots")
  func nearestIndexMatchesBruteForce() throws {
    let palette = ColorPalette.default
    for raw in stride(from: 0, through: 0xFFFFFF, by: 0x3D71) {
      let probe = EditorColor(rgbHex: UInt32(raw))
      let expected = bruteForceNearest(in: palette, to: probe)
      #expect(palette.nearestIndex(to: probe) == expected)
    }
  }

  @Test("nearestIndex skips fully transparent used slots")
  func nearestIndexSkipsTransparentSlots() throws {
    let palette = ColorPalette(colors: [
      .transparent,
      EditorColor(rgbHex: 0x101010),
    ])
    // Transparent is the closest slot numerically but must be skipped.
    #expect(palette.nearestIndex(to: EditorColor(red: 0, green: 0, blue: 0)) == 1)
  }

  // MARK: - append

  @Test("append lands in the first unused slot and re-pads the tail")
  func appendUsesFirstUnusedSlot() throws {
    var palette = ColorPalette(colors: [EditorColor(rgbHex: 0x112233)])
    let added = EditorColor(rgbHex: 0x445566)

    let index = palette.append(added)
    #expect(index == 1)
    #expect(palette.usedCount == 2)
    #expect(palette[1] == added)
    #expect(palette.colors.count == ColorPalette.capacity)
    #expect(palette.colors[ColorPalette.capacity - 1] == added)
    #expect(palette.nearestIndex(to: added) == 1)
  }

  @Test("append past capacity returns nil and leaves the palette untouched")
  func appendPastCapacityIsRejected() throws {
    var palette = ColorPalette(
      colors: (0..<ColorPalette.capacity).map { EditorColor(rgbHex: UInt32($0)) }
    )
    let before = palette
    #expect(palette.usedCount == ColorPalette.capacity)

    let index = palette.append(EditorColor(rgbHex: 0xABCDEF))
    #expect(index == nil)
    #expect(palette == before)
    #expect(palette.usedCount == ColorPalette.capacity)
    #expect(palette.colors.count == ColorPalette.capacity)
  }

  // MARK: - remove

  @Test("remove shifts survivors down and reports the permutation they moved by")
  func removePermutationTracksSurvivors() throws {
    let entries: [EditorColor] = [
      .transparent,
      EditorColor(rgbHex: 0xFF0000),
      EditorColor(rgbHex: 0x00FF00),
      EditorColor(rgbHex: 0x0000FF),
    ]
    let palette = ColorPalette(colors: entries)
    let (result, permutation) = palette.remove(at: 2)

    #expect(result.usedCount == 3)
    #expect(result.usedColors == [entries[0], entries[1], entries[3]])
    #expect(permutation.count == ColorPalette.capacity)
    #expect(permutation[0] == 0)
    #expect(permutation[1] == 1)
    #expect(permutation[3] == 2)
    // Every surviving old index must name a slot holding its own color.
    for old in [0, 1, 3] {
      #expect(result[permutation[old]] == entries[old])
    }
    // Padding follows the last used slot.
    for old in palette.usedCount..<ColorPalette.capacity {
      #expect(permutation[old] == permutation[palette.usedCount - 1])
    }
  }

  @Test("The removed index maps to the nearest surviving color")
  func removedIndexMapsToNearestSurvivor() throws {
    let palette = ColorPalette(colors: [
      .transparent,
      EditorColor(rgbHex: 0xFF0000),  // red
      EditorColor(rgbHex: 0xFE0101),  // near-identical red — the survivor
      EditorColor(rgbHex: 0x0000FF),  // blue
    ])
    let (result, permutation) = palette.remove(at: 1)

    // Old slot 2 shifted down to 1; the removed slot 1 must resolve to it.
    #expect(permutation[2] == 1)
    #expect(permutation[1] == 1)
    #expect(result[permutation[1]] == EditorColor(rgbHex: 0xFE0101))
  }

  @Test("remove refuses the pinned transparent slot, out-of-use slots, and the last color")
  func removeRefusesIllegalTargets() throws {
    let palette = ColorPalette(colors: [
      .transparent,
      EditorColor(rgbHex: 0xFF0000),
    ])
    let identity = ColorPalette.identityPermutation

    let pinned = palette.remove(at: ColorPalette.transparentSlot)
    #expect(pinned.palette == palette)
    #expect(pinned.permutation == identity)

    let unused = palette.remove(at: 200)
    #expect(unused.palette == palette)
    #expect(unused.permutation == identity)

    let single = ColorPalette(colors: [EditorColor(rgbHex: 0x123456)])
    let lastOne = single.remove(at: 0)
    #expect(lastOne.palette == single)
    #expect(lastOne.permutation == identity)
  }

  // MARK: - compact

  @Test("compact collapses duplicates and every old index still names its own color")
  func compactCollapsesDuplicates() throws {
    let red = EditorColor(rgbHex: 0xFF0000)
    let blue = EditorColor(rgbHex: 0x0000FF)
    let entries: [EditorColor] = [.transparent, red, blue, red, blue, red]
    let palette = ColorPalette(colors: entries)

    let (result, permutation) = palette.compact()
    #expect(result.usedCount == 3)
    #expect(result.usedColors == [.transparent, red, blue])
    // First occurrence wins, so the pinned transparent slot stays at 0.
    #expect(permutation[0] == 0)
    for old in 0..<palette.usedCount {
      #expect(result[permutation[old]] == entries[old])
    }
    for old in palette.usedCount..<ColorPalette.capacity {
      #expect(result[permutation[old]] == entries[entries.count - 1])
    }
  }

  @Test("compact leaves a duplicate-free palette alone")
  func compactIsIdempotentWithoutDuplicates() throws {
    let palette = ColorPalette.default
    let (result, permutation) = palette.compact()
    #expect(result == palette)
    for old in 0..<palette.usedCount {
      #expect(permutation[old] == PaletteIndex(old))
    }
    // Padding never maps to itself: it holds a copy of the last used
    // color, so it follows that slot. Color-preserving either way.
    for old in palette.usedCount..<ColorPalette.capacity {
      #expect(permutation[old] == PaletteIndex(palette.usedCount - 1))
      #expect(result[permutation[old]] == palette.colors[old])
    }
  }

  // MARK: - sorted

  @Test("sorted reorders used slots, pins slot 0, and reports where each slot went")
  func sortedPermutationTracksSlots() throws {
    let entries: [EditorColor] = [
      .transparent,
      EditorColor(rgbHex: 0x0000FF),
      EditorColor(rgbHex: 0xFF0000),
      EditorColor(rgbHex: 0x00FF00),
    ]
    let palette = ColorPalette(colors: entries)
    let (result, permutation) = palette.sorted { $0.red < $1.red }

    #expect(result.usedCount == 4)
    #expect(result[ColorPalette.transparentSlot] == .transparent)
    #expect(permutation[0] == 0)
    // blue (0) and green (0) tie on red and keep their relative order;
    // red (255) sorts last.
    #expect(result.usedColors == [entries[0], entries[1], entries[3], entries[2]])
    for old in 0..<palette.usedCount {
      #expect(result[permutation[old]] == entries[old])
    }
    for old in palette.usedCount..<ColorPalette.capacity {
      #expect(permutation[old] == permutation[palette.usedCount - 1])
    }
  }

  @Test("sorted is stable, so equal colors keep their relative order")
  func sortedIsStable() throws {
    let entries: [EditorColor] = [
      .transparent,
      EditorColor(rgbHex: 0x000010),
      EditorColor(rgbHex: 0x000020),
      EditorColor(rgbHex: 0x000030),
    ]
    let palette = ColorPalette(colors: entries)
    // Every color compares equal under this predicate.
    let (result, permutation) = palette.sorted { _, _ in false }
    #expect(result == palette)
    for old in 0..<palette.usedCount {
      #expect(permutation[old] == PaletteIndex(old))
    }
  }

  @Test("sorted is a no-op when only the pinned slot is in use")
  func sortedNoOpOnSingleSlot() throws {
    let palette = ColorPalette(colors: [.transparent])
    let (result, permutation) = palette.sorted { $0.red < $1.red }
    #expect(result == palette)
    #expect(permutation == ColorPalette.identityPermutation)
  }

  @Test("Every edit preserves the exactly-capacity invariant the encoder relies on")
  func editsPreserveCapacityInvariant() throws {
    var palette = ColorPalette.default
    _ = palette.append(EditorColor(rgbHex: 0x123456))
    let removed = palette.remove(at: 5).palette
    let compacted = removed.compact().palette
    let sorted = compacted.sorted { $0.blue < $1.blue }.palette

    for candidate in [palette, removed, compacted, sorted] {
      #expect(candidate.colors.count == ColorPalette.capacity)
      #expect((1...ColorPalette.capacity).contains(candidate.usedCount))
      // Padding always mirrors the last used slot.
      let last = candidate.colors[candidate.usedCount - 1]
      for slot in candidate.usedCount..<ColorPalette.capacity {
        #expect(candidate.colors[slot] == last)
      }
    }
  }

  private func bruteForceNearest(
    in palette: ColorPalette,
    to color: EditorColor
  ) -> PaletteIndex {
    var best: (index: PaletteIndex, distance: Int) = (0, .max)
    for (i, candidate) in palette.usedColors.enumerated() where candidate.alpha != 0 {
      let d = color.distanceSquared(to: candidate)
      if d < best.distance { best = (PaletteIndex(i), d) }
    }
    return best.index
  }
}
