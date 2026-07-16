import SwiftTUIRuntime

struct NavigationCollectionsTab: View {
  @State private var selectedDoc = "overview"
  @State private var selectedTableRow = "queued"
  @State private var showingDetail = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 1) {
          header
          Divider()
          HStack(alignment: .top, spacing: 2) {
            listSection
            outlineSection
          }
          Divider()
          lazyStacksSection
          Divider()
          tableSection
          Button("Open selected detail") {
            showingDetail = true
          }
          Spacer(minLength: 0)
        }
        .padding(1)
        .navigationDestination(isPresented: $showingDetail) {
          detailView
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Navigation & Collections").foregroundStyle(.foreground)
      Text(
        "NavigationStack, navigationDestination, OutlineGroup, lazy stacks, list selection, and table selection."
      )
      .foregroundStyle(.separator)
    }
  }

  private var listSection: some View {
    GroupBox("List selection") {
      List(selection: $selectedDoc) {
        Text("Overview").tag("overview")
        Text("Build lanes").tag("build-lanes")
        Text("Focused tests").tag("focused-tests")
      }
      .frame(width: 24, height: 5)
    }
  }

  private var outlineSection: some View {
    GroupBox("OutlineGroup") {
      OutlineGroup(Self.outlineNodes, children: \.children) { node in
        Text(node.title)
      }
      .outlineStyle(RoundedOutlineStyle())
      .frame(width: 34, height: 8, alignment: .topLeading)
    }
  }

  private var lazyStacksSection: some View {
    GroupBox("Lazy stacks") {
      VStack(alignment: .leading, spacing: 1) {
        LazyHStack(spacing: 1) {
          ForEach(0..<8, id: \.self) { index in
            Text("H\(index)")
              .padding(.horizontal, 1)
              .border(set: .single)
          }
        }
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<4, id: \.self) { index in
            Text("Lazy row \(index)")
          }
        }
      }
    }
  }

  private var tableSection: some View {
    GroupBox("Table selection") {
      Table(
        selection: $selectedTableRow,
        columns: [
          TableColumn("State", width: 14),
          TableColumn("Count", width: 6, alignment: .trailing),
          TableColumn("Owner", width: 16),
        ]
      ) {
        TableRow {
          Text("Queued")
          Text("3")
          Text("Examples")
        }
        .tag("queued")
        TableRow {
          Text("In review")
          Text("1")
          Text("Docs")
        }
        .tag("review")
        TableRow {
          Text("Done")
          Text("8")
          Text("Runtime")
        }
        .tag("done")
      }
      .frame(height: 6)
    }
  }

  private var detailView: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Selected detail").bold()
      Text("List row: \(selectedDoc)")
      Text("Table row: \(selectedTableRow)")
      Button("Done") {
        showingDetail = false
      }
    }
    .padding(2)
  }

  private static let outlineNodes: [OutlineNode] = [
    .init(
      title: "Examples",
      children: [
        .init(title: "Terminal"),
        .init(title: "SwiftUI host"),
        .init(title: "Web/WASI"),
      ]
    ),
    .init(
      title: "Coverage",
      children: [
        .init(title: "Build lanes"),
        .init(title: "Focused tests"),
      ]
    ),
  ]
}

private struct OutlineNode: Identifiable, Sendable {
  let id: String
  let title: String
  let children: [OutlineNode]?

  init(title: String, children: [OutlineNode]? = nil) {
    id = title
    self.title = title
    self.children = children
  }
}
