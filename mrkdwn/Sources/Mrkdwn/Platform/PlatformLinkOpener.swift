public import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct PlatformLinkOpener: Sendable {
  public init() {}

  public func open(_ url: URL, timeout: Duration = .seconds(10)) async -> Bool {
    #if os(macOS)
      let executable = URL(fileURLWithPath: "/usr/bin/open")
      let arguments = ["--", url.absoluteString]
    #elseif os(Linux)
      let executable = URL(fileURLWithPath: "/usr/bin/xdg-open")
      let arguments = [url.absoluteString]
    #else
      return false
    #endif

    return await run(
      executable: executable,
      arguments: arguments,
      timeout: timeout
    )
  }

  func run(
    executable: URL,
    arguments: [String],
    timeout: Duration
  ) async -> Bool {
    guard
      let processIdentifier = Self.spawn(
        executable: executable.path,
        arguments: arguments
      )
    else { return false }
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline, !Task.isCancelled {
      switch Self.poll(processIdentifier) {
      case .running:
        break
      case .exited(let status):
        return !Task.isCancelled
          && clock.now < deadline
          && Self.exitedSuccessfully(status)
      case .unavailable:
        return false
      }
      do {
        try await Task.sleep(for: .milliseconds(20))
      } catch {
        break
      }
    }

    Self.signalProcessGroup(processIdentifier, signal: SIGTERM)
    let terminationDeadline = clock.now + .milliseconds(250)
    while clock.now < terminationDeadline {
      switch Self.poll(processIdentifier) {
      case .running:
        await Self.cleanupPause()
      case .exited, .unavailable:
        return false
      }
    }

    Self.signalProcessGroup(processIdentifier, signal: SIGKILL)
    let reapDeadline = clock.now + .seconds(1)
    while clock.now < reapDeadline {
      switch Self.poll(processIdentifier) {
      case .running:
        await Self.cleanupPause()
      case .exited, .unavailable:
        return false
      }
    }
    return false
  }

  private enum ChildState {
    case running
    case exited(Int32)
    case unavailable
  }

  private static func spawn(
    executable: String,
    arguments: [String]
  ) -> pid_t? {
    guard !executable.isEmpty, !executable.utf8.contains(0),
      !arguments.contains(where: { $0.utf8.contains(0) })
    else {
      return nil
    }

    #if canImport(Darwin)
      var fileActions: posix_spawn_file_actions_t?
    #else
      var fileActions = unsafe posix_spawn_file_actions_t()
    #endif
    guard unsafe posix_spawn_file_actions_init(&fileActions) == 0 else { return nil }
    defer { unsafe posix_spawn_file_actions_destroy(&fileActions) }
    guard
      unsafe posix_spawn_file_actions_addopen(
        &fileActions,
        STDIN_FILENO,
        "/dev/null",
        O_RDONLY,
        0
      ) == 0,
      unsafe posix_spawn_file_actions_addopen(
        &fileActions,
        STDOUT_FILENO,
        "/dev/null",
        O_WRONLY,
        0
      ) == 0,
      unsafe posix_spawn_file_actions_addopen(
        &fileActions,
        STDERR_FILENO,
        "/dev/null",
        O_WRONLY,
        0
      ) == 0
    else {
      return nil
    }
    #if canImport(Glibc)
      guard
        unsafe posix_spawn_file_actions_addclosefrom_np(
          &fileActions,
          STDERR_FILENO + 1
        ) == 0
      else {
        return nil
      }
    #endif

    #if canImport(Darwin)
      var attributes: posix_spawnattr_t?
      let spawnFlags =
        POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
    #else
      var attributes = posix_spawnattr_t()
      let spawnFlags = POSIX_SPAWN_SETPGROUP
    #endif
    guard unsafe posix_spawnattr_init(&attributes) == 0 else { return nil }
    defer { unsafe posix_spawnattr_destroy(&attributes) }
    guard
      unsafe posix_spawnattr_setflags(
        &attributes,
        Int16(spawnFlags)
      ) == 0,
      unsafe posix_spawnattr_setpgroup(&attributes, 0) == 0
    else {
      return nil
    }

    guard
      var argumentPointers = unsafe makeCStringArray([executable] + arguments),
      var environmentPointers = unsafe makeCStringArray(
        ProcessInfo.processInfo.environment
          .map { "\($0.key)=\($0.value)" }
          .sorted()
      )
    else {
      return nil
    }
    defer {
      unsafe releaseCStringArray(argumentPointers)
      unsafe releaseCStringArray(environmentPointers)
    }

    var processIdentifier: pid_t = 0
    let result = unsafe executable.withCString { executablePointer in
      unsafe argumentPointers.withUnsafeMutableBufferPointer { argumentBuffer in
        unsafe environmentPointers.withUnsafeMutableBufferPointer { environmentBuffer in
          unsafe posix_spawn(
            &processIdentifier,
            executablePointer,
            &fileActions,
            &attributes,
            argumentBuffer.baseAddress!,
            environmentBuffer.baseAddress!
          )
        }
      }
    }
    return result == 0 ? processIdentifier : nil
  }

  private static func makeCStringArray(
    _ strings: [String]
  ) -> [UnsafeMutablePointer<CChar>?]? {
    var result: [UnsafeMutablePointer<CChar>?] = unsafe []
    unsafe result.reserveCapacity(strings.count + 1)
    for string in strings {
      guard let pointer = unsafe strdup(string) else {
        unsafe releaseCStringArray(result)
        return nil
      }
      unsafe result.append(pointer)
    }
    unsafe result.append(nil)
    return unsafe result
  }

  private static func releaseCStringArray(
    _ pointers: [UnsafeMutablePointer<CChar>?]
  ) {
    var index = 0
    while index < (unsafe pointers.count) {
      let pointer = unsafe pointers[index]
      unsafe free(pointer)
      index += 1
    }
  }

  private static func poll(_ processIdentifier: pid_t) -> ChildState {
    while true {
      var status: Int32 = 0
      let result = unsafe waitpid(processIdentifier, &status, WNOHANG)
      if result == processIdentifier {
        return .exited(status)
      }
      if result == 0 {
        return .running
      }
      if errno != EINTR {
        return .unavailable
      }
    }
  }

  private static func exitedSuccessfully(_ status: Int32) -> Bool {
    status & 0x7F == 0 && (status >> 8) & 0xFF == 0
  }

  private static func signalProcessGroup(
    _ processIdentifier: pid_t,
    signal: Int32
  ) {
    _ = kill(-processIdentifier, signal)
    _ = kill(processIdentifier, signal)
  }

  private static func cleanupPause() async {
    await Task.detached {
      _ = usleep(10_000)
    }.value
  }
}
