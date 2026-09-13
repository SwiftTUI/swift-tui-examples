import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

@MainActor
struct FinitePlaybackTests {
  @Test(
    "STUI-374: preview plays the imported GIF's exact finite count and holds its last frame",
    arguments: [1, 2, 4])
  func finitePreview(plays: Int) throws {
    let size = GIFEditorCore.PixelSize(width: 1, height: 1)
    let frames = (1...2).map { index in
      EditorFrame(
        layers: [.init(name: "Frame", pixels: .init(size: size, fill: UInt8(index)))],
        delayCentiseconds: index * 3)
    }
    let document = GIFDocument(size: size, frames: frames, loopCount: plays)
    let bytes = Data(try GIFEncoder.encode(document: document))
    #expect(GIFLoader.declaredLoopCount(in: bytes) == (plays == 1 ? nil : plays - 1))
    let loaded = try GIFLoader.load(data: bytes)
    #expect(loaded.loopCount == plays)
    var maximum = document
    maximum.loopCount = EditingSession.maximumLoopCount
    let maximumBytes = Data(try GIFEncoder.encode(document: maximum))
    #expect(GIFLoader.declaredLoopCount(in: maximumBytes) == 65535)
    #expect(try GIFLoader.load(data: maximumBytes).loopCount == 65536)
    let model = EditingSession(document: loaded)
    model.startPlayback()
    var displayed = [model.currentFrameIndex]
    var delays: [Duration] = []
    for _ in 0..<(plays * 2) {
      delays.append(model.currentPlaybackDelay)
      if model.advancePlaybackFrame() { displayed.append(model.currentFrameIndex) }
    }
    #expect(displayed == Array(repeating: [0, 1], count: plays).flatMap { $0 })
    #expect(
      delays
        == Array(repeating: [Duration.milliseconds(30), .milliseconds(60)], count: plays).flatMap {
          $0
        })
    #expect(!model.isPlaybackActive)
    #expect(model.currentFrameIndex == 1)
    #expect(!model.advancePlaybackFrame())
    #expect(!model.isDirty)
    model.startPlayback()
    #expect(model.currentFrameIndex == 0)
    model.stopPlayback()
    #expect(!model.advancePlaybackFrame())
  }

  @Test("infinite previews keep wrapping; changing the count stops the active preview")
  func infinitePreview() {
    var document = GIFDocument.blank(size: .init(width: 1, height: 1))
    document.frames.append(EditorFrame(layers: document.frames[0].layers))
    let model = EditingSession(document: document)
    model.startPlayback()
    for _ in 0..<12 { #expect(model.advancePlaybackFrame()) }
    #expect(model.isPlaybackActive)
    model.setLoopCount(2)
    #expect(!model.isPlaybackActive)
  }
}
