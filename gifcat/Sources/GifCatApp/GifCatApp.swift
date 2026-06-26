import GifCat
import SwiftTUI

@main
struct GifCatApp: App {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "gifcat",
    abstract: "Display one or more GIFs in a grid in the terminal."
  )

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Argument(parsing: .remaining, help: "GIF file paths to display.")
  var paths: [String] = []

  var body: some Scene {
    WindowGroup {
      GifCatRootView(paths: paths)
    }
  }
}

private struct GifCatRootView: View {
  let paths: [String]
  @State private var loadedItems: [GifCatItem]?

  var body: some View {
    content
      .task(id: GifCatLoadRequest(paths: paths)) {
        @MainActor in
        if paths.isEmpty {
          loadedItems = []
          return
        }

        loadedItems = nil
        let items = await GifCatInput.loadItems(paths: paths)
        guard !Task.isCancelled else {
          return
        }
        loadedItems = items
      }
  }

  @ViewBuilder
  private var content: some View {
    if paths.isEmpty {
      GifCatView(items: [])
    } else if let loadedItems {
      GifCatView(items: loadedItems)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text("gifcat").foregroundStyle(.foreground)
        Text("loading GIFs...")
          .foregroundStyle(.muted)
      }
      .padding(1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

private struct GifCatLoadRequest: Equatable, Sendable {
  var paths: [String]
}
