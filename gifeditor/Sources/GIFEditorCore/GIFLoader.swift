import EditorGIF
import Foundation

public enum GIFLoaderError: Error, Equatable {
  case unreadable(URL)
  case decode(String)
  case empty
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
      loopCount: image.loopCount ?? playsOnce
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
