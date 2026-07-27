import Foundation

/// Where each frame of a document sits on a spritesheet.
///
/// **The column rule.** With no explicit count, `columns` is the smallest
/// integer whose square is at least the frame count — `ceil(sqrt(n))`,
/// computed in integers so it cannot drift with a floating-point library.
/// A 5-frame document lays out 3x2, a 16-frame one 4x4, a 17-frame one
/// 5x4.
///
/// The rule is chosen for the consumer, not for the writer. A single row
/// is the other obvious convention and is trivially simpler, but a
/// 60-frame 256-pixel animation becomes a 15360-pixel-wide texture, which
/// several engines will either refuse or silently downscale. A
/// near-square sheet keeps both axes near `sqrt(n) * cell`, which is the
/// smallest either axis can be, and it is the shape Unity's and Godot's
/// grid-slicing importers expect. Anything else — a fixed column count, a
/// power-of-two sheet, a packed atlas with per-frame rects — is a
/// different product decision, so ``SpritesheetLayout/init(frameCount:cell:columns:)``
/// takes an explicit override rather than guessing.
///
/// Cells past the last frame in the final row exist and are fully
/// transparent. Trimming the sheet to a ragged edge would break the one
/// property a grid consumer relies on: `frame(i)` is at
/// `(i % columns, i / columns)`.
public struct SpritesheetLayout: Hashable, Sendable {
  public let columns: Int
  public let rows: Int
  /// One frame's size — the document canvas.
  public let cell: PixelSize
  /// The whole sheet's size, `columns x rows` cells.
  public let sheet: PixelSize

  public init(frameCount: Int, cell: PixelSize, columns: Int? = nil) {
    precondition(frameCount > 0, "a spritesheet needs at least one frame")
    let resolvedColumns = max(1, columns ?? Self.defaultColumns(forFrameCount: frameCount))
    let resolvedRows = (frameCount + resolvedColumns - 1) / resolvedColumns
    self.columns = resolvedColumns
    self.rows = resolvedRows
    self.cell = cell
    self.sheet = PixelSize(
      width: resolvedColumns * cell.width,
      height: resolvedRows * cell.height
    )
  }

  /// `ceil(sqrt(frameCount))` without touching `Double`. The loop runs
  /// `sqrt(n)` times, which for any plausible frame count is a handful of
  /// iterations.
  public static func defaultColumns(forFrameCount frameCount: Int) -> Int {
    var columns = 1
    while columns * columns < frameCount { columns += 1 }
    return columns
  }

  /// Top-left corner of a frame's cell, in sheet pixel coordinates.
  public func origin(ofFrame frameIndex: Int) -> PixelPoint {
    PixelPoint(
      x: (frameIndex % columns) * cell.width,
      y: (frameIndex / columns) * cell.height
    )
  }
}

/// The sidecar JSON a spritesheet ships with.
///
/// A bare PNG grid is not enough to animate from: a consumer needs the
/// cell size (it cannot be inferred — a 64x64 sheet is 2x2 32-pixel cells
/// or 4x4 16-pixel ones), the frame count (so it stops before the
/// transparent padding cells), and the per-frame delay (which is the
/// entire reason this document is an animation rather than a tileset).
/// Everything else here is derivable, and is written anyway because the
/// consumer of this file is usually a five-line import script, not a
/// library.
///
/// ```json
/// {
///   "cell":       { "width": 32, "height": 32 },
///   "columns":    3,
///   "format":     "gifeditor-spritesheet",
///   "frameCount": 5,
///   "frames": [
///     { "column": 0, "delayCentiseconds": 10, "delayMilliseconds": 100,
///       "height": 32, "index": 0, "row": 0, "width": 32, "x": 0, "y": 0 }
///   ],
///   "image":      { "width": 96, "height": 64 },
///   "loopCount":  0,
///   "rows":       2,
///   "version":    1
/// }
/// ```
///
/// `delayMilliseconds` is redundant with `delayCentiseconds` and is
/// written because every engine's animation API is in milliseconds or
/// seconds, and a x10 slip is exactly the bug that survives review.
/// `loopCount` follows the document's convention: zero means forever.
public struct SpritesheetMetadata: Hashable, Sendable, Codable {
  /// Identifies the schema for a reader that may be handed several
  /// vendors' sidecars.
  public static let formatIdentifier = "gifeditor-spritesheet"
  /// Bump when the *meaning* of a field changes, in the same spirit as
  /// ``ProjectFile/currentFormatVersion``.
  public static let currentVersion = 1

