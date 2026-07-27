import Foundation
import Testing

@testable import Sextant

@Suite("Column browser presentation")
struct ColumnBrowserPresentationTests {
  @Test("built-in previews expose metadata and truncation")
  func previewIndicators() {
    let metadata = PreviewMetadata(
      displayName: "large.txt",
      path: "/fixture/large.txt",
      kind: "File",
      size: 300_000
    )
    #expect(
      BuiltInPreviewPresentation.metadataLine(metadata)
        == "File · 300000 bytes"
    )
    #expect(
      BuiltInPreviewPresentation.indicator(
        .text(
          TextPreview(
            text: "prefix",
            encoding: .utf8,
            isTruncated: true
          )
        )
      ) == "UTF-8 · truncated to 256 KiB"
    )
    #expect(
      BuiltInPreviewPresentation.indicator(
        .hexadecimal(
          HexPreview(
            formatted: "00",
            renderedByteCount: 4_096,
            isTruncated: true
          )
        )
      ) == "4096 bytes shown · truncated"
    )
  }

  @Test("every non-terminal preview owns an Escape-capable host focus target")
  func nonTerminalFocusTargets() {
    let directory = URL(fileURLWithPath: "/fixture")
    let directoryID = DirectoryID(identity: .path(directory.path))
    let itemURL = directory.appendingPathComponent("file.txt")
    let identity = FileSystemIdentity.path(itemURL.path)
    let item = BrowserItem(
      id: BrowserItemID(identity: identity),
      directoryID: directoryID,
      name: "file.txt",
      url: itemURL,
      kind: .file,
      listingMetadata: ItemMetadata(identity: identity, isReadable: true)
    )
    let generation = PreviewGeneration(rawValue: 1)
    let preview = BuiltInPreview(
      metadata: PreviewMetadata(
        displayName: item.name,
        path: item.url.path,
        kind: "File"
      ),
      body: .metadataOnly
    )

    #expect(
      PreviewFocusPolicy.usesHostFocusTarget(
        .loading(item: item, generation: generation)
      )
    )
    #expect(
      PreviewFocusPolicy.usesHostFocusTarget(
        .builtIn(item: item, generation: generation, preview: preview)
      )
    )
    #expect(
      PreviewFocusPolicy.usesHostFocusTarget(
        .unavailable(
          item: item,
          generation: generation,
          reason: .previewDisabled
        )
      )
    )
    #expect(
      PreviewFocusPolicy.usesHostFocusTarget(
        .failed(
          item: item,
          generation: generation,
          adapter: nil,
          failure: .missing,
          fallback: nil
        )
      )
    )
    #expect(!PreviewFocusPolicy.usesHostFocusTarget(.welcome))
  }

  @Test("loading-to-terminal handoff preserves semantic preview focus")
  func externalPreviewFocusHandoff() {
    let directoryID = DirectoryID(identity: .path("/fixture"))

    #expect(
      PreviewFocusHandoffPolicy.shouldPreserveSemanticFocus(
        from: .host,
        to: .terminal,
        semanticFocus: .preview
      )
    )
    #expect(
      !PreviewFocusHandoffPolicy.shouldPreserveSemanticFocus(
        from: .host,
        to: .terminal,
        semanticFocus: .browser(directoryID)
      )
    )
    #expect(
      !PreviewFocusHandoffPolicy.shouldPreserveSemanticFocus(
        from: .terminal,
        to: .host,
        semanticFocus: .preview
      )
    )
  }

  @Test("external preview failures have actionable labels")
  func externalPreviewFailureLabels() {
    #expect(
      PreviewFailurePresentation.label(
        .missingExecutable("fixture-tool")
      ) == "External preview executable not found: fixture-tool"
    )
    #expect(
      PreviewFailurePresentation.label(.externalExit(7))
        == "External preview exited with status 7."
    )
    #expect(
      PreviewFailurePresentation.label(.externalSignal(9))
        == "External preview terminated by signal 9."
    )
  }
}
