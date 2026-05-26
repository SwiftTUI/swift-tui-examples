import SwiftTUIRuntime

public struct HostDetailsView: View {
  private let title: String
  private let lines: [String]
  private let showsTerminalSizeInBody: Bool
  private let showsTerminalSizeInToolbar: Bool

  public init(
    title: String,
    lines: [String],
    showsTerminalSizeInBody: Bool = false,
    showsTerminalSizeInToolbar: Bool = false
  ) {
    self.title = title
    self.lines = lines
    self.showsTerminalSizeInBody = showsTerminalSizeInBody
    self.showsTerminalSizeInToolbar = showsTerminalSizeInToolbar
  }

  public var body: some View {
    GeometryReader { geometry in
      content(geometry: geometry)
    }
  }

  @ViewBuilder
  private func content(geometry: GeometryProxy) -> some View {
    let base = VStack(alignment: .leading, spacing: 1) {
      Text(title)
      Divider()
      ForEach(lines, id: \.self) { line in
        Text(line)
      }
      if showsTerminalSizeInBody {
        Text("Reported terminal size: \(geometry.size.width)x\(geometry.size.height)")
      }
      Spacer()
    }
    .padding(1)

    if showsTerminalSizeInToolbar {
      base.toolbarItem(
        .init(
          title: "terminal size: \(geometry.size.width)x\(geometry.size.height)",
          action: {}
        )
      )
    } else {
      base
    }
  }
}
