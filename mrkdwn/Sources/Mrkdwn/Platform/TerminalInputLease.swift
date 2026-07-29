public import Foundation
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public enum TerminalInputLeaseError: Error, Sendable, LocalizedError {
  case unsupportedPlatform
  case duplicateFailed(Int32)
  case controllingTerminalUnavailable
  case replacementFailed(Int32)
  case restorationFailed(Int32)

  public var errorDescription: String? {
    switch self {
    case .unsupportedPlatform:
      "standard-input documents require a POSIX controlling terminal for interaction"
    case .duplicateFailed(let errorNumber):
      "could not preserve standard input (errno \(errorNumber))"
    case .controllingTerminalUnavailable:
      "standard-input documents need an interactive controlling terminal at /dev/tty"
    case .replacementFailed(let errorNumber):
      "could not attach terminal input after reading the document (errno \(errorNumber))"
    case .restorationFailed(let errorNumber):
      "could not restore standard input (errno \(errorNumber))"
    }
  }
}

/// Preserves the document pipe, then scopes fd 0 to the controlling terminal
/// while SwiftTUI owns interactive input.
public final class TerminalInputLease: Sendable {
  #if canImport(Darwin) || canImport(Glibc)
    private struct State {
      var savedStandardInput: Int32
      var isRestored = false
    }

    private let state: Mutex<State>

    public init() throws {
      let duplicate = fcntl(STDIN_FILENO, F_DUPFD_CLOEXEC, 0)
      guard duplicate >= 0 else {
        throw TerminalInputLeaseError.duplicateFailed(errno)
      }
      state = Mutex(State(savedStandardInput: duplicate))
    }

    deinit {
      try? restore()
    }

    public func activateControllingTerminal() throws {
      let terminalDescriptor = unsafe open("/dev/tty", O_RDONLY | O_CLOEXEC)
      if terminalDescriptor >= 0 {
        // If the document reader closed fd 0, open(2) may install /dev/tty
        // directly there. In that case ownership has already transferred to
        // standard input; closing a temporary owner would close the terminal
        // again after dup2(0, 0).
        guard terminalDescriptor != STDIN_FILENO else { return }
        defer { _ = close(terminalDescriptor) }
        try activate(fileDescriptor: terminalDescriptor)
        return
      }
      // Foundation's `Process` can attach stdout/stderr to a PTY while fd 0
      // remains the one-shot document pipe without making that PTY the
      // process's controlling terminal. PTY slave descriptors are read/write,
      // so stdout is the correct interactive-input fallback for that launch
      // shape and for embedders that deliberately avoid a session-wide tty.
      guard isatty(STDOUT_FILENO) == 1 else {
        throw TerminalInputLeaseError.controllingTerminalUnavailable
      }
      try activate(fileDescriptor: STDOUT_FILENO)
    }

    func activate(fileDescriptor: Int32) throws {
      guard dup2(fileDescriptor, STDIN_FILENO) >= 0 else {
        throw TerminalInputLeaseError.replacementFailed(errno)
      }
    }

    var preservedStandardInputIsCloseOnExec: Bool {
      state.withLock {
        let flags = fcntl($0.savedStandardInput, F_GETFD)
        return flags >= 0 && flags & FD_CLOEXEC != 0
      }
    }

    public func restore() throws {
      try state.withLock {
        guard !$0.isRestored else { return }
        guard dup2($0.savedStandardInput, STDIN_FILENO) >= 0 else {
          throw TerminalInputLeaseError.restorationFailed(errno)
        }
        $0.isRestored = true
        _ = close($0.savedStandardInput)
      }
    }
  #else
    public init() throws {
      throw TerminalInputLeaseError.unsupportedPlatform
    }

    public func activateControllingTerminal() throws {
      throw TerminalInputLeaseError.unsupportedPlatform
    }

    func activate(fileDescriptor: Int32) throws {
      throw TerminalInputLeaseError.unsupportedPlatform
    }

    public func restore() throws {}
  #endif
}
