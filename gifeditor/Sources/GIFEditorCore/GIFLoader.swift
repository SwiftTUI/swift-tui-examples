import EditorGIF
import Foundation

public enum GIFLoaderError: Error, Equatable {
  case unreadable(URL)
  case decode(String)
  case empty

  /// The logical screen is larger than a project file may declare
  /// (``ProjectFile/maximumCanvasDimension`` per axis,
  /// ``ProjectFile/maximumCanvasArea`` in all). Opening it would hand the
  /// editor a document its own Save and autosave could write but never
  /// read back.
  case canvasTooLarge(width: Int, height: Int, dimensionLimit: Int, areaLimit: Int)

  /// The frames times the canvas area exceed `pixelLimit`
  /// (`GIFLoader.maximumImportedPixelCount`): the composited animation is
  /// more than an import is allowed to hold in memory.
  case animationTooLarge(frameCount: Int, canvasArea: Int, pixelLimit: Int)
}

/// Reads GIF bytes off disk and adapts the vendored `swift-gif` decoder
/// into a `GIFDocument` the editor can edit.
///
/// The loader's job is to flatten the decoder's compositing semantics
/// (per-frame palettes, transparency, KEEP/BACKGROUND/PREVIOUS disposal)
/// into the editor's flatter "shared global palette + one editable
/// layer per imported frame" model. The original frames stay
/// pixel-faithful when the GIF uses ≤255 distinct opaque colors total;
/// beyond that ``Quantizer`` median-cuts the union of every composited
/// frame down to fit.
///
/// Two pieces of animation metadata survive that flattening: the per-frame
/// delay and the loop count, both of which the decoder hands over — see
/// ``declaredLoopCount(in:)`` for what "no loop count" means.
///
/// An import is bounded twice before anything is composited: the canvas
/// must fit the project format's limits, and the frames must fit a
/// composited-pixel budget (`checkCanvas(width:height:)`,
/// `maximumImportedPixelCount`). A GIF outside either is refused with a
/// ``GIFLoaderError``, which the open paths report as a malformed document.
public enum GIFLoader {

