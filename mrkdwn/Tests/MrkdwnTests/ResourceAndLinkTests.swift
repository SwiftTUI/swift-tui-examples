import Foundation
import Synchronization
import Testing

@testable import Mrkdwn

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private final class StubImageURLProtocol: URLProtocol {
  enum Mode: Sendable {
    case httpRedirect
    case hostnameRedirect
    case privateRedirect
    case nonHTTPRedirect
    case stall
  }

  private struct State {
    var mode: Mode = .stall
    var observedURLs: [URL] = []
    var stopCount = 0
  }

  private static let state = Mutex(State())

  private static func begin(_ url: URL) -> Mode {
    state.withLock {
      $0.observedURLs.append(url)
      return $0.mode
    }
  }

  private static func stopped() {
    state.withLock {
      $0.stopCount += 1
    }
  }

  static func reset(to mode: Mode) {
    state.withLock {
      $0.mode = mode
      $0.observedURLs = []
      $0.stopCount = 0
    }
  }

  static var snapshot: (urls: [URL], stopCount: Int) {
    state.withLock { ($0.observedURLs, $0.stopCount) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else { return }
    let mode = Self.begin(url)
    switch mode {
    case .httpRedirect where url.path != "/final":
      redirect(to: URL(string: "https://93.184.216.34/final")!)
    case .hostnameRedirect:
      redirect(to: URL(string: "https://redirect.example/final")!)
    case .privateRedirect:
      redirect(to: URL(string: "http://127.0.0.1/private.png")!)
    case .nonHTTPRedirect:
      redirect(to: URL(string: "file:///tmp/redirected.png")!)
    case .httpRedirect:
      let data = Self.pngHeader(width: 2, height: 2)
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Length": "\(data.count)"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    case .stall:
      break
    }
  }

  override func stopLoading() {
    Self.stopped()
  }

  private func redirect(to destination: URL) {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 302,
      httpVersion: "HTTP/1.1",
      headerFields: ["Location": destination.absoluteString]
    )!
    client?.urlProtocol(
      self,
      wasRedirectedTo: URLRequest(url: destination),
      redirectResponse: response
    )
  }
  private static func pngHeader(width: Int, height: Int) -> Data {
    let bytes: [UInt8] = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52,
      UInt8((width >> 24) & 0xFF), UInt8((width >> 16) & 0xFF),
      UInt8((width >> 8) & 0xFF), UInt8(width & 0xFF),
      UInt8((height >> 24) & 0xFF), UInt8((height >> 16) & 0xFF),
      UInt8((height >> 8) & 0xFF), UInt8(height & 0xFF),
    ]
    return Data(bytes)
  }
}