  public struct Frame: Hashable, Sendable, Codable {
    public let index: Int
    public let column: Int
    public let row: Int
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let delayCentiseconds: Int
    public let delayMilliseconds: Int
  }

  public let format: String
  public let version: Int
  public let image: PixelSize
  public let cell: PixelSize
  public let columns: Int
  public let rows: Int
  public let frameCount: Int
  public let loopCount: Int
  public let frames: [Frame]

  public init(document: GIFDocument, layout: SpritesheetLayout) {
    self.format = Self.formatIdentifier
    self.version = Self.currentVersion
    self.image = layout.sheet
    self.cell = layout.cell
    self.columns = layout.columns
    self.rows = layout.rows
    self.frameCount = document.frames.count
    self.loopCount = document.loopCount
    self.frames = document.frames.enumerated().map { index, frame in
      let origin = layout.origin(ofFrame: index)
      return Frame(
        index: index,
        column: index % layout.columns,
        row: index / layout.columns,
        x: origin.x,
        y: origin.y,
        width: layout.cell.width,
        height: layout.cell.height,
        delayCentiseconds: frame.delayCentiseconds,
        delayMilliseconds: frame.delayCentiseconds * 10
      )
    }
  }

  /// Serializes the sidecar.
  ///
  /// Sorted keys for the same reason ``ProjectFile/data(for:)`` sorts
  /// them — a re-export of unchanged content is byte-stable, so it diffs
  /// cleanly in whatever repo the sheet is committed to. Pretty-printed
  /// because unlike a project file this one is read by people.
  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}

/// A spritesheet and its sidecar, produced together so the two can never
/// describe different grids.
public struct Spritesheet: Sendable {
  public let png: [UInt8]
  public let layout: SpritesheetLayout
  public let metadata: SpritesheetMetadata
}

/// Lays a document's frames out on one PNG grid.
public enum SpritesheetExport {
  /// Composites every frame into a single sheet.
  ///
  /// `columns` overrides the near-square default described on
  /// ``SpritesheetLayout``.
  public static func encode(
    document: GIFDocument,
    columns: Int? = nil,
    flattenedColors: [[EditorColor?]]? = nil
  ) -> Spritesheet {
    let frames =
      flattenedColors
      ?? (0..<document.frames.count).map { document.flattenedColors(frameIndex: $0) }
    precondition(frames.count == document.frames.count, "one color plane per frame")

    let layout = SpritesheetLayout(
      frameCount: document.frames.count,
      cell: document.size,
      columns: columns
    )

    // The sheet starts fully transparent, so the padding cells in a
    // ragged last row need no special case — they are simply never
    // written to.
    var sheet = [UInt8](repeating: 0, count: layout.sheet.area * 4)
    let sheetStride = layout.sheet.width * 4
    let cellStride = layout.cell.width * 4

    for (frameIndex, colors) in frames.enumerated() {
      let cell = PNGRaster.rgbaBytes(colors: colors, size: layout.cell)
      let origin = layout.origin(ofFrame: frameIndex)
      for row in 0..<layout.cell.height {
        let source = row * cellStride
        let destination = (origin.y + row) * sheetStride + origin.x * 4
        sheet.replaceSubrange(
          destination..<(destination + cellStride),
          with: cell[source..<(source + cellStride)]
        )
      }
    }

    return Spritesheet(
      png: PNGEncoder.encode(rgba: sheet, size: layout.sheet),
      layout: layout,
      metadata: SpritesheetMetadata(document: document, layout: layout)
    )
  }

  /// Writes `<baseName>.png` and `<baseName>.json` into `directory`,
  /// creating it if it does not exist, and returns both URLs.
  ///
  /// A thin convenience over ``encode(document:columns:flattenedColors:)``,
  /// which stays the pure entry point: everything the format decides is
  /// decided there, and nothing here is more than filesystem plumbing.
  @discardableResult
  public static func write(
    _ sheet: Spritesheet,
    toDirectory directory: URL,
    baseName: String
  ) throws -> (png: URL, metadata: URL) {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let pngURL = directory.appendingPathComponent("\(baseName).png")
    let metadataURL = directory.appendingPathComponent("\(baseName).json")
    try Data(sheet.png).write(to: pngURL)
    try sheet.metadata.jsonData().write(to: metadataURL)
    return (pngURL, metadataURL)
  }
}
