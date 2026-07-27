public import Foundation
import SwiftTUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct HandoffClient: Sendable {
  public var open: @Sendable (URL) async -> Result<Void, HandoffFailure>
  public var edit: @Sendable (_ command: [String], _ url: URL) async -> Result<Void, HandoffFailure>
  public var reveal: @Sendable (URL) async -> Result<Void, HandoffFailure>
  public var copy: @Sendable (String) async -> Result<Void, HandoffFailure>

  public init(
    open: @escaping @Sendable (URL) async -> Result<Void, HandoffFailure>,
    edit:
      @escaping @Sendable ([String], URL) async -> Result<Void, HandoffFailure>,
    reveal: @escaping @Sendable (URL) async -> Result<Void, HandoffFailure>,
    copy: @escaping @Sendable (String) async -> Result<Void, HandoffFailure>
  ) {
    self.open = open
    self.edit = edit
    self.reveal = reveal
    self.copy = copy
  }
}

public enum HandoffFailure: Error, Equatable, Sendable {
  case unavailable(String)
  case invalidEditor(String)
  case launchFailed(String)
  case nonzeroExit(command: String, status: Int32)
}

public struct EditorCommandResolver: Sendable {
  public var lexer: POSIXWordLexer

  public init(lexer: POSIXWordLexer = POSIXWordLexer()) {
    self.lexer = lexer
  }

  public func resolve(
    environment: [String: String],
    configuredFallback: [String]?
  ) -> Result<[String], HandoffFailure> {
    for name in ["VISUAL", "EDITOR"] {
      if let source = environment[name], !source.isEmpty {
        do {
          let words = try lexer.parse(source)
          guard !words.isEmpty else {
            return .failure(.invalidEditor("\(name) is empty."))
          }
          return .success(words)
        } catch {
          return .failure(
            .invalidEditor("\(name) could not be parsed: \(error)")
          )
        }
      }
    }
    guard let configuredFallback, !configuredFallback.isEmpty,
      !configuredFallback[0].isEmpty
    else {
      return .failure(
        .unavailable("Set VISUAL, EDITOR, or the Sextant editor configuration.")
      )
    }
    return .success(configuredFallback)
  }
}

extension HandoffClient {
  public static func live() -> HandoffClient {
    live { value in
      let result = await runHandoffProcess(
        "/usr/bin/pbcopy",
        arguments: [],
        standardIO: .input(Data(value.utf8))
      )
      if case .success = result {
        return true
      }
      return false
    }
  }

  public static func live(
    clipboard: @escaping @Sendable (String) async -> Bool
  ) -> HandoffClient {
    live(
      clipboard: clipboard,
      environment: ProcessInfo.processInfo.environment,
      editorStandardIO: .terminal
    )
  }

  static func live(
    clipboard: @escaping @Sendable (String) async -> Bool,
    environment: [String: String],
    editorStandardIO: ProcessStandardIO
  ) -> HandoffClient {
    HandoffClient(
      open: { url in
        await runHandoffProcess("/usr/bin/open", arguments: ["--", url.path])
      },
      edit: { command, url in
        guard let executable = command.first else {
          return .failure(.invalidEditor("The editor command is empty."))
        }
        let resolvedExecutable: String
        switch resolveLaunchExecutable(executable, environment: environment) {
        case .success(let value):
          resolvedExecutable = value
        case .failure(let failure):
          return .failure(failure)
        }
        return await runHandoffProcess(
          resolvedExecutable,
          arguments: Array(command.dropFirst()) + ["--", url.path],
          standardIO: editorStandardIO,
          environment: environment
        )
      },
      reveal: { url in
        await runHandoffProcess("/usr/bin/open", arguments: ["-R", "--", url.path])
      },
      copy: { value in
        await clipboard(value)
          ? .success(())
          : .failure(.unavailable("The host clipboard is unavailable."))
      }
    )
  }

  func perform(
    _ request: BrowserHandoffRequest
  ) async -> Result<Void, HandoffFailure> {
    switch request {
    case .open(let url):
      await open(url)
    case .edit(let command, let url):
      await edit(command, url)
    case .reveal(let url):
      await reveal(url)
    case .copy(let value):
      await copy(value)
    }
  }

  @MainActor
  func performWithRuntimeHandoff(
    _ request: BrowserHandoffRequest
  ) async -> Result<Void, HandoffFailure> {
    guard case .edit = request else {
      return await perform(request)
    }
    do {
      try await TerminalHandoffAction.perform {
        if case .failure(let failure) = await perform(request) {
          throw failure
        }
      }
      return .success(())
    } catch let failure as HandoffFailure {
      return .failure(failure)
    } catch let failure as TerminalHandoffError {
      return .failure(.unavailable(failure.description))
    } catch {
      return .failure(.launchFailed(String(describing: error)))
    }
  }
}

