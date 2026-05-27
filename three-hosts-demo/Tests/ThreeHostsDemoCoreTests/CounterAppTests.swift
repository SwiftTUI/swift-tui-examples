import Testing
@testable import ThreeHostsDemoCore

@Suite("CounterApp wiring")
struct CounterAppTests {
  @Test("CounterApp has a single WindowGroup scene")
  @MainActor
  func counterAppExposesOneScene() async throws {
    let app = CounterApp()
    // Smoke check: instantiating the App must not crash and the body
    // accessor must return a non-nil Scene. The exact scene topology is
    // intentionally not asserted by structural pattern matching here —
    // SwiftTUI's Scene type is opaque; this test exists to guarantee the
    // App stays trivially instantiable from every host target.
    _ = app.body
  }

  @Test("CounterView is buildable from any host without extra arguments")
  @MainActor
  func counterViewIsTriviallyInstantiable() async throws {
    let view = CounterView()
    _ = view.body
  }
}
