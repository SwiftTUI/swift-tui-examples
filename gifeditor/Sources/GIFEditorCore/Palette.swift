import Foundation

/// An sRGB color stored as 8-bit-per-channel RGBA.
///
/// `GIFEditorCore` deliberately avoids depending on the framework's much
/// richer `SwiftTUICore.Color` so the model layer stays platform-neutral. The UI
/// layer converts between this and `SwiftTUICore.Color` at the boundary.
public struct EditorColor: Hashable, Sendable, Codable {
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8
  public var alpha: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// Constructs from a 0xRRGGBB literal, full alpha.
  public init(rgbHex: UInt32) {
    self.init(
      red: UInt8((rgbHex >> 16) & 0xFF),
      green: UInt8((rgbHex >> 8) & 0xFF),
      blue: UInt8(rgbHex & 0xFF),
      alpha: 255
    )
  }

  public static let black = EditorColor(rgbHex: 0x000000)
  public static let white = EditorColor(rgbHex: 0xFFFFFF)
  public static let transparent = EditorColor(red: 0, green: 0, blue: 0, alpha: 0)

  /// Squared RGB distance — sufficient for nearest-color quantization.
  public func distanceSquared(to other: EditorColor) -> Int {
    let dr = Int(red) - Int(other.red)
    let dg = Int(green) - Int(other.green)
    let db = Int(blue) - Int(other.blue)
    return dr * dr + dg * dg + db * db
  }
}

/// Index into a palette. GIF restricts palettes to 256 entries.
public typealias PaletteIndex = UInt8

/// A 256-color palette shared across the document.
///
/// Slot 0 is reserved as the document's "transparent" sentinel for
/// export — pixels stored as `nil` map to slot 0 and slot 0 is marked as
/// the GIF's transparent index. Authors can still pick slot 0 as a
/// drawing color; we just guarantee at least one slot is available for
/// the transparency role.
public struct ColorPalette: Hashable, Sendable, Codable {
  /// Always exactly `Self.capacity` entries; slots at or past
  /// ``usedCount`` are padding — duplicates of the last used color — so
  /// ``subscript(_:)`` can never trap and the GIF global color table is
  /// always a full 256 entries.
  public private(set) var colors: [EditorColor]
  public static let capacity: Int = 256

  /// How many leading slots the author is actually using. Always in
  /// `1...capacity`.
  ///
  /// Padding used to be indistinguishable from real content, which made
  /// nearest-color matching lean toward whatever color happened to get
  /// duplicated into the tail, and left "add a color" with no meaning.
  /// The count is taken from the array handed to ``init(colors:)``
  /// *before* padding, and every structural edit below re-derives it
  /// through that same initializer.
  public private(set) var usedCount: Int

  /// Reserved slot used to represent "transparent" when flattening a
  /// document for GIF export. Authors editing this slot will see that
  /// the GIF's transparent pixels recolor accordingly.
  ///
  /// The slot is *pinned*: ``sorted(by:)`` never moves it and
  /// ``remove(at:)`` refuses to delete it, because pixels stored as
  /// `nil` carry no index and so cannot be carried across by an index
  /// permutation — they always land back on slot 0 at export time.
  public static let transparentSlot: PaletteIndex = 0

  /// The single normalizing entry point. Everything else — the mutating
  /// API below, and (later) decoding — routes through here so the
  /// "exactly `capacity` entries, padding duplicates the last used
  /// color" invariant has one owner.
  public init(colors: [EditorColor]) {
    var bounded = Array(colors.prefix(Self.capacity))
    if bounded.isEmpty {
      bounded = [.transparent]
    }
    self.usedCount = bounded.count
    while bounded.count < Self.capacity {
      bounded.append(bounded.last ?? .black)
    }
    self.colors = bounded
  }

  /// Raw slot access. The setter writes the slot verbatim and does *not*
  /// grow ``usedCount`` — a write at or past `usedCount` lands in
  /// padding, stays invisible to ``nearestIndex(to:)``, and is
  /// overwritten by the next structural edit. Use ``append(_:)`` to add
  /// a color.
  public subscript(index: PaletteIndex) -> EditorColor {
    get { colors[Int(index)] }
    set { colors[Int(index)] = newValue }
  }

