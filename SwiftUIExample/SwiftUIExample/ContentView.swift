import ExampleScenes
import SwiftTUIRuntime
import SwiftUI
import SwiftUIHost

#if os(macOS)
  import AppKit
#endif

struct ContentView: SwiftUI::View {
  var body: some SwiftUI::View {
    if CommandLine.arguments.contains("--preview-readiness-journey") {
      PreviewReadinessHostContent()
    } else {
      HostedAppContent(app: ExampleApp())
    }
  }
}

private struct PreviewReadinessHostContent: SwiftUI::View {
  var body: some SwiftUI::View {
    #if os(macOS)
      SwiftUI.VStack(spacing: 0) {
        SwiftUI.Button("Resize preview window") {
          guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
            return
          }
          var frame = window.frame
          frame.size.width += 160
          frame.size.height += 100
          window.setFrame(frame, display: true, animate: false)
        }
        .accessibilityLabel("Resize preview window")

        HostedAppContent(app: PreviewReadinessApp())
      }
    #else
      HostedAppContent(app: PreviewReadinessApp())
    #endif
  }
}

private struct HostedAppContent<A: SwiftTUIRuntime.App>: SwiftUI::View {
  let app: A
  @SwiftUI::State private var tuiState: SwiftUIHostAppState<A>?
  @SwiftUI::State private var error: (any Error)?

  var body: some SwiftUI::View {
    if let tuiState {
      SwiftUIHostAppView(state: tuiState)
    } else if let error {
      ContentUnavailableView {
        VStack {
          Image(systemName: "square.stack.3d.up.trianglebadge.exclamationmark.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.yellow, .black)
            .symbolRenderingMode(.palette)
            .symbolVariableValueMode(.color)
            .symbolColorRenderingMode(.gradient)
            .symbolEffect(
              .variableColor.cumulative.dimInactiveLayers.nonReversing,
              options: .repeat(.continuous)
            )
            .frame(maxWidth: 100)
          Text(error.localizedDescription)
            .font(.title)
        }
      }
    } else {
      ProgressView("Starting TUI")
        .onAppear {
          do {
            tuiState = try .init(app: app)
          } catch {
            self.error = error
          }
        }
    }
  }
}

#Preview {
  ContentView()
}
