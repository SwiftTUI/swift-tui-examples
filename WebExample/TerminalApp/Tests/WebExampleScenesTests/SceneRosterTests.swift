import Testing
@testable import WebExampleScenes

@Test("WebExampleApp is the shared multi-host counter")
func webExampleUsesSharedCounterApp() {
  let app = WebExampleApp()
  #expect(String(describing: type(of: app)) == "CounterApp")
}
