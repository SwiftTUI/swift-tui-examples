import Foundation
import Testing

@testable import MrkdwnMermaid

@Suite
struct FamilyMatrixTests {
  private let families = ["flowchart", "state", "sequence", "class", "er", "xy"]

  @Test
  func everyFamilyFreezesAdvancedMalformedUnsupportedWideCyclicAndUnicodeReports() throws {
    for family in families {
      let cases = try matrixCases(family: family)
      #expect(
        cases.map(\.name) == ["advanced", "malformed", "unsupported", "wide", "cyclic", "unicode"]
      )
      for testCase in cases {
        for ambiguousWidth in MermaidAmbiguousWidth.allCases {
          for glyphMode in MermaidGlyphMode.allCases {
            let renderer = MermaidRenderer(
              configuration: .init(
                glyphMode: glyphMode,
                ambiguousWidth: ambiguousWidth
              )
            )
            let report = renderer.renderSurface(testCase.source, forWidth: 72)
            let actualReport =
              report.fidelity.rawValue + " "
              + (report.diagnostics.map(\.code.rawValue).joined(separator: ",").nilIfEmpty ?? "-")

            #expect(
              actualReport == testCase.expectedReport,
              "Unexpected \(family)/\(testCase.name) report under \(glyphMode.rawValue)/\(ambiguousWidth.rawValue)"
            )
            #expect((report.output == nil) == (report.fidelity == .unavailable))
            if let surface = report.output {
              #expect(surface.size.width <= 72)
              #expect(renderer.measure(testCase.source, forWidth: 72).output == surface.size)
              #expect(
                !report.diagnostics.contains { $0.code == .layoutFailure },
                "Valid matrix case reached layout failure"
              )
              assertFrozenSemantics(
                family: family,
                testCase: testCase,
                surface: surface,
                glyphMode: glyphMode
              )
            }

            let metrics = renderer.layoutMetrics(for: testCase.source)
            let actualMetricsReport =
              metrics.fidelity.rawValue + " "
              + (metrics.diagnostics.map(\.code.rawValue).joined(separator: ",").nilIfEmpty ?? "-")
            #expect(actualMetricsReport == testCase.expectedReport)
            if let metric = metrics.output {
              for width in Set([metric.minimumWidth, metric.idealSize.width]) {
                let constrained = renderer.renderSurface(testCase.source, forWidth: width)
                let constrainedReport =
                  constrained.fidelity.rawValue + " "
                  + (constrained.diagnostics.map(\.code.rawValue).joined(separator: ",").nilIfEmpty
                    ?? "-")
                #expect(constrainedReport == testCase.expectedReport)
                #expect(constrained.output?.size.width ?? width + 1 <= width)
                #expect(
                  renderer.measure(testCase.source, forWidth: width).output
                    == constrained.output?.size)
              }
            }
          }
        }
      }
    }
  }

  private func assertFrozenSemantics(
    family: String,
    testCase: FamilyMatrixCase,
    surface: MermaidSurface,
    glyphMode: MermaidGlyphMode
  ) {
    let text = surface.serialized(as: glyphMode)
    let roles = Set(surface.rows.flatMap { $0 }.map(\.role))
    #expect(roles.contains(.title))
    #expect(roles.contains(.text))
    #expect(roles.contains(.border))

    let fragments: [String]
    switch (family, testCase.name) {
    case ("flowchart", "advanced"):
      fragments = ["Start", "Finish", "[-->] B", "subgraph Multi Word Label"]
    case ("flowchart", "unsupported"):
      fragments = ["A", "[-->] B"]
      #expect(!text.contains("fill:red"))
    case ("flowchart", "wide"):
      fragments = ["解析", "👩🏽‍💻", "é", "完了"]
    case ("flowchart", "cyclic"):
      fragments = ["A", "B", "C"]
      #expect(text.components(separatedBy: "[-->]").count - 1 == 3)
    case ("flowchart", "unicode"):
      fragments = ["logical שלום", "done"]
    case ("state", "advanced"):
      fragments = ["Ready now", "Choice", "[-->] Ready", "choose"]
    case ("state", "unsupported"):
      fragments = ["A", "B"]
      #expect(!text.contains("note right"))
    case ("state", "wide"):
      fragments = ["解析👩🏽‍💻", "完了"]
    case ("state", "cyclic"):
      fragments = ["A", "B", "C"]
      #expect(text.components(separatedBy: "[-->]").count - 1 == 3)
    case ("state", "unicode"):
      fragments = ["שלום", "B"]
    case ("sequence", "advanced"):
      fragments = ["Client", "Service", "request", "response", "loop: retry"]
    case ("sequence", "unsupported"):
      fragments = ["A", "B", "request"]
      #expect(!text.contains("activate"))
    case ("sequence", "wide"):
      fragments = ["解析👩🏽‍💻", "完了", "é"]
    case ("sequence", "cyclic"):
      fragments = ["A", "B", "request", "response"]
    case ("sequence", "unicode"):
      fragments = ["שלום", "B", "logical"]
    case ("class", "advanced"):
      fragments = ["Service", "Worker", "String name", "run()", "interface", "[<|--] Worker"]
    case ("class", "unsupported"):
      fragments = ["A", "B", "[-->] B"]
      #expect(!text.contains("fill:red"))
    case ("class", "wide"):
      fragments = ["解析👩🏽‍💻", "完了"]
    case ("class", "cyclic"):
      fragments = ["A", "B", "C"]
      #expect(text.components(separatedBy: "[-->]").count - 1 == 3)
    case ("class", "unicode"):
      fragments = ["שלום", "Done"]
    case ("er", "advanced"):
      fragments = ["CUSTOMER", "ORDER", "string name", "int number", "[||--o{] ORDER", "places"]
    case ("er", "unsupported"):
      fragments = ["A", "B", "[||--o{] B", "owns"]
      #expect(!text.contains("unsupported final"))
    case ("er", "wide"):
      fragments = ["解析👩🏽‍💻", "完了", "owns"]
    case ("er", "cyclic"):
      fragments = ["A", "B", "C"]
      #expect(text.components(separatedBy: "[||--o{]").count - 1 == 3)
    case ("er", "unicode"):
      fragments = ["שלום", "DONE", "owns"]
    case ("xy", "advanced"):
      fragments = ["Requests", "Mon", "Tue", "Wed", "bar 1", "line 2", "8, 16, 12", "6, 10, 18"]
    case ("xy", "unsupported"):
      fragments = ["line 1", "1, 2, 3"]
      #expect(!text.contains("unknown authored"))
    case ("xy", "wide"):
      fragments = ["解析", "👩🏽‍💻", "é", "1, 2, 3"]
    case ("xy", "cyclic"):
      fragments = ["A", "B", "C", "D", "line 1", "bar 2"]
    case ("xy", "unicode"):
      fragments = ["שלום", "done", "1, 2"]
    default:
      fragments = []
    }
    for fragment in fragments {
      #expect(
        text.contains(fragment),
        "Missing frozen \(family)/\(testCase.name) fragment: \(fragment)"
      )
    }
    if testCase.name != "malformed" {
      #expect(roles.contains(.edge) || family == "class")
    }
  }

  private func matrixCases(family: String) throws -> [FamilyMatrixCase] {
    let text = try fixture("\(family)/matrix.txt")
    var result: [FamilyMatrixCase] = []
    var currentName: String?
    var currentReport: String?
    var sourceLines: [Substring] = []

    func appendCurrent() {
      guard let name = currentName, let report = currentReport else { return }
      result.append(
        FamilyMatrixCase(
          name: name,
          expectedReport: report,
          source: sourceLines.joined(separator: "\n")
        )
      )
    }

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix("@@ ") {
        appendCurrent()
        let fields = line.dropFirst(3).split(separator: " ", maxSplits: 2).map(String.init)
        currentName = fields.first
        currentReport = fields.dropFirst().joined(separator: " ")
        sourceLines = []
      } else {
        sourceLines.append(line)
      }
    }
    appendCurrent()
    return result
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

private struct FamilyMatrixCase {
  var name: String
  var expectedReport: String
  var source: String
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