  /// The used slots only, in order — what a palette editor renders and
  /// what a `.hex` / `.gpl` export would write.
  public var usedColors: [EditorColor] {
    Array(colors.prefix(usedCount))
  }

  /// Nearest color among the *used* slots by squared RGB distance,
  /// ignoring transparent slots (alpha == 0). Falls back to slot 0 when
  /// every used slot is transparent.
  public func nearestIndex(to color: EditorColor) -> PaletteIndex {
    var best: (index: PaletteIndex, distance: Int) = (0, .max)
    for i in 0..<usedCount {
      let candidate = colors[i]
      if candidate.alpha == 0 { continue }
      let d = color.distanceSquared(to: candidate)
      if d < best.distance {
        best = (PaletteIndex(i), d)
        if d == 0 { break }
      }
    }
    return best.index
  }

  // MARK: - Editing
  //
  // `remove(at:)`, `compact()`, and `sorted(by:)` each return the index
  // permutation they imply alongside the new palette, indexed by the
  // *old* slot: `permutation[old] == new`. The array is always
  // `capacity` long so a caller can remap any `PaletteIndex` —
  // `permutation[Int(oldIndex)]` — without a bounds check. Applying it
  // document-wide (every `PixelBuffer`, the primary/secondary selection,
  // the clipboard) is the caller's job; handing back a correct
  // permutation is ours.

  /// Adds a color in the first unused slot and returns its index, or
  /// `nil` when all `capacity` slots are already in use. A full palette
  /// is left untouched.
  public mutating func append(_ color: EditorColor) -> PaletteIndex? {
    guard usedCount < Self.capacity else { return nil }
    let index = PaletteIndex(usedCount)
    self = ColorPalette(colors: usedColors + [color])
    return index
  }

  /// Removes a used slot, shifting everything after it down one.
  ///
  /// The removed index has no successor of its own, so it maps to the
  /// **nearest surviving color** — `nearestIndex(to:)` on the resulting
  /// palette — and pixels that referenced it recolor to the closest
  /// remaining choice instead of shifting arbitrarily. Padding indices
  /// follow the last used slot.
  ///
  /// A no-op returning the identity permutation when `index` is the
  /// pinned ``transparentSlot``, is not a used slot, or would empty the
  /// palette.
  public func remove(
    at index: PaletteIndex
  ) -> (palette: ColorPalette, permutation: [PaletteIndex]) {
    let slot = Int(index)
    guard slot != Int(Self.transparentSlot), slot < usedCount, usedCount > 1 else {
      return (self, Self.identityPermutation)
    }

    var entries = usedColors
    entries.remove(at: slot)
    let result = ColorPalette(colors: entries)

    var permutation = Self.identityPermutation
    for old in 0..<usedCount {
      if old < slot {
        permutation[old] = PaletteIndex(old)
      } else if old > slot {
        permutation[old] = PaletteIndex(old - 1)
      } else {
        permutation[old] = result.nearestIndex(to: colors[old])
      }
    }
    Self.extendPadding(&permutation, usedCount: usedCount)
    return (result, permutation)
  }

  /// Collapses duplicate colors among the used slots, keeping the first
  /// occurrence of each. Every old index maps to the surviving slot that
  /// holds its exact color, so a compact never changes a single rendered
  /// pixel — it only shortens the palette.
  ///
  /// Core cannot see the document's pixels, so this deliberately does
  /// *not* drop colors that merely go unreferenced; that is a caller's
  /// decision, made with a usage census in hand.
  public func compact() -> (palette: ColorPalette, permutation: [PaletteIndex]) {
    var entries: [EditorColor] = []
    var firstOccurrence: [EditorColor: PaletteIndex] = [:]
    var permutation = Self.identityPermutation

    for old in 0..<usedCount {
      let color = colors[old]
      if let existing = firstOccurrence[color] {
        permutation[old] = existing
      } else {
        let new = PaletteIndex(entries.count)
        firstOccurrence[color] = new
        entries.append(color)
        permutation[old] = new
      }
    }
    Self.extendPadding(&permutation, usedCount: usedCount)
    return (ColorPalette(colors: entries), permutation)
  }

