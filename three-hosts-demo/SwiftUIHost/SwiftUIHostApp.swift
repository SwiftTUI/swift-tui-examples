// MARK: - SwiftUI host stub for three-hosts-demo
//
// This file is the reference content for the native SwiftUI host that wraps
// `ThreeHostsDemoCore.CounterApp` in a macOS window via `SwiftUIHost`.
//
// It is **not** wired into the SwiftPM build of `three-hosts-demo`. Native
// SwiftUI macOS apps need an Xcode project (or an XcodeGen/Tuist manifest) to
// produce a `.app` bundle with the right Info.plist and entitlements. Set up
// the Xcode project alongside this file the same way `SwiftUIExample/` is
// arranged, depending on the local `three-hosts-demo` SwiftPM package for
// `ThreeHostsDemoCore`.
//
// The intended marketing capture is the three windows from a single
// `CounterApp` value: terminal, native SwiftUI window, browser.

import SwiftUI
import SwiftUIHost
import ThreeHostsDemoCore

@main
struct CounterHostApp: SwiftUI.App {
  var body: some SwiftUI.Scene {
    WindowGroup {
      CounterHostContentView()
        .frame(minWidth: 320, minHeight: 200)
    }
  }
}

struct CounterHostContentView: SwiftUI.View {
  @SwiftUI.State private var hostState: SwiftUIHostAppState<CounterApp>?
  @SwiftUI.State private var error: (any Error)?

  var body: some SwiftUI.View {
    if let hostState {
      SwiftUIHostAppView(state: hostState)
    } else if let error {
      Text("Failed to start CounterApp: \(error.localizedDescription)")
        .padding()
    } else {
      ProgressView("Starting SwiftTUI host")
        .onAppear {
          do {
            hostState = try .init(app: CounterApp())
          } catch {
            self.error = error
          }
        }
    }
  }
}