@Suite("links and bounded resources", .serialized)
struct ResourceAndLinkTests {
  @Test("link resolver keeps Markdown navigation inside the viewer")
  func linkResolution() throws {
    let resolver = LinkResolver()
    let document = URL(fileURLWithPath: "/docs/readme.md")

    #expect(resolver.resolve("#intro", relativeTo: document) == .anchor("intro"))
    #expect(
      resolver.resolve("next.markdown", relativeTo: document)
        == .markdownDocument(
          URL(fileURLWithPath: "/docs/next.markdown"),
          anchor: nil
        )
    )
    #expect(
      resolver.resolve("asset.png", relativeTo: document)
        == .file(URL(fileURLWithPath: "/docs/asset.png"))
    )
    #expect(
      resolver.resolve("next%20chapter.md", relativeTo: document)
        == .markdownDocument(
          URL(fileURLWithPath: "/docs/next chapter.md"),
          anchor: nil
        )
    )
    #expect(
      resolver.resolve("next%20chapter.md#part-two", relativeTo: document)
        == .markdownDocument(
          URL(fileURLWithPath: "/docs/next chapter.md"),
          anchor: "part-two"
        )
    )
    #expect(
      resolver.resolve("https://example.com", relativeTo: document)
        == .external(URL(string: "https://example.com")!)
    )
    #expect(
      resolver.resolve("javascript:alert(1)", relativeTo: document)
        == .unsupported(scheme: "javascript")
    )

    let loader = ResourceLoader(allowsRemoteImages: false)
    #expect(
      try loader.resolvedURL("diagram%20one.png", relativeTo: document)
        == URL(fileURLWithPath: "/docs/diagram one.png")
    )
  }

  @Test("PNG and JPEG headers are inspected without decoding")
  func imageHeaders() throws {
    let png = pngHeader(width: 32, height: 16)
    #expect(
      try ImageHeaderInspector().inspect(png)
        == InspectedImage(
          format: .png,
          dimensions: ImageDimensions(width: 32, height: 16)
        )
    )

    let jpeg = Data([
      0xFF, 0xD8,
      0xFF, 0xC0,
      0x00, 0x11,
      0x08,
      0x00, 0x10,
      0x00, 0x20,
      0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
    ])
    #expect(
      try ImageHeaderInspector().inspect(jpeg).dimensions
        == ImageDimensions(width: 32, height: 16)
    )
  }

  @Test("oversized and malformed images fail before SwiftTUI")
  func imageLimits() {
    do {
      _ = try ImageHeaderInspector().inspect(pngHeader(width: 8_193, height: 1))
      Issue.record("Expected dimension failure")
    } catch let error as ImageInspectionError {
      #expect(error == .invalidDimensions(width: 8_193, height: 1))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    do {
      _ = try ImageHeaderInspector().inspect(Data("not an image".utf8))
      Issue.record("Expected format failure")
    } catch let error as ImageInspectionError {
      #expect(error == .unsupportedFormat)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("resource response buffer rejects declared and streamed overflow")
  func boundedResponseBuffer() throws {
    let url = URL(string: "https://example.com/image.png")!
    var declared = BoundedResourceBuffer(maximumBytes: 8)
    #expect(throws: ResourceLoadError.self) {
      try declared.validateExpectedLength(9, url: url)
    }

    var streamed = BoundedResourceBuffer(maximumBytes: 8)
    try streamed.append(Data(repeating: 0, count: 5), url: url)
    #expect(throws: ResourceLoadError.self) {
      try streamed.append(Data(repeating: 0, count: 4), url: url)
    }
    #expect(streamed.data.count == 5)
  }

  @Test("resource cache enforces entry LRU bound")
  func cacheBounds() async {
    let cache = ResourceCache()
    for index in 0..<100 {
      let url = URL(fileURLWithPath: "/image-\(index).png")
      let data = Data([UInt8(index % 255)])
      await cache.insert(
        data,
        for: ResourceCacheKey(
          url: url,
          fingerprint: ResourceLoader.fingerprint(data)
        )
      )
    }
    let occupancy = await cache.occupancy
    #expect(occupancy.entries == ResourceCache.maximumEntries)
    #expect(occupancy.bytes == ResourceCache.maximumEntries)
  }

  @Test("local image replacement invalidates the coordinated cache")
  func localCacheInvalidation() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mrkdwn-image-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = directory.appendingPathComponent("document.md")
    let image = directory.appendingPathComponent("image.png")
    try pngHeader(width: 16, height: 8).write(to: image)
    let coordinator = ImageLoadCoordinator(
      loader: ResourceLoader(allowsRemoteImages: false)
    )

    let first = try await coordinator.load(
      source: "image.png",
      relativeTo: document
    )
    #expect(first.image.dimensions == ImageDimensions(width: 16, height: 8))

    try pngHeader(width: 32, height: 8).write(to: image, options: .atomic)
    let second = try await coordinator.load(
      source: "image.png",
      relativeTo: document
    )
    #expect(second.image.dimensions == ImageDimensions(width: 32, height: 8))
  }

  @Test("local image bytes retain the identity of their open descriptor")
  func localDescriptorIdentity() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mrkdwn-image-identity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let image = directory.appendingPathComponent("image.png")
    try pngHeader(width: 16, height: 8).write(to: image)

    let loaded = try await ResourceLoader(allowsRemoteImages: false).load(
      source: image.absoluteString,
      relativeTo: nil
    )
    let loadedIdentity = try #require(loaded.localVersion)
    let initialPathIdentity = try BoundedRegularFileReader.identity(of: image)
    #expect(loadedIdentity == initialPathIdentity)

    try pngHeader(width: 32, height: 8).write(to: image, options: .atomic)
    let replacementIdentity = try BoundedRegularFileReader.identity(of: image)
    #expect(loadedIdentity != replacementIdentity)
    #expect(loaded.image.dimensions == ImageDimensions(width: 16, height: 8))
  }

  @Test("malformed, truncated, zero, decoded-overflow, and decoded-cap images fail")
  func comprehensiveImageRejection() {
    let inspector = ImageHeaderInspector()
    #expect(throws: ImageInspectionError.truncated) {
      try inspector.inspect(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }
    #expect(throws: ImageInspectionError.truncated) {
      try inspector.inspect(Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00]))
    }
    #expect(throws: ImageInspectionError.invalidDimensions(width: 0, height: 1)) {
      try inspector.inspect(pngHeader(width: 0, height: 1))
    }
    #expect(throws: ImageInspectionError.decodedImageTooLarge(268_435_456)) {
      try inspector.inspect(pngHeader(width: 8_192, height: 8_192))
    }
    #expect(ImageDimensions(width: Int.max, height: 2).decodedRGBABytes == nil)
  }

  @Test("unsupported image schemes fail before any resource I/O")
  func unsupportedImageScheme() async {
    let loader = ResourceLoader(allowsRemoteImages: true)
    do {
      _ = try await loader.load(source: "data:image/png;base64,AA==", relativeTo: nil)
      Issue.record("Expected an unsupported image scheme")
    } catch let error as ResourceLoadError {
      guard case .unsupportedScheme("data") = error else {
        Issue.record("Unexpected resource error: \(error)")
        return
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("remote image policy rejects non-public networks and unsafe authority")
  func remoteImageNetworkPolicy() {
    #expect(!RemoteImageNetworkPolicy.isPublicAddress([127, 0, 0, 1]))
    #expect(!RemoteImageNetworkPolicy.isPublicAddress([10, 0, 0, 1]))
    #expect(!RemoteImageNetworkPolicy.isPublicAddress([169, 254, 1, 1]))
    #expect(!RemoteImageNetworkPolicy.isPublicAddress([192, 168, 1, 1]))
    #expect(!RemoteImageNetworkPolicy.isPublicAddress([192, 88, 99, 1]))
    #expect(RemoteImageNetworkPolicy.isPublicAddress([8, 8, 8, 8]))
    #expect(
      !RemoteImageNetworkPolicy.isPublicAddress([
        0x20, 0x01, 0, 2, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 1,
      ])
    )
    #expect(
      !RemoteImageNetworkPolicy.isPublicAddress([
        0x3F, 0xFF, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 1,
      ])
    )
    #expect(
      RemoteImageNetworkPolicy.isPublicAddress([
        0x26, 0x06, 0x47, 0x00, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 1,
      ])
    )
    #expect(throws: ResourceLoadError.self) {
      try RemoteImageNetworkPolicy.validate(URL(string: "http://localhost/image.png")!)
    }
    #expect(throws: ResourceLoadError.self) {
      try RemoteImageNetworkPolicy.validate(URL(string: "https://example.com/image.png")!)
    }
    #expect(throws: ResourceLoadError.self) {
      try RemoteImageNetworkPolicy.validate(
        URL(string: "http://93.184.216.34./image.png")!
      )
    }
    #expect(throws: ResourceLoadError.self) {
      try RemoteImageNetworkPolicy.validate(URL(string: "https://example.com:8443/image.png")!)
    }
    #expect(throws: ResourceLoadError.self) {
      try RemoteImageNetworkPolicy.validate(
        URL(string: "https://user:secret@example.com/image.png")!
      )
    }
    #expect(throws: ResourceLoadError.self) {
      try RemoteImageNetworkPolicy.validatePeerAddress(
        "127.0.0.1",
        for: URL(string: "https://example.com/image.png")!
      )
    }
    #expect(throws: Never.self) {
      try RemoteImageNetworkPolicy.validate(
        URL(string: "http://93.184.216.34/image.png")!
      )
    }
    #expect(throws: Never.self) {
      try RemoteImageNetworkPolicy.validate(
        URL(string: "https://[2606:4700:4700::1111]/image.png")!
      )
    }
    #expect(throws: Never.self) {
      try RemoteImageNetworkPolicy.validatePeerAddress(
        "8.8.8.8",
        for: URL(string: "https://example.com/image.png")!
      )
    }
  }

  @Test("hostname policy rejects before URL loading begins")
  func hostnameRejectedBeforeRequest() async {
    StubImageURLProtocol.reset(to: .stall)
    let loader = ResourceLoader(
      allowsRemoteImages: true,
      remoteSessionConfiguration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubImageURLProtocol.self]
        return configuration
      }
    )

    do {
      _ = try await loader.load(
        source: "https://example.test/private-probe.png",
        relativeTo: nil
      )
      Issue.record("Expected a hostname destination to be blocked")
    } catch let error as ResourceLoadError {
      guard case .remoteDestinationBlocked = error else {
        Issue.record("Unexpected resource error: \(error)")
        return
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
    #expect(StubImageURLProtocol.snapshot.urls.isEmpty)
  }

  @Test("HTTP redirects remain bounded and non-HTTP redirects are rejected")
  func redirectPolicy() async throws {
    #if canImport(Darwin)
      StubImageURLProtocol.reset(to: .httpRedirect)
      let redirected = try await remoteLoader(timeout: 1).load(
        source: "https://93.184.216.34/start",
        relativeTo: nil
      )
      #expect(redirected.image.dimensions == ImageDimensions(width: 2, height: 2))
      #expect(StubImageURLProtocol.snapshot.urls.map(\.path) == ["/start", "/final"])

      StubImageURLProtocol.reset(to: .nonHTTPRedirect)
      do {
        _ = try await remoteLoader(timeout: 1).load(
          source: "https://93.184.216.34/start",
          relativeTo: nil
        )
        Issue.record("Expected the non-HTTP redirect to fail")
      } catch {
        #expect(!StubImageURLProtocol.snapshot.urls.contains { $0.scheme == "file" })
      }

      StubImageURLProtocol.reset(to: .privateRedirect)
      do {
        _ = try await remoteLoader(timeout: 1).load(
          source: "https://93.184.216.34/start",
          relativeTo: nil
        )
        Issue.record("Expected the private-network redirect to fail")
      } catch let error as ResourceLoadError {
        guard case .remoteDestinationBlocked = error else {
          Issue.record("Unexpected resource error: \(error)")
          return
        }
        #expect(!StubImageURLProtocol.snapshot.urls.contains { $0.host == "127.0.0.1" })
      } catch {
        Issue.record("Unexpected error: \(error)")
      }

      StubImageURLProtocol.reset(to: .hostnameRedirect)
      do {
        _ = try await remoteLoader(timeout: 1).load(
          source: "https://93.184.216.34/start",
          relativeTo: nil
        )
        Issue.record("Expected the hostname redirect to fail")
      } catch let error as ResourceLoadError {
        guard case .remoteDestinationBlocked = error else {
          Issue.record("Unexpected resource error: \(error)")
          return
        }
        #expect(!StubImageURLProtocol.snapshot.urls.contains { $0.host == "redirect.example" })
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    #else
      // swift-corelibs-foundation's custom URLProtocol client traps when a
      // fixture reports a redirect. Linux still compiles the production
      // redirect delegate and exercises both destination policies directly;
      // the complete URLSession redirect journey runs on Darwin.
      #expect(throws: ResourceLoadError.self) {
        try RemoteImageNetworkPolicy.validate(
          URL(string: "file:///tmp/redirected.png")!
        )
      }
      #expect(throws: ResourceLoadError.self) {
        try RemoteImageNetworkPolicy.validate(
          URL(string: "http://127.0.0.1/private.png")!
        )
      }
    #endif
  }

  @Test("local image and theme readers reject non-regular files")
  func localReadersRejectDirectories() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mrkdwn-nonregular-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      _ = try await ResourceLoader(allowsRemoteImages: false).load(
        source: directory.absoluteString,
        relativeTo: nil
      )
      Issue.record("Expected a non-regular image failure")
    } catch let error as ResourceLoadError {
      guard case .requestFailed(_, let reason) = error else {
        Issue.record("Unexpected resource error: \(error)")
        return
      }
      #expect(reason.contains("regular file"))
    }

    do {
      _ = try ThemeRepository().load(.file(directory, explicit: true))
      Issue.record("Expected a non-regular theme failure")
    } catch let error as ThemeRepositoryError {
      guard case .unreadable(_, let reason) = error else {
        Issue.record("Unexpected theme error: \(error)")
        return
      }
      #expect(reason.contains("regular file"))
    }
  }

  @Test("remote image timeout and cancellation stop the underlying transfer")
  func timeoutAndCancellation() async {
    StubImageURLProtocol.reset(to: .stall)
    let timeoutClock = ContinuousClock()
    let timeoutStart = timeoutClock.now
    do {
      _ = try await remoteLoader(timeout: 0.05).load(
        source: "https://93.184.216.34/timeout",
        relativeTo: nil
      )
      Issue.record("Expected the request to time out")
    } catch {
      #expect(timeoutStart.duration(to: timeoutClock.now) < .seconds(2))
    }

    StubImageURLProtocol.reset(to: .stall)
    let task = Task {
      try await remoteLoader(timeout: 10).load(
        source: "https://93.184.216.34/cancel",
        relativeTo: nil
      )
    }
    for _ in 0..<100 where StubImageURLProtocol.snapshot.urls.isEmpty {
      try? await Task.sleep(for: .milliseconds(1))
    }
    task.cancel()
    _ = try? await task.value
    for _ in 0..<100 where StubImageURLProtocol.snapshot.stopCount == 0 {
      try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(StubImageURLProtocol.snapshot.stopCount > 0)
  }

  @Test("image coordinator bounds and immediately removes cancelled waiters")
  func boundedCoordinatorWaiters() async {
    StubImageURLProtocol.reset(to: .stall)
    let coordinator = ImageLoadCoordinator(
      loader: remoteLoader(timeout: 10),
      maximumConcurrentRequests: 1,
      maximumQueuedRequests: 2
    )
    let first = Task {
      try await coordinator.load(
        source: "https://93.184.216.34/one",
        relativeTo: nil
      )
    }
    for _ in 0..<200 where await coordinator.activeRequestCount != 1 {
      try? await Task.sleep(for: .milliseconds(1))
    }

    let second = Task {
      try await coordinator.load(
        source: "https://93.184.216.34/two",
        relativeTo: nil
      )
    }
    let third = Task {
      try await coordinator.load(
        source: "https://93.184.216.34/three",
        relativeTo: nil
      )
    }
    for _ in 0..<200 where await coordinator.queuedRequestCount != 2 {
      try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(await coordinator.activeRequestCount == 1)
    #expect(await coordinator.queuedRequestCount == 2)

    second.cancel()
    third.cancel()
    _ = try? await second.value
    _ = try? await third.value
    for _ in 0..<200 where await coordinator.queuedRequestCount != 0 {
      try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(await coordinator.queuedRequestCount == 0)

    first.cancel()
    _ = try? await first.value
    for _ in 0..<200 where await coordinator.activeRequestCount != 0 {
      try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(await coordinator.activeRequestCount == 0)
  }

  @Test("external opener subprocesses are timed and cancellable")
  func externalOpenerLifecycle() async throws {
    let opener = PlatformLinkOpener()
    let clock = ContinuousClock()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mrkdwn-opener-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let timedPID = directory.appendingPathComponent("timed.pid")
    let timeoutStart = clock.now
    let timed = await opener.run(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", Self.childProcessScript, "mrkdwn-opener", timedPID.path],
      timeout: .milliseconds(50)
    )
    #expect(!timed)
    #expect(timeoutStart.duration(to: clock.now) < .seconds(2))
    await expectRecordedProcessIsGone(at: timedPID)

    let cancelledPID = directory.appendingPathComponent("cancelled.pid")
    let cancellationStart = clock.now
    let task = Task {
      await opener.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: [
          "-c",
          Self.childProcessScript,
          "mrkdwn-opener",
          cancelledPID.path,
        ],
        timeout: .seconds(30)
      )
    }
    for _ in 0..<200 where !FileManager.default.fileExists(atPath: cancelledPID.path) {
      try? await Task.sleep(for: .milliseconds(1))
    }
    task.cancel()
    #expect(await task.value == false)
    #expect(cancellationStart.duration(to: clock.now) < .seconds(2))
    await expectRecordedProcessIsGone(at: cancelledPID)
  }

  @Test("external opener subprocesses do not inherit unrelated descriptors")
  func externalOpenerDescriptorIsolation() async {
    #if canImport(Darwin) || canImport(Glibc)
      let sourceDescriptor = unsafe open("/dev/null", O_RDONLY)
      #expect(sourceDescriptor >= 0)
      guard sourceDescriptor >= 0 else { return }
      let inheritedDescriptor = fcntl(sourceDescriptor, F_DUPFD, 100)
      _ = close(sourceDescriptor)
      #expect(inheritedDescriptor >= 100)
      guard inheritedDescriptor >= 100 else { return }
      defer { close(inheritedDescriptor) }
      #expect(fcntl(inheritedDescriptor, F_SETFD, 0) == 0)

      let isolated = await PlatformLinkOpener().run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: [
          "-c",
          "test ! -e /dev/fd/\(inheritedDescriptor)",
        ],
        timeout: .seconds(2)
      )
      #expect(isolated)
    #else
      Issue.record("Descriptor isolation requires Darwin or Glibc")
    #endif
  }

  private func remoteLoader(timeout: TimeInterval) -> ResourceLoader {
    ResourceLoader(
      allowsRemoteImages: true,
      inspector: ImageHeaderInspector(),
      remoteSessionConfiguration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubImageURLProtocol.self]
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return configuration
      },
      remoteURLValidator: RemoteImageNetworkPolicy.validate,
      remotePeerValidator: RemoteImageNetworkPolicy.validatePeerAddress,
      requiresPublicPeerValidation: false
    )
  }

  private static let childProcessScript = """
    sleep 30 &
    child=$!
    trap '' TERM INT
    printf '%s\\n' "$child" > "$1"
    wait "$child"
    """

  private func expectRecordedProcessIsGone(at url: URL) async {
    var processIdentifier: pid_t?
    for _ in 0..<200 where processIdentifier == nil {
      if let contents = try? String(contentsOf: url, encoding: .utf8),
        let value = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
      {
        processIdentifier = value
      } else {
        try? await Task.sleep(for: .milliseconds(1))
      }
    }
    guard let processIdentifier else {
      Issue.record("The opener child did not record its process identifier")
      return
    }
    for _ in 0..<200 where processIsRunning(processIdentifier) {
      try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(!processIsRunning(processIdentifier))
  }

  private func processIsRunning(_ processIdentifier: pid_t) -> Bool {
    #if os(Linux)
      if let status = try? String(
        contentsOfFile: "/proc/\(processIdentifier)/stat",
        encoding: .utf8
      ), status.split(separator: " ").dropFirst(2).first == "Z" {
        // Minimal test containers may not have an init process that reaps
        // adopted zombies. A zombie has terminated and cannot execute.
        return false
      }
    #endif
    return kill(processIdentifier, 0) == 0
  }

  private func pngHeader(width: Int, height: Int) -> Data {
    var bytes: [UInt8] = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52,
      0, 0, 0, 0,
      0, 0, 0, 0,
    ]
    writeBigEndian(width, to: &bytes, at: 16)
    writeBigEndian(height, to: &bytes, at: 20)
    return Data(bytes)
  }

  private func writeBigEndian(_ value: Int, to bytes: inout [UInt8], at offset: Int) {
    bytes[offset] = UInt8((value >> 24) & 0xFF)
    bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
    bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
    bytes[offset + 3] = UInt8(value & 0xFF)
  }
}
