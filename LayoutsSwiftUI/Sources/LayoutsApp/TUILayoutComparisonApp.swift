import Layouts
import SwiftTUIRuntime

struct TUILayoutComparisonApp: App {
  private let entryID: String

  nonisolated init() {
    entryID = LayoutCatalog.all.first?.id ?? ""
  }

  nonisolated init(entryID: String) {
    self.entryID = entryID
  }

  var body: some Scene {
    WindowGroup("SwiftTUI", id: "comparison") {
      if let entry = LayoutCatalog.entry(id: entryID) {
        TUILayoutComparisonRoot(entry: entry)
      } else {
        Text("Missing layout: \(entryID)")
          .padding(1)
      }
    }
    .exitOnKeys([])
  }
}

private struct TUILayoutComparisonRoot: View {
  let entry: LayoutEntry

  var body: some View {
    entry.makeView()
//      .panel(id: "layouts.embedded.\(entry.id)")
  }
}
