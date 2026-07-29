import Foundation
import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import Mrkdwn

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private let mrkdwnRealPTYTestsEnabled =
  ProcessInfo.processInfo.environment["MRKDWN_REAL_PTY_TESTS"] != nil
private let mrkdwnRealPTYTestGateComment: Comment =
  "Resource-owning fd test; set MRKDWN_REAL_PTY_TESTS=1 to run."

@Suite(.serialized)
struct TerminalInputLeaseTests {
  @Test("standard-input document reads borrow the caller's handle")
  func standardInputDocumentBorrowsHandle() throws {
    #if canImport(Darwin) || canImport(Glibc)
      let pipe = Pipe()
      let reader = pipe.fileHandleForReading
      defer { try? reader.close() }
      pipe.fileHandleForWriting.write(Data("# borrowed stdin".utf8))
      try pipe.fileHandleForWriting.close()

      let snapshot = try DocumentSource().readStandardInput(reader)

      #expect(snapshot.source == "# borrowed stdin")
      #expect(fcntl(reader.fileDescriptor, F_GETFD) >= 0)
    #else
      Issue.record("Descriptor ownership requires Darwin or Glibc")
    #endif
  }

  @Test(
    "stdin document handoff scopes fd zero and restores it",
    .enabled(if: mrkdwnRealPTYTestsEnabled, mrkdwnRealPTYTestGateComment),
    .timeLimit(.minutes(1))
  )
  func controllingTerminalHandoff() throws {
    #if canImport(Darwin) || canImport(Glibc)
      var before = stat()
      try #require(unsafe fstat(STDIN_FILENO, &before) == 0)
      let pair = try RealTerminalPTYPair.open(
        size: CellSize(width: 80, height: 24)
      )
      defer { pair.close() }
      let lease = try TerminalInputLease()
      defer { try? lease.restore() }
      #expect(lease.preservedStandardInputIsCloseOnExec)

      try lease.activate(fileDescriptor: pair.slave)
      #expect(isatty(STDIN_FILENO) == 1)
      try lease.restore()

      var after = stat()
      #expect(unsafe fstat(STDIN_FILENO, &after) == 0)
      #expect(before.st_dev == after.st_dev)
      #expect(before.st_ino == after.st_ino)
      #expect(before.st_rdev == after.st_rdev)
    #else
      Issue.record("PTY handoff requires Darwin or Glibc")
    #endif
  }
}
