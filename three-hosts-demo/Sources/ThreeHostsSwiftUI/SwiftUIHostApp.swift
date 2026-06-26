import SwiftUI
import SwiftUIHost
import ThreeHostsDemoCore

@main
struct CounterHostApp: SwiftUI::App {
  var body: some SwiftUI::Scene {
    WindowGroup {
      CounterHostRootView()
    }
  }
}

private struct CounterHostRootView: SwiftUI.View {
  @SwiftUI::State private var hostState: SwiftUIHostAppState<CounterApp>?
  @SwiftUI::State private var launchError: String?

  var body: some SwiftUI.View {
    SwiftUI.Group {
      if let hostState {
        SwiftUIHostAppView(state: hostState)
      } else if let launchError {
        SwiftUI.ContentUnavailableView {
          SwiftUI.Label("SwiftTUI Host Failed", systemImage: "exclamationmark.triangle")
        } description: {
          SwiftUI.Text(launchError)
        }
      } else {
        SwiftUI.ProgressView("Starting SwiftTUI host")
      }
    }
    .task {
      launchHostIfNeeded()
    }
  }

  @MainActor
  private func launchHostIfNeeded() {
    guard hostState == nil, launchError == nil else {
      return
    }

    do {
      hostState = try SwiftUIHostAppState(app: CounterApp())
    } catch {
      launchError = String(describing: error)
    }
  }
}
