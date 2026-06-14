import GalleryDemoViews
import SwiftTUIAndroidHost
import SwiftTUIRuntime

private struct GalleryAndroidApp: App {
  var body: some Scene {
    WindowGroup {
      GalleryView()
    }
  }
}

@_cdecl("swift_tui_android_create_host")
public func swift_tui_android_create_host() -> Int64 {
  MainActor.assumeIsolated {
    do {
      let host = try AndroidHostSceneHost(app: GalleryAndroidApp())
      return AndroidHostHandleRegistry.register(host)
    } catch {
      return 0
    }
  }
}
