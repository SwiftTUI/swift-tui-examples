import Foundation
import SwiftTUI

final class ReloadReference: Codable {
  var value: Int
  init(value: Int) { self.value = value }
}

struct ReloadRoot: View {
  @State private var count = 7
  @State private var reference = ReloadReference(value: 11)

  var body: some View {
    let displayedCount = count
    VStack {
      Text("GEN-000 count=\(count) reference=\(reference.value)")
      Button("Increment") {
        count += 1
        reference.value += 1
      }
      Text("Edit GEN-000 in App.swift, or press Return to increment.")
    }
    .onAppear { recordReloadEvent("appear", value: count) }
    .onDisappear { recordReloadEvent("disappear", value: displayedCount) }
    .task {
      let initialCount = count
      recordReloadEvent("start", value: initialCount)
      do { try await Task.sleep(for: .seconds(86_400)) } catch {}
      recordReloadEvent("cancel", value: initialCount)
    }
  }
}

// Optional process-test evidence. Normal launches do not open a log file.
@MainActor
func recordReloadEvent(_ event: String, value: Int) {
  guard let path = ProcessInfo.processInfo.environment["SWIFTTUI_RELOAD_PROBE"] else { return }
  let url = URL(fileURLWithPath: path)
  if !FileManager.default.fileExists(atPath: path) {
    _ = FileManager.default.createFile(atPath: path, contents: nil)
  }
  guard let file = try? FileHandle(forWritingTo: url) else { return }
  defer { try? file.close() }
  _ = try? file.seekToEnd()
  try? file.write(contentsOf: Data("\(event) GEN-000 \(value)\n".utf8))
}

@main struct HotReloadDemo: App {
  var body: some Scene { WindowGroup { ReloadRoot() } }
}

#if DEBUG && SWIFTTUI_HOT_RELOAD && (os(macOS) || os(Linux))
@_cdecl("swifttui_hot_reload_root")
@MainActor public func reloadRoot() -> UnsafeMutableRawPointer {
  HotReloadExport.retainedRoot { ReloadRoot() }
}
#endif
