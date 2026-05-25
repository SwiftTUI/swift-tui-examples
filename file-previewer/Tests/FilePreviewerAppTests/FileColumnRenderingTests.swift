@testable import FilePreviewerApp
import Foundation
import SwiftTUI
import Testing

@MainActor
struct FileColumnRenderingTests {
  @Test("large file columns realize viewport-scale row work")
  func largeFileColumnsRealizeViewportScaleRowWork() {
    let directory = URL(fileURLWithPath: "/tmp/large")
    let entries = (0..<1_000).map { index in
      FileEntry(
        url: directory.appendingPathComponent("file-\(index).swift"),
        isDirectory: false
      )
    }
    let renderer = DefaultRenderer()

    let artifacts = renderer.render(
      FileColumn(
        directory: directory,
        entries: entries,
        selection: entries[0].url,
        isActive: true
      ),
      context: .init(identity: Identity(components: ["Column"])),
      proposal: .init(width: 30, height: 8)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(rendered.contains("file-0.swift"))
    #expect(!rendered.contains("file-999.swift"))
    #expect(artifacts.diagnostics.counts.resolvedNodes < 80)
    #expect(artifacts.diagnostics.counts.measuredNodes < 80)
    #expect(artifacts.diagnostics.counts.placedNodes < 80)
  }
}
