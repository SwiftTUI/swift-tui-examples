public import Foundation
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public enum CSVTerminalInputLeaseError: Error, Sendable, LocalizedError {
  case unsupportedPlatform
  case duplicateFailed(Int32)
  case controllingTerminalUnavailable
  case replacementFailed(Int32)
  case restorationFailed(Int32)

  public var errorDescription: String? {
    switch self {
    case .unsupportedPlatform:
      "standard-input documents require a POSIX controlling terminal for interaction"
    case .duplicateFailed(let number): "could not preserve standard input (errno \(number))"
    case .controllingTerminalUnavailable:
      "standard-input documents need an interactive controlling terminal at /dev/tty"
    case .replacementFailed(let number):
      "could not attach terminal input after reading the document (errno \(number))"
    case .restorationFailed(let number): "could not restore standard input (errno \(number))"
    }
  }
}

public final class CSVTerminalInputLease: Sendable {
  #if canImport(Darwin) || canImport(Glibc)
    private struct State {
      var savedStandardInput: Int32
      var isRestored = false
    }

    private let state: Mutex<State>

    public init() throws {
      let duplicate = fcntl(STDIN_FILENO, F_DUPFD_CLOEXEC, 0)
      guard duplicate >= 0 else { throw CSVTerminalInputLeaseError.duplicateFailed(errno) }
      state = Mutex(State(savedStandardInput: duplicate))
    }

    deinit { try? restore() }

    public func activateControllingTerminal() throws {
      let descriptor = unsafe open("/dev/tty", O_RDONLY | O_CLOEXEC)
      if descriptor >= 0 {
        if isatty(STDOUT_FILENO) == 1, !Self.isSameTerminal(descriptor, STDOUT_FILENO) {
          _ = close(descriptor)
          try activate(fileDescriptor: STDOUT_FILENO)
          return
        }
        guard descriptor != STDIN_FILENO else { return }
        defer { _ = close(descriptor) }
        try activate(fileDescriptor: descriptor)
        return
      }
      guard isatty(STDOUT_FILENO) == 1 else {
        throw CSVTerminalInputLeaseError.controllingTerminalUnavailable
      }
      try activate(fileDescriptor: STDOUT_FILENO)
    }

    private static func isSameTerminal(_ lhs: Int32, _ rhs: Int32) -> Bool {
      var lhsStatus = stat()
      var rhsStatus = stat()
      guard unsafe fstat(lhs, &lhsStatus) == 0, unsafe fstat(rhs, &rhsStatus) == 0 else {
        return true
      }
      return lhsStatus.st_dev == rhsStatus.st_dev && lhsStatus.st_rdev == rhsStatus.st_rdev
    }

    func activate(fileDescriptor: Int32) throws {
      guard dup2(fileDescriptor, STDIN_FILENO) >= 0 else {
        throw CSVTerminalInputLeaseError.replacementFailed(errno)
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
          throw CSVTerminalInputLeaseError.restorationFailed(errno)
        }
        $0.isRestored = true
        _ = close($0.savedStandardInput)
      }
    }
  #else
    public init() throws { throw CSVTerminalInputLeaseError.unsupportedPlatform }
    public func activateControllingTerminal() throws {
      throw CSVTerminalInputLeaseError.unsupportedPlatform
    }
    func activate(fileDescriptor: Int32) throws {
      throw CSVTerminalInputLeaseError.unsupportedPlatform
    }
    public func restore() throws {}
  #endif
}