  public static func load(
    contentsOf url: URL,
    dithering: Quantizer.Dithering = .none
  ) throws -> GIFDocument {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw GIFLoaderError.unreadable(url)
    }
    return try load(data: data, dithering: dithering)
  }

  public static func load(
    data: Data,
    dithering: Quantizer.Dithering = .none
  ) throws -> GIFDocument {
    // The canvas is refused from the header, before the decoder or the
    // compositor sizes a single buffer by it: a 13-byte header can declare
    // a 65535 x 65535 screen, which is 17 GB per composited frame.
    if let screen = logicalScreenSize(of: data) {
      try checkCanvas(width: screen.width, height: screen.height)
    }

    var source = ByteSource(data: data)
    let image: GIF.Image
    do {
      image = try GIF.Image.decompress(stream: &source)
    } catch {
      throw GIFLoaderError.decode(String(describing: error))
    }
    if image.frames.isEmpty {
      throw GIFLoaderError.empty
    }

    let size = PixelSize(width: image.size.x, height: image.size.y)
    try checkPixelBudget(canvasArea: size.area, frameCount: image.frames.count)

    // Composite every frame first, honoring disposal modes — each frame
    // as the user "sees" it during playback becomes one editable frame.
    // The source disposal is consumed rather than carried: once a frame
    // has been flattened into what it looked like on screen, the disposal
    // that produced it has already been applied, and re-declaring it would
    // apply it twice. Every imported frame therefore arrives `.background`,
    // which is `EditorFrame`'s default and the one value that leaves
    // `GIFEncoder` free to delta-code the re-export. Authors can set
    // disposal per frame afterwards; the timeline says what that costs.
    //
    // Every frame is composited before a single palette decision is
    // made. That is deliberate on two counts: a full palette must never
    // stop us keeping frames (tying the two together used to truncate
    // any GIF rich enough to saturate the table), and the palette itself
    // has to see the whole animation. Choosing colors while scanning
    // meant the first frame's background could spend the entire table
    // before a later frame's content was ever considered.
    let compositedFrames: [[EditorColor?]] = (0..<image.frames.count).map { frameIndex in
      image.composited(frameIndex: frameIndex, as: GIF.RGBA<UInt8>.self).map { px in
        px.a == 0 ? nil : EditorColor(red: px.r, green: px.g, blue: px.b)
      }
    }

    let quantized = Quantizer.quantize(
      frames: compositedFrames,
      size: size,
      options: Quantizer.Options(dithering: dithering)
    )

    let editorFrames: [EditorFrame] = quantized.frames.enumerated().map { index, indices in
      let layer = EditorLayer(
        name: "Imported",
        pixels: PixelBuffer(size: size, pixels: indices)
      )
      let delay = max(1, image.frames[index].delayCentiseconds)
      return EditorFrame(layers: [layer], delayCentiseconds: delay)
    }

    return GIFDocument(
      size: size,
      palette: quantized.palette,
      frames: editorFrames,
      // `nil` is "the file declared nothing", which the format defines as
      // playing once. Defaulting it to the type's zero would say "forever"
      // about every finite animation the editor ever opens — and the
      // project format preserves what it is told, so that lie would be
      // saved and re-exported rather than just shown.
      loopCount: image.loopCount.map { $0 == 0 ? 0 : $0 + 1 } ?? playsOnce
    )
  }

  // MARK: - Import limits

  /// The most composited pixels — frames times canvas area — one import
  /// may produce: 2^26, four canvases at ``ProjectFile/maximumCanvasArea``.
  ///
  /// Every imported frame is composited at full canvas size and kept until
  /// the palette is chosen, at about seven bytes a pixel (an optional
  /// color, then an optional palette index), so this bounds an import's
  /// working set near half a gigabyte. A 256 x 256 animation may have 1024
  /// frames; a 640 x 480 one, 218.
  static let maximumImportedPixelCount = 1 << 26

  /// Refuses a canvas the project format could not store.
  ///
  /// The same limits ``PixelSize/init(from:)`` applies to a project file,
  /// applied at import so that every document the editor holds can be
  /// saved and autosaved in a form it can reopen. The per-axis limit is
  /// checked first, so the area is only multiplied out for two numbers no
  /// larger than 16384.
  static func checkCanvas(width: Int, height: Int) throws(GIFLoaderError) {
    guard
      width <= ProjectFile.maximumCanvasDimension,
      height <= ProjectFile.maximumCanvasDimension,
      width * height <= ProjectFile.maximumCanvasArea
    else {
      throw .canvasTooLarge(
        width: width,
        height: height,
        dimensionLimit: ProjectFile.maximumCanvasDimension,
        areaLimit: ProjectFile.maximumCanvasArea
      )
    }
  }

  /// Refuses an animation whose composited frames would exceed
  /// ``maximumImportedPixelCount``.
  static func checkPixelBudget(canvasArea: Int, frameCount: Int) throws(GIFLoaderError) {
    let total = canvasArea.multipliedReportingOverflow(by: frameCount)
    guard !total.overflow, total.partialValue <= maximumImportedPixelCount else {
      throw .animationTooLarge(
        frameCount: frameCount,
        canvasArea: canvasArea,
        pixelLimit: maximumImportedPixelCount
      )
    }
  }

  /// The logical screen size a GIF header declares, or `nil` when `data`
  /// does not start with a complete header and screen descriptor — the
  /// decoder reports those itself.
  ///
  /// The descriptor follows the six-byte signature: width, then height,
  /// each a little-endian 16-bit integer (GIF89a §18).
  static func logicalScreenSize(of data: Data) -> (width: Int, height: Int)? {
    guard ProjectFile.hasGIFSignature(data) else { return nil }
    let header = Array(data.prefix(10))
    guard header.count == 10 else { return nil }
    return (
      width: Int(header[6]) | Int(header[7]) << 8,
      height: Int(header[8]) | Int(header[9]) << 8
    )
  }

  // MARK: - Loop count

  /// The loop count a GIF carrying no `NETSCAPE2.0` application extension
  /// has: the format defines such an animation as playing through exactly
  /// once.
  ///
  /// Zero — here and in ``GIFDocument/loopCount`` — means forever, so the
  /// absent-block default is emphatically *not* the type's zero default.
  public static let playsOnce = 1

  /// The loop count declared by `data`'s `NETSCAPE2.0` application
  /// extension, or `nil` when the file carries none.
  ///
  /// This used to scan the raw bytes for the block's 14-byte anchor,
  /// because the vendored decoder discarded the extension before the
  /// loader ever saw it. It no longer does — `GIF.Image` carries the
  /// count — so the answer comes from a real walk of the file's block
  /// structure instead of from a needle in its bytes. A `NETSCAPE2.0`
  /// signature that happens to fall inside LZW data is no longer
  /// mistakable for a declaration.
  ///
  /// Bytes that are not a decodable GIF come back `nil` rather than
  /// throwing: "carries no such block" and "is not a GIF" are the same
  /// answer to the only question asked here, and every caller already
  /// holds a file it decoded (or failed to) by another route.
  public static func declaredLoopCount(in data: Data) -> Int? {
    var source = ByteSource(data: data)
    return (try? GIF.Image.decompress(stream: &source))?.loopCount
  }

  /// Adapter that drains a `Data` blob into the `GIF.BytestreamSource`
  /// the decoder expects. The decoder reads in 4 KiB chunks, so we just
  /// hand each call a bounded slice.
  private struct ByteSource: GIF.BytestreamSource {
    var bytes: [UInt8]
    var offset: Int

    init(data: Data) {
      self.bytes = Array(data)
      self.offset = 0
    }

    mutating func read(count: Int) -> [UInt8]? {
      guard offset < bytes.count else { return nil }
      let end = min(offset + count, bytes.count)
      let chunk = Array(bytes[offset..<end])
      offset = end
      return chunk
    }
  }
}
