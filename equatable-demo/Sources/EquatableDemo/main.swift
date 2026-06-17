// Demonstrates `View.equatable()` — SwiftTUI's opt-in for memoized-body reuse.
//
// When a `@State` change invalidates an ancestor, SwiftTUI re-evaluates the
// reached subtree. A boundary view that conforms to `Equatable` (here applied
// with `.equatable()`) is instead compared by its `==`: when it is unchanged,
// its whole rendered subtree is reused without re-evaluating it. Wrap stable,
// expensive subtrees whose body reads no `@State`/`@Observable`/focus state.
//
// `==` is a correctness contract: if it ignores a value the subtree depends on,
// the reused subtree will be stale.
//
// Run it: `swiftly run swift run --package-path equatable-demo equatable-demo`
// (press the `tick` button or the spacebar; the static panel below the counter
// is memoized across every tick).

import Foundation
import SwiftTUICLI

/// A large, static panel. Its only stored value is `title`, so the synthesized
/// `Equatable` `==` is exact, and its body reads no dynamic state — making it a
/// sound, profitable `.equatable()` boundary. SwiftTUI reuses this whole grid
/// across frames where `title` is unchanged instead of rebuilding all 48 cells.
struct DashboardPanel: View, Equatable {
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).bold()
      Divider()
      ForEach(Array(0..<8), id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Array(0..<6), id: \.self) { column in
            Text("r\(row)c\(column)").border(.separator)
          }
        }
      }
    }
  }
}

struct DemoRoot: View {
  @State private var ticks = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("EquatableView demo").bold()
      Text("ticks: \(ticks) — the panel below is reused on every tick")
      Button("tick") { ticks += 1 }

      // The opt-in: `.equatable()` tells SwiftTUI to compare `DashboardPanel`
      // by `==` and reuse its committed subtree when it is unchanged, rather
      // than re-evaluating it each time `ticks` invalidates this view.
      DashboardPanel(title: "Static Panel").equatable()
    }
    .padding(1)
  }
}

@main
struct EquatableDemoApp: App {
  init() {}

  var body: some Scene {
    WindowGroup("Equatable Demo", id: WindowIdentifier("main")) {
      DemoRoot()
    }
  }

  @MainActor
  static func main() async throws {
    let configuration = RuntimeConfiguration.detect(
      environment: ProcessInfo.processInfo.environment,
      isStdoutTTY: RenderOnce.standardOutputIsTTY()
    )
    try await TerminalRunner.run(Self.self, configuration: configuration)
  }
}
