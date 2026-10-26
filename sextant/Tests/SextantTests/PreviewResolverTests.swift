import Foundation
import Testing

@testable import Sextant

@Suite("Preview resolver")
struct PreviewResolverTests {
  @Test("specific priority wins and unavailable tools fall back")
  func priorityAndAvailability() {
    let resolver = PreviewResolver()
    let markdown = URL(fileURLWithPath: "/tmp/readme.md")

    #expect(
      resolver.resolve(
        url: markdown,
        classification: .text(.utf8),
        byteCount: 12,
        availableExecutables: [:]
      ) == .builtIn
    )

    #expect(
      resolver.resolve(
        url: markdown,
        classification: .text(.utf8),
        byteCount: 12,
        availableExecutables: [
          "bat": "/opt/bin/bat",
          "glow": "/opt/bin/glow",
        ]
      )
        == .external(
          PreviewLaunch(
            adapterID: PreviewAdapterID("glow"),
            adapterName: "Glow",
            executable: "/opt/bin/glow",
            arguments: ["-s", "dark", "--", "/tmp/readme.md"],
            isInteractive: false
          )
        )
    )
  }

  @Test("explicit external mode exposes a missing executable")
  func explicitExternalMissingExecutable() {
    let resolver = PreviewResolver()
    let markdown = URL(fileURLWithPath: "/tmp/readme.md")

    #expect(
      resolver.resolve(
        url: markdown,
        classification: .text(.utf8),
        byteCount: 12,
        availableExecutables: [:],
        requiresExternal: true
      )
        == .unavailable(
          .missingExecutable(
            adapterName: "Glow",
            executable: "glow"
          )
        )
    )
    #expect(
      resolver.resolve(
        url: URL(fileURLWithPath: "/tmp/value.unknown"),
        classification: .binary,
        byteCount: 12,
        availableExecutables: [:],
        requiresExternal: true
      )
        == .unavailable(.noMatchingAdapter)
    )
  }

  @Test("size limits and classification participate in resolution")
  func sizeAndClassification() {
    let adapter = PreviewAdapterDescription(
      id: PreviewAdapterID("small-text"),
      displayName: "Small text",
      contentKinds: [.text],
      executable: "small",
      isInteractive: false,
      priority: 1,
      maximumByteCount: 10,
      arguments: { [$0.path] }
    )
    let resolver = PreviewResolver(adapters: [adapter])
    let url = URL(fileURLWithPath: "/tmp/value")
    let available = ["small": "/bin/small"]

    #expect(
      resolver.resolve(
        url: url,
        classification: .binary,
        byteCount: 5,
        availableExecutables: available
      ) == .builtIn
    )
    #expect(
      resolver.resolve(
        url: url,
        classification: .text(.utf8),
        byteCount: 11,
        availableExecutables: available
      ) == .builtIn
    )
    #expect(
      resolver.resolve(
        url: url,
        classification: .text(.utf8),
        byteCount: nil,
        availableExecutables: available
      ) == .builtIn
    )
  }

  @Test("missing adapters preserve automatic fallback and report explicit mode")
  func mandatoryFallbackPolicy() {
    let adapter = PreviewAdapterDescription(
      id: PreviewAdapterID("strict"),
      displayName: "Strict previewer",
      contentKinds: [.text],
      executable: "strict-preview",
      isInteractive: false,
      priority: 1,
      arguments: { [$0.path] }
    )
    let resolver = PreviewResolver(adapters: [adapter])
    let url = URL(fileURLWithPath: "/tmp/value.txt")

    #expect(
      resolver.resolve(
        url: url,
        classification: .text(.utf8),
        byteCount: 5,
        availableExecutables: [:]
      )
        == .builtIn
    )
    #expect(
      resolver.resolve(
        url: url,
        classification: .text(.utf8),
        byteCount: 5,
        availableExecutables: [:],
        requiresExternal: true
      )
        == .unavailable(
          .missingExecutable(
            adapterName: "Strict previewer",
            executable: "strict-preview"
          )
        )
    )

    guard
      case .external(let launch) = resolver.resolve(
        url: url,
        classification: .text(.utf8),
        byteCount: 5,
        availableExecutables: ["strict-preview": "/bin/strict-preview"]
      )
    else {
      Issue.record("expected the available strict adapter to launch")
      return
    }
    #expect(launch.adapterName == "Strict previewer")
  }

  @Test("hostile paths remain one exact argv element")
  func hostilePathArguments() {
    let path = "/tmp/- quotes ' and \" plus\nnewline.md"
    let url = URL(fileURLWithPath: path)
    let result = PreviewResolver().resolve(
      url: url,
      classification: .text(.utf8),
      byteCount: 10,
      availableExecutables: ["glow": "/usr/local/bin/glow"]
    )
    guard case .external(let launch) = result else {
      Issue.record("expected external launch")
      return
    }
    #expect(launch.executable == "/usr/local/bin/glow")
    #expect(launch.arguments == ["-s", "dark", "--", path])
  }

  /// The live probe requires an executable regular file, as the editor
  /// handoff does, and `stat` follows a symbolic link to one.
  @Test("the live probe accepts a symbolic link to an executable file")
  func liveProbeAcceptsLinkedExecutable() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("sextant-probe-\(UUID().uuidString)", isDirectory: true)
    let first = root.appendingPathComponent("dirA", isDirectory: true)
    let second = root.appendingPathComponent("dirB", isDirectory: true)
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["real", "tool"] {
      let file = second.appendingPathComponent(name)
      try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }
    try FileManager.default.createSymbolicLink(
      atPath: first.appendingPathComponent("tool").path,
      withDestinationPath: "../dirB/real"
    )
    let adapter = PreviewAdapterDescription(
      id: PreviewAdapterID("linked"),
      displayName: "Linked",
      executable: "tool",
      isInteractive: false,
      priority: 0,
      arguments: { [$0.path] }
    )

    let found = await PreviewExecutableCache.live(path: "\(first.path):\(second.path)")
      .availability(for: [adapter])["tool"]

    let resolved = try #require(found.map(URL.init(fileURLWithPath:)))
    #expect(resolved.lastPathComponent == "tool")
    #expect(resolved.deletingLastPathComponent().lastPathComponent == "dirA")
  }

  @Test("executable probes are cached once per launch PATH")
  func probeCache() async {
    let recorder = ProbeRecorder()
    let cache = PreviewExecutableCache(path: "/one:/two") { executable, path in
      await recorder.record(executable: executable, path: path)
      return "/one/\(executable)"
    }
    let adapters = [
      PreviewAdapterDescription(
        id: PreviewAdapterID("a"),
        displayName: "A",
        executable: "shared",
        isInteractive: false,
        priority: 1,
        arguments: { [$0.path] }
      ),
      PreviewAdapterDescription(
        id: PreviewAdapterID("b"),
        displayName: "B",
        executable: "shared",
        isInteractive: false,
        priority: 2,
        arguments: { [$0.path] }
      ),
    ]

    _ = await cache.availability(for: adapters)
    _ = await cache.availability(for: adapters)
    #expect(await recorder.calls == [Call(executable: "shared", path: "/one:/two")])
  }
}

private struct Call: Equatable, Sendable {
  var executable: String
  var path: String
}

private actor ProbeRecorder {
  private(set) var calls: [Call] = []

  func record(executable: String, path: String) {
    calls.append(Call(executable: executable, path: path))
  }
}