  /// Reorders the used slots. Slot 0 stays pinned (see
  /// ``transparentSlot``) and only `1..<usedCount` is sorted.
  ///
  /// The sort is stable — equal colors keep their relative order — so
  /// the permutation is deterministic across platforms and a golden test
  /// can pin it.
  public func sorted(
    by areInIncreasingOrder: (EditorColor, EditorColor) -> Bool
  ) -> (palette: ColorPalette, permutation: [PaletteIndex]) {
    let pinned = Int(Self.transparentSlot)
    guard usedCount > pinned + 1 else { return (self, Self.identityPermutation) }

    var order = Array((pinned + 1)..<usedCount)
    order.sort { lhs, rhs in
      if areInIncreasingOrder(colors[lhs], colors[rhs]) { return true }
      if areInIncreasingOrder(colors[rhs], colors[lhs]) { return false }
      return lhs < rhs
    }

    var entries = [colors[pinned]]
    entries.append(contentsOf: order.map { colors[$0] })

    var permutation = Self.identityPermutation
    for (offset, old) in order.enumerated() {
      permutation[old] = PaletteIndex(pinned + 1 + offset)
    }
    Self.extendPadding(&permutation, usedCount: usedCount)
    return (ColorPalette(colors: entries), permutation)
  }

  /// `permutation[i] == i` for every slot — what the no-op edits return.
  ///
  /// Public because a caller that builds its *own* index map (adopting an
  /// imported palette remaps by nearest color, which is not a
  /// permutation of the old slots) needs the same `capacity`-long shape
  /// the editing API hands back, so one remap routine can consume both.
  public static var identityPermutation: [PaletteIndex] {
    (0..<capacity).map { PaletteIndex($0) }
  }

  /// Padding slots hold a copy of the last used color, so they follow
  /// wherever that slot went.
  private static func extendPadding(_ permutation: inout [PaletteIndex], usedCount: Int) {
    guard usedCount < capacity else { return }
    let lastUsed = permutation[usedCount - 1]
    for old in usedCount..<capacity {
      permutation[old] = lastUsed
    }
  }

  /// The default 32-color authoring palette. Slot 0 is transparent; the
  /// remaining 31 colors are a usable mix of greys, primaries, and
  /// pastels suitable for general doodling.
  public static let `default`: ColorPalette = {
    let entries: [EditorColor] = [
      .transparent,
      .black,
      .white,
      EditorColor(rgbHex: 0x808080),
      EditorColor(rgbHex: 0x404040),
      EditorColor(rgbHex: 0xC0C0C0),
      EditorColor(rgbHex: 0xE05757),  // red
      EditorColor(rgbHex: 0xEB7A3C),  // orange
      EditorColor(rgbHex: 0xEBB33C),  // yellow
      EditorColor(rgbHex: 0x61C67B),  // green
      EditorColor(rgbHex: 0x2E8B57),  // dark green
      EditorColor(rgbHex: 0x5BA3FF),  // blue
      EditorColor(rgbHex: 0x1E5AAE),  // dark blue
      EditorColor(rgbHex: 0x56B6C2),  // cyan
      EditorColor(rgbHex: 0xB46EFF),  // magenta
      EditorColor(rgbHex: 0xFF8FB4),  // pink
      EditorColor(rgbHex: 0x8B5A2B),  // brown
      EditorColor(rgbHex: 0xC9A878),  // tan
      EditorColor(rgbHex: 0xF5DEB3),  // wheat
      EditorColor(rgbHex: 0xFFD7E4),  // light pink
      EditorColor(rgbHex: 0xFFEFAA),  // light yellow
      EditorColor(rgbHex: 0xCEEBC1),  // mint
      EditorColor(rgbHex: 0xC4DEFF),  // light blue
      EditorColor(rgbHex: 0xE3D3FF),  // lavender
      EditorColor(rgbHex: 0x7A1F1F),  // wine
      EditorColor(rgbHex: 0x40220F),  // espresso
      EditorColor(rgbHex: 0x143D2A),  // forest
      EditorColor(rgbHex: 0x0D2C66),  // navy
      EditorColor(rgbHex: 0x6E1B8C),  // royal purple
      EditorColor(rgbHex: 0xFF005D),  // hot pink
      EditorColor(rgbHex: 0x00C896),  // teal
      EditorColor(rgbHex: 0xC0FF33),  // lime
    ]
    return ColorPalette(colors: entries)
  }()
}
