import Foundation
import GIFEditorCore
import SwiftTUI

struct SaveGIFPreview: Equatable, Sendable {
  var frames: [Frame]
  var encodedByteCount: Int?
  var errorMessage: String?

  var canSave: Bool {
    errorMessage == nil
  }

  static func make(from document: GIFDocument) -> SaveGIFPreview {
    do {
      let bytes = try GIFEncoder.encode(document: document)
      let decoded = try GIFLoader.load(data: Data(bytes))
      let frames = decoded.frames.indices.map { index in
        Frame(
          size: decoded.size,
          pixels: decoded.flattenedColors(frameIndex: index),
          delayCentiseconds: decoded.frames[index].delayCentiseconds
        )
      }
      return SaveGIFPreview(
        frames: frames,
        encodedByteCount: bytes.count,
        errorMessage: nil
      )
    } catch {
      return SaveGIFPreview(
        frames: [],
        encodedByteCount: nil,
        errorMessage: String(describing: error)
      )
    }
  }

  struct Frame: Equatable, Sendable {
    var size: GIFEditorCore.PixelSize
    var pixels: [EditorColor?]
    var delayCentiseconds: Int

    var delay: Duration {
      .milliseconds(max(1, delayCentiseconds) * 10)
    }
  }
}

struct SaveGIFSheetView: View {
  let preview: SaveGIFPreview
  @Binding var pathText: String
  @Binding var overwriteConfirmed: Bool
  let onSave: @MainActor @Sendable (URL, Bool) -> Void
  let onCancel: @MainActor @Sendable () -> Void

  @State private var previewFrameIndex = 0
  @FocusState private var pathFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Review GIF before saving").foregroundStyle(.tint)
      pathField
      Divider()
      previewArea
      Divider()
      targetStatus
      if requiresOverwriteConfirmation {
        overwriteConfirmation
      }
      HStack(spacing: 1) {
        Spacer(minLength: 1)
        Button("Cancel", action: onCancel)
          .systemHint("Esc")
        Button("Save") {
          guard let targetURL, canSave else { return }
          onSave(targetURL, requiresOverwriteConfirmation)
        }
        .disabled(!canSave)
      }
    }
    .padding(1)
    .onChange(of: pathText) {
      overwriteConfirmed = false
    }
    .task(id: preview) { @MainActor in
      await runPreview()
    }
  }

  private var pathField: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Destination").foregroundStyle(.muted)
      TextField("Path", text: $pathText)
        .focused($pathFocused)
        .onAppear {
          pathFocused = true
        }
        .textFieldStyle(.plain)
        .frame(width: 58, alignment: .leading)
    }
  }

  @ViewBuilder
  private var previewArea: some View {
    if let errorMessage = preview.errorMessage {
      Text("Preview failed: \(errorMessage)")
        .foregroundStyle(.warning)
    } else if let frame = currentFrame {
      VStack(alignment: .leading, spacing: 1) {
        Text("Encoded preview")
          .foregroundStyle(.muted)
        Canvas.pixelGrid(
          width: displaySize(for: frame).width,
          height: displaySize(for: frame).height,
          pixels: displayPixels(for: frame),
          mode: .verticalHalfBlock
        )
        .border(.separator, set: .single)
        Text(previewSummary)
          .foregroundStyle(.muted)
      }
    } else {
      Text("No frames to preview").foregroundStyle(.warning)
    }
  }

  @ViewBuilder
  private var targetStatus: some View {
    if targetURL == nil {
      Text("Enter a destination path").foregroundStyle(.warning)
    } else if requiresOverwriteConfirmation {
      Text("A file already exists at this path. Confirm overwrite to enable Save.")
        .foregroundStyle(.warning)
    } else {
      Text("Ready to save").foregroundStyle(.success)
    }
  }

  private var overwriteConfirmation: some View {
    Button {
      overwriteConfirmed.toggle()
    } label: {
      HStack(spacing: 1) {
        Text(overwriteConfirmed ? "[✓]" : "[ ]")
          .foregroundStyle(overwriteConfirmed ? .tint : .muted)
        Text("Confirm overwrite").foregroundStyle(.foreground)
      }
    }
    .buttonStyle(.plain)
  }

  private var currentFrame: SaveGIFPreview.Frame? {
    guard !preview.frames.isEmpty else { return nil }
    return preview.frames[min(previewFrameIndex, preview.frames.count - 1)]
  }

  private var targetURL: URL? {
    EditorViewModel.saveURL(from: pathText)
  }

  private var targetExists: Bool {
    guard let targetURL else { return false }
    return FileManager.default.fileExists(atPath: targetURL.path)
  }

  private var requiresOverwriteConfirmation: Bool {
    targetExists
  }

  private var canSave: Bool {
    targetURL != nil && preview.canSave && (!requiresOverwriteConfirmation || overwriteConfirmed)
  }

  private var previewSummary: String {
    let byteCount = preview.encodedByteCount.map { "\($0) bytes" } ?? "unknown size"
    guard let currentFrame else {
      return "\(preview.frames.count) frames • \(byteCount)"
    }
    return "Frame \(previewFrameIndex + 1)/\(preview.frames.count) • "
      + "\(currentFrame.delayCentiseconds) cs • \(byteCount)"
  }

  @MainActor
  private func runPreview() async {
    previewFrameIndex = 0
    while preview.frames.count > 1 && !Task.isCancelled {
      let frame = preview.frames[min(previewFrameIndex, preview.frames.count - 1)]
      try? await Task.sleep(for: frame.delay)
      guard !Task.isCancelled else { return }
      previewFrameIndex = (previewFrameIndex + 1) % preview.frames.count
    }
  }

  private func displaySize(for frame: SaveGIFPreview.Frame) -> GIFEditorCore.PixelSize {
    GIFEditorCore.PixelSize(
      width: min(frame.size.width, 32),
      height: min(frame.size.height, 32)
    )
  }

  private func displayPixels(for frame: SaveGIFPreview.Frame) -> [Color?] {
    let size = displaySize(for: frame)
    var output: [Color?] = []
    output.reserveCapacity(size.area)

    for y in 0..<size.height {
      for x in 0..<size.width {
        let sx = (x * frame.size.width) / size.width
        let sy = (y * frame.size.height) / size.height
        let sourceIndex = sy * frame.size.width + sx
        if frame.pixels.indices.contains(sourceIndex), let color = frame.pixels[sourceIndex] {
          output.append(color.toTerminalColor())
        } else {
          let shade = ((x + y) & 1) == 0 ? 0.18 : 0.10
          output.append(Color(red: shade, green: shade, blue: shade, alpha: 1.0))
        }
      }
    }

    return output
  }
}