func runHandoffProcess(
  _ executable: String,
  arguments: [String],
  standardIO: ProcessStandardIO = .discarded,
  environment: [String: String]? = nil,
  terminationGracePeriod: Duration = .milliseconds(750)
) async -> Result<Void, HandoffFailure> {
  let controller = CancellableProcess()
  return await withTaskCancellationHandler {
    await withCheckedContinuation { continuation in
      let process = controller.process
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      if let environment {
        process.environment = environment
      }
      switch standardIO {
      case .discarded:
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
      case .terminal:
        guard let terminal = FileHandle(forUpdatingAtPath: "/dev/tty") else {
          continuation.resume(
            returning: .failure(
              .unavailable("No controlling terminal is available for the editor.")
            )
          )
          return
        }
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
      case .fileDescriptor(let fileDescriptor):
        let terminal = FileHandle(
          fileDescriptor: fileDescriptor,
          closeOnDealloc: false
        )
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
      case .input:
        break
      }
      let inputPipe: Pipe?
      if case .input = standardIO {
        let pipe = Pipe()
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        inputPipe = pipe
      } else {
        inputPipe = nil
      }
      process.terminationHandler = { process in
        if process.terminationStatus == 0 {
          continuation.resume(returning: .success(()))
        } else {
          continuation.resume(
            returning: .failure(
              .nonzeroExit(
                command: executable,
                status: process.terminationStatus
              )
            )
          )
        }
      }
      do {
        try controller.run()
        if case .input(let data) = standardIO, let inputPipe {
          inputPipe.fileHandleForWriting.write(data)
          inputPipe.fileHandleForWriting.closeFile()
        }
      } catch is CancellationError {
        continuation.resume(
          returning: .failure(.launchFailed("Editor launch was cancelled."))
        )
      } catch {
        continuation.resume(
          returning: .failure(.launchFailed(String(describing: error)))
        )
      }
    }
  } onCancel: {
    controller.cancel(gracePeriod: terminationGracePeriod)
  }
}

private func resolveLaunchExecutable(
  _ executable: String,
  environment: [String: String]
) -> Result<String, HandoffFailure> {
  guard !executable.contains("/") else {
    return .success(executable)
  }
  guard let path = environment["PATH"], !path.isEmpty else {
    return .failure(
      .launchFailed("Editor executable '\(executable)' was not found because PATH is empty.")
    )
  }

  for component in path.split(separator: ":", omittingEmptySubsequences: false) {
    let directory =
      component.isEmpty
      ? FileManager.default.currentDirectoryPath
      : String(component)
    let candidate = URL(
      fileURLWithPath: directory,
      isDirectory: true
    ).appendingPathComponent(executable).path
    if isExecutableFile(candidate) {
      return .success(candidate)
    }
  }

  return .failure(
    .launchFailed("Editor executable '\(executable)' was not found in PATH.")
  )
}

private func isExecutableFile(_ path: String) -> Bool {
  var info = stat()
  let status = unsafe path.withCString {
    unsafe stat($0, &info)
  }
  guard status == 0,
    UInt32(info.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG)
  else {
    return false
  }
  return unsafe path.withCString {
    unsafe access($0, X_OK) == 0
  }
}

enum ProcessStandardIO: Sendable {
  case discarded
  case terminal
  case fileDescriptor(Int32)
  case input(Data)
}

private final class CancellableProcess: @unchecked Sendable {
  let process = Process()
  private let lock = NSLock()
  private var cancellationRequested = false

  func run() throws {
    lock.lock()
    defer { lock.unlock() }
    guard !cancellationRequested else {
      throw CancellationError()
    }
    try process.run()
  }

  func cancel(gracePeriod: Duration) {
    lock.lock()
    cancellationRequested = true
    let isRunning = process.isRunning
    lock.unlock()
    if isRunning {
      process.terminate()
      Task.detached { [weak self] in
        try? await Task.sleep(for: gracePeriod)
        self?.forceKillIfRunning()
      }
    }
  }

  private func forceKillIfRunning() {
    lock.lock()
    let processIdentifier =
      process.isRunning ? process.processIdentifier : nil
    lock.unlock()
    guard let processIdentifier else {
      return
    }
    _ = kill(processIdentifier, SIGKILL)
  }
}
