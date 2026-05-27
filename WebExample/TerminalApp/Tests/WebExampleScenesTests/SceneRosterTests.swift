import Testing
@testable import WebExampleScenes

@Test("WebExampleApp exposes the four-scene gallery tour")
func sceneRosterIncludesFourTourScenes() {
  let app = WebExampleApp()
  #expect(app.sceneTitles == ["Game of Life", "Animations", "Images", "Calculator"])
}
