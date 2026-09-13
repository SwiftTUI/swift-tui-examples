import SwiftTUI

/// A transient command sink deliberately has no Codable conformance. Replacement
/// generations construct a new sink; active tab lifecycle work installs handlers.
@MainActor final class ReloadCommands {
  var increment: (() -> Void)?
}

struct FidelityRoot: View {
  @State private var selection = 0
  @State private var offset = ScrollCellOffset.zero
  @State private var commands = ReloadCommands()
  @FocusState private var focus: Int?

  var body: some View {
    VStack {
      Text("FOCUS=\(focus ?? 0) SCROLL=\(offset.y) TAB=\(selection)")
      Button("First focus") {}.focused($focus, equals: 1)
      Button("Second focus") {}.focused($focus, equals: 2)
      ScrollView(.vertical, position: $offset) {
        VStack { ForEach(0..<30) { Text("ROW-\($0)") } }
      }.frame(height: 4)
      TabView(selection: $selection) {
        Tab("A", value: 0) { FidelityCounter(label: "A", commands: commands) }
        Tab("B", value: 1) { FidelityCounter(label: "B", commands: commands) }
      }.frame(height: 5)
      Text("a/b: select tab; x: increment tab; f: second focus; j: scroll")
    }
    .onKeyPress { key in
      switch key.key {
      case .character("a"): selection = 0
      case .character("b"): selection = 1
      case .character("x"): commands.increment?()
      case .character("f"): focus = 2
      case .character("j"): offset.y = 6
      default: return .ignored
      }
      return .handled
    }
  }
}

struct FidelityCounter: View {
  let label: String
  let commands: ReloadCommands
  @State private var count = 0
  var body: some View {
    Text("TAB-\(label) count=\(count)")
      .onAppear { commands.increment = { count += 1 } }
      .onDisappear { commands.increment = nil }
      .task {
        let initialCount = count
        recordReloadEvent("start", value: initialCount)
        do { try await Task.sleep(for: .seconds(86_400)) } catch {}
        recordReloadEvent("cancel", value: initialCount)
      }
  }
}
