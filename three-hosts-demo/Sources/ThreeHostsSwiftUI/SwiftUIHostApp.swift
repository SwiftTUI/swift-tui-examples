import SwiftUI
import SwiftUIHost
import ThreeHostsDemoCore

@main
struct CounterHostApp: SwiftUI::App {
  @SwiftUI::State private var hostState: SwiftUIHostAppState<CounterApp> = try! .init(
    app: CounterApp())
  var body: some SwiftUI::Scene {
    WindowGroup {
      SwiftUIHostAppView(state: hostState)
    }
  }
}
