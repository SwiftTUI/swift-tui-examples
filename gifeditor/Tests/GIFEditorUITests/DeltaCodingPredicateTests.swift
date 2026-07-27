import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

/// The "authored disposal other than `.background` disables delta coding"
/// rule, checked against the encoder that enforces it.
///
/// The rule used to be written twice — once in `GIFEncoder`, which acts
/// on it, and once in `EditorViewModel`, which warns about it — and two
/// spellings of a predicate that decides file size are two spellings that
/// can drift. They are now one `GIFEncoder.supportsDeltaCoding(_:)`.
///
/// Restating that call in a test would only prove the compiler works, so
/// the check that matters is the last one: the predicate is compared to
/// what the encoder actually *emits*. A delta-coded document must produce
/// different bytes from the full-frame coding of the same document, and a
/// declined one must produce identical bytes — which is the observable
/// meaning of "the export fell back".
@MainActor
@Suite("GIF editor delta-coding predicate")
struct DeltaCodingPredicateTests {

  /// Every disposal, and the two frame counts that matter, as documents.
  private static func subjects() -> [(name: String, document: GIFDocument)] {
    let size = PixelSize(width: 8, height: 8)
    func frame(_ fill: PaletteIndex, _ disposal: EditorFrame.FrameDisposal) -> EditorFrame {
      EditorFrame(
        layers: [EditorLayer(name: "L", pixels: PixelBuffer(size: size, fill: fill))],
        delayCentiseconds: 10,
        disposal: disposal
      )
    }

    var subjects: [(String, GIFDocument)] = [
      ("single frame, background", GIFDocument(size: size, frames: [frame(1, .background)]))
    ]
    for disposal in EditorViewModel.disposalOrder {
      subjects.append(
        (
          "two frames, both \(EditorViewModel.disposalLabel(disposal))",
          GIFDocument(size: size, frames: [frame(1, disposal), frame(2, disposal)])
        )
      )
      guard disposal != .background else { continue }
      // One authored frame in an otherwise default document — the case
      // the warning exists for, and the one a per-frame rule would get
      // wrong by half-honouring it.
      subjects.append(
        (
          "two frames, second \(EditorViewModel.disposalLabel(disposal))",
          GIFDocument(size: size, frames: [frame(1, .background), frame(2, disposal)])
        )
      )
    }
    return subjects
  }

  @Test("the view model reports whatever the encoder decides")
  func viewModelAgreesWithTheEncoder() {
    for (name, document) in Self.subjects() {
      let model = EditorViewModel(document: document)
      #expect(
        model.exportUsesDeltaFrames == GIFEncoder.supportsDeltaCoding(document),
        "\(name): the view model and the encoder disagree"
      )
      // The warning is the narrower question: an authored disposal, not
      // merely a document with nothing to delta against.
      #expect(
        model.authoredDisposalDisablesDeltaCoding
          == (document.frames.count > 1 && !GIFEncoder.supportsDeltaCoding(document)),
        "\(name): the warning fired on the wrong document"
      )
    }
  }

  /// The assertion that cannot drift: the predicate against the bytes.
  @Test("the predicate matches what the encoder actually emits")
  func predicateMatchesTheEmittedBytes() throws {
    for (name, document) in Self.subjects() {
      let delta = try GIFEncoder.encode(document: document, frameCoding: .deltaFrames)
      let full = try GIFEncoder.encode(document: document, frameCoding: .fullFrames)
      if GIFEncoder.supportsDeltaCoding(document) {
        #expect(delta != full, "\(name): claimed delta coding but wrote the full-frame bytes")
      } else {
        #expect(delta == full, "\(name): declined delta coding but wrote something else")
      }
    }
  }

  /// A single frame flipped to `.keep` costs the *whole* document its
  /// delta coding. That is the surprise the warning exists to prevent, so
  /// it is stated as its own case rather than left inside a sweep.
  @Test("one authored frame declines the whole document")
  func oneAuthoredFrameDeclinesTheDocument() {
    let size = PixelSize(width: 4, height: 4)
    var document = GIFDocument(
      size: size,
      frames: (0..<4).map { index in
        EditorFrame(
          layers: [
            EditorLayer(
              name: "L\(index)", pixels: PixelBuffer(size: size, fill: PaletteIndex(index + 1)))
          ],
          disposal: .background
        )
      }
    )
    let model = EditorViewModel(document: document)
    #expect(model.exportUsesDeltaFrames)

    document.frames[2].disposal = .keep
    let authored = EditorViewModel(document: document)
    #expect(!authored.exportUsesDeltaFrames)
    #expect(authored.authoredDisposalDisablesDeltaCoding)
    #expect(!GIFEncoder.supportsDeltaCoding(document))
  }
}
