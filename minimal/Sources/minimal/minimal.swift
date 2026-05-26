// One-shot rendering reference. This example deliberately does NOT use the
// scene runtime, App protocol, TerminalRunner, or SwiftTUICommand. It uses the
// public RenderOnce helper so readers can copy the canonical path for printing
// one SwiftTUI view tree and exiting.

import SwiftTUICLI

struct BuildSummary: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Deploy Queue")
        .bold()
      Divider()
      ProgressView("Release", value: 18, total: 24)
      LabeledContent("Window", value: "staging")
      LabeledContent("Owner", value: "infra")
    }
    .padding(.init(horizontal: 1, vertical: 0))
  }
}

await MainActor.run {
  RenderOnce.print(BuildSummary(), width: 40)
}
