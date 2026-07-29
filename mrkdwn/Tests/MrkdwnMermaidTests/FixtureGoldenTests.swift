import Foundation
import Testing

@testable import MrkdwnMermaid

@Suite
struct FixtureGoldenTests {
  private let families = ["flowchart", "state", "sequence", "class", "er", "xy"]
  private let renderWidth = 48

  @Test
  func minimalFamilyFixturesMatchFrozenReportsRolesAndSurfaces() throws {
    for family in families {
      let source = try fixture("\(family)/minimal.mmd")
      let unicodeRenderer = MermaidRenderer()
      let asciiRenderer = MermaidRenderer(configuration: .init(glyphMode: .ascii))
      let unicode = unicodeRenderer.renderSurface(source, forWidth: renderWidth)
      let ascii = asciiRenderer.renderSurface(source, forWidth: renderWidth)
      let metrics = unicodeRenderer.layoutMetrics(for: source)
      let unicodeSurface = try #require(unicode.output)
      let asciiSurface = try #require(ascii.output)

      #expect(unicode.fidelity == .complete)
      #expect(ascii.fidelity == .complete)
      #expect(unicodeRenderer.measure(source, forWidth: renderWidth).output == unicodeSurface.size)
      #expect(asciiRenderer.measure(source, forWidth: renderWidth).output == asciiSurface.size)

      let actual = FixtureGolden(
        unicode: unicodeSurface.serialized() + "\n",
        ascii: asciiSurface.serialized(as: .ascii) + "\n",
        metadata: metadata(metrics: metrics, report: unicode, surface: unicodeSurface)
      )
      if ProcessInfo.processInfo.environment["SWIFT_MERMAID_RECORD_GOLDENS"] == "1" {
        try record(actual, family: family)
        continue
      }

      let expectedUnicode = try fixture("\(family)/minimal.unicode.txt")
      let expectedASCII = try fixture("\(family)/minimal.ascii.txt")
      let expectedMetadata = try fixture("\(family)/minimal.metadata.txt")
      #expect(actual.unicode == expectedUnicode)
      #expect(actual.ascii == expectedASCII)
      #expect(actual.metadata == expectedMetadata)
    }
  }

  private func metadata(
    metrics: MermaidReport<MermaidLayoutMetrics>,
    report: MermaidReport<MermaidSurface>,
    surface: MermaidSurface
  ) -> String {
    var roleCounts: [String: Int] = [:]
    for cell in surface.rows.flatMap({ $0 }) {
      roleCounts[cell.role.rawValue, default: 0] += 1
    }
    let roles = roleCounts.keys.sorted().map { "\($0)=\(roleCounts[$0] ?? 0)" }
      .joined(separator: ",")
    let diagnosticCodes = report.diagnostics.map(\.code.rawValue).joined(separator: ",")
    return
      """
      fidelity=\(report.fidelity.rawValue)
      diagnostics=\(diagnosticCodes)
      minimumWidth=\(metrics.output?.minimumWidth ?? -1)
      idealSize=\(metrics.output?.idealSize.width ?? -1)x\(metrics.output?.idealSize.height ?? -1)
      renderWidth=\(renderWidth)
      renderSize=\(surface.size.width)x\(surface.size.height)
      roles=\(roles)

      """
  }

  private func record(_ golden: FixtureGolden, family: String) throws {
    let sourceDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures")
      .appendingPathComponent(family)
    try golden.unicode.write(
      to: sourceDirectory.appendingPathComponent("minimal.unicode.txt"),
      atomically: true,
      encoding: .utf8
    )
    try golden.ascii.write(
      to: sourceDirectory.appendingPathComponent("minimal.ascii.txt"),
      atomically: true,
      encoding: .utf8
    )
    try golden.metadata.write(
      to: sourceDirectory.appendingPathComponent("minimal.metadata.txt"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func fixture(_ path: String) throws -> String {
    let components = path.split(separator: "/")
    let filename = String(try #require(components.last))
    let subdirectory = "Fixtures/" + components.dropLast().joined(separator: "/")
    let stem = filename.split(separator: ".", maxSplits: 1).first.map(String.init) ?? filename
    let extensionName = filename.dropFirst(stem.count + 1)
    let url = try #require(
      Bundle.module.url(
        forResource: stem,
        withExtension: String(extensionName),
        subdirectory: subdirectory
      )
    )
    return try String(contentsOf: url, encoding: .utf8)
  }
}

private struct FixtureGolden {
  var unicode: String
  var ascii: String
  var metadata: String
}
