import Foundation
import SwiftTUI

final class ReloadReference: Codable {
  var value: Int
  init(value: Int) { self.value = value }
}

/// Currently internal functionality only
///
///  mise exec -- bazel run //:open_overlay -- \
///    --source-mode worktree \
///    --output "$PWD/.build/coordination/hot-reload-demo" \
///    examples
///
///  swiftly run swift run \
///    --package-path "$PWD/.build/coordination/hot-reload-demo/swift-tui" \
///    swifttui-dev \
///    --package-path "$PWD/.build/coordination/hot-reload-demo/swift-tui-examples/hot-reload" \
///    --product HotReloadDemo
struct ReloadRoot: View {
  @State private var count = 7
  @State private var reference = ReloadReference(value: 11)

  var body: some View {
    let displayedCount = count
    VStack(spacing: 1) {
      Text("GEN-003HELLO count=\(count) reference=\(reference.value)")
      Button("Increment") {
        count += 1
        reference.value += 1
      }
      Text("Edit GEN-003 in App.swift, or press Return to increment.")
      HStack(spacing: 2) {
        Rectangle().fill(.red)
        Rectangle().fill(.blue)
        Rectangle().fill(.cyan)
      }
      HStack(spacing: 2) {
        Rectangle().fill(.magenta)
        Rectangle().fill(.yellow)
        Rectangle().fill(.green)
      }
      HStack(spacing: 2) {
        Rectangle().fill(.white)
        Rectangle().fill(.black)
        Rectangle().fill(.gray)
      }
    }
    .padding(1)
    .padding(.horizontal, 1)
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
  try? file.write(contentsOf: Data("\(event) GEN-003 \(value)\n".utf8))
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
