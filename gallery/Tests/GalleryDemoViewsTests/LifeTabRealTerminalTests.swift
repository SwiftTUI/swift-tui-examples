import Dispatch
import Foundation
@_spi(Runners) @_spi(Testing) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import GalleryDemoViews
@testable import SwiftTUICore
@testable import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

// Real-terminal (PTY) drilldown for the "Life tab freezes" user report, run in
// the production `.async` render mode:
//
//   1. the auto-tick animation sometimes never starts on entry, and the tab
//      cannot be left afterwards;
//   2. after switching away and back, the tab renders but never ticks again.
//
// The deterministic sync-harness sibling (`LifeTabRevisitTests`) passes, so
// the failure needs real wall-clock task scheduling and async frame delivery
// to reproduce.
@MainActor
@Suite(.serialized)
struct LifeTabRealTerminalTests {
  @Test(
    "real terminal Life tab ticks, survives leaving, and resumes on revisit",
    .enabled(if: galleryRuntimeTestsEnabled, galleryRuntimeTestGateComment))
  func lifeTabTicksAndResumesAcrossRevisit() async throws {
    let terminalSize = CellSize(width: 120, height: 40)
    let rootIdentity = Identity(components: [.named("GalleryLifeRealTerminalRevisit")])
    let pty = try #require(Self.makePseudoTerminal(size: terminalSize))
    defer {
      _ = close(pty.master)
      _ = close(pty.slave)
    }

    let host = TerminalHost(
      inputFileDescriptor: pty.slave,
      outputFileDescriptor: pty.slave,
      fallbackSize: terminalSize,
      capabilityProfile: .previewUnicode
    )
    let inputReader = InputReader(fileDescriptor: pty.slave)

    let runTask = Task {
      try await Self.runHarness(
        presentationSurface: host,
        terminalInputReader: inputReader,
        terminalSize: terminalSize,
        rootIdentity: rootIdentity,
        viewBuilder: { GalleryView(initialTab: .life) }
      )
    }

    var screen = PTYVisibleScreen(size: terminalSize)

    // Leg 1 — the auto-tick loop must start: `gen` advances past its seed.
    let tickingScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("Conway's Life") && (Self.generation(in: rendered) ?? 0) >= 2
    }
    #expect(
      tickingScreen.contains("Conway's Life"),
      "expected the Life tab to render and tick; screen was:\n\(tickingScreen)"
    )

    // Leg 2 — leaving the tab must work while (or after) it animates.
    let counterCenter = try #require(
      Self.centerOfText("Counter", in: tickingScreen),
      "could not locate the Counter tab label; screen was:\n\(tickingScreen)"
    )
    try Self.writeAllBytes(Self.sgrPrimaryClick(at: counterCenter), to: pty.master)
    let counterScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("A SwiftUI-shaped terminal UI")
    }
    #expect(
      counterScreen.contains("A SwiftUI-shaped terminal UI"),
      "expected the Counter tab after clicking it; screen was:\n\(counterScreen)"
    )

    // Leg 3 — returning must resume ticking (fresh or continued, but alive).
    let lifeCenter = try #require(
      Self.centerOfText("Life", in: counterScreen),
      "could not locate the Life tab label; screen was:\n\(counterScreen)"
    )
    try Self.writeAllBytes(Self.sgrPrimaryClick(at: lifeCenter), to: pty.master)
    let revisitScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("Conway's Life")
    }
    let revisitGeneration = Self.generation(in: revisitScreen) ?? -1

    let resumedScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      guard rendered.contains("Conway's Life"),
        let generation = Self.generation(in: rendered)
      else {
        return false
      }
      return generation != revisitGeneration && generation >= 1
    }
    let resumedGeneration = Self.generation(in: resumedScreen)
    #expect(
      resumedGeneration != nil && resumedGeneration != revisitGeneration,
      """
      expected the Life tab to resume ticking after revisit (was gen \
      \(revisitGeneration)); screen was:\n\(resumedScreen)
      """
    )

    _ = close(pty.master)
    _ = try await runTask.value
  }

  // MARK: - Screen parsing

  private static func generation(in rendered: String) -> Int? {
    guard let range = rendered.range(of: "gen ") else { return nil }
    let digits = rendered[range.upperBound...].prefix(while: \.isNumber)
    guard !digits.isEmpty else { return nil }
    return Int(digits)
  }

  private static func centerOfText(_ target: String, in rendered: String) -> Point? {
    for (row, line) in rendered.split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
    {
      guard let range = line.range(of: target) else { continue }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }

  // MARK: - Harness (mirrors GalleryTabSwitchTests, production async mode)

  @MainActor
  private static func runHarness<V: View>(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    terminalSize: CellSize,
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: LifeRealTerminalEmptySignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: env,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder() }
    )
    // Production default: exercise the async frame tail the user actually runs.
    runLoop.renderMode = .async
    return try await runLoop.run()
  }

  // MARK: - PTY plumbing (mirrors GalleryTabSwitchTests)

  private static func makePseudoTerminal(
    size: CellSize
  ) -> (master: Int32, slave: Int32)? {
    var master: Int32 = -1
    var slave: Int32 = -1
    var windowSize = winsize(
      ws_row: UInt16(max(1, size.height)),
      ws_col: UInt16(max(1, size.width)),
      ws_xpixel: 0,
      ws_ypixel: 0
    )

    guard openpty(&master, &slave, nil, nil, &windowSize) == 0 else {
      return nil
    }

    let currentFlags = fcntl(master, F_GETFL)
    guard currentFlags >= 0 else {
      _ = close(master)
      _ = close(slave)
      return nil
    }
    guard fcntl(master, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
      _ = close(master)
      _ = close(slave)
      return nil
    }

    return (master, slave)
  }

  private static func writeAllBytes(
    _ bytes: [UInt8],
    to fileDescriptor: Int32
  ) throws {
    var totalBytesWritten = 0

    try unsafe bytes.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else {
        return
      }

      while totalBytesWritten < bytes.count {
        let nextAddress = unsafe baseAddress.advanced(by: totalBytesWritten)
        let bytesRemaining = bytes.count - totalBytesWritten
        let bytesWritten = unsafe write(fileDescriptor, nextAddress, bytesRemaining)
        guard bytesWritten >= 0 else {
          throw TerminalHostError.failedToWrite(errno: errno)
        }
        totalBytesWritten += bytesWritten
      }
    }
  }

  private static func sgrPrimaryClick(at point: Point) -> [UInt8] {
    sgrMouse(encodedButton: 0, terminator: "M", at: point)
      + sgrMouse(encodedButton: 0, terminator: "m", at: point)
  }

  private static func sgrMouse(
    encodedButton: Int,
    terminator: String,
    at point: Point
  ) -> [UInt8] {
    let cell = point.containingCell
    return Array(
      "\u{001B}[<\(encodedButton);\(cell.x + 1);\(cell.y + 1)\(terminator)".utf8
    )
  }

  private enum ScreenWaitError: Error, CustomStringConvertible {
    case timedOut(rendered: String)

    var description: String {
      switch self {
      case .timedOut(let rendered):
        "Timed out waiting for screen condition; last screen was:\n\(rendered)"
      }
    }
  }

  private static func waitForScreen(
    on fileDescriptor: Int32,
    screen: inout PTYVisibleScreen,
    condition: (String) -> Bool
  ) async throws -> String {
    var rendered = screen.renderedText
    let initial = try readAvailableBytes(from: fileDescriptor)
    if !initial.bytes.isEmpty {
      screen.feed(initial.bytes)
      rendered = screen.renderedText
    }
    if condition(rendered) {
      return rendered
    }

    let readable = LifeRealTerminalPTYReadableSource(fileDescriptor: fileDescriptor)
    var outcome: Result<String, any Error> = .failure(
      ScreenWaitError.timedOut(rendered: rendered)
    )
    for await _ in readable.events {
      let next: (bytes: [UInt8], reachedEOF: Bool)
      do {
        next = try readAvailableBytes(from: fileDescriptor)
      } catch {
        outcome = .failure(error)
        break
      }
      if !next.bytes.isEmpty {
        screen.feed(next.bytes)
        rendered = screen.renderedText
      }
      if condition(rendered) {
        outcome = .success(rendered)
        break
      }
      if next.reachedEOF {
        outcome = .failure(ScreenWaitError.timedOut(rendered: rendered))
        break
      }
    }
    await readable.cancel()
    return try outcome.get()
  }

  private static func readAvailableBytes(
    from fileDescriptor: Int32
  ) throws -> (bytes: [UInt8], reachedEOF: Bool) {
    var collected: [UInt8] = []

    while true {
      var buffer = Array(repeating: UInt8(0), count: 4096)
      let bytesRead = unsafe read(fileDescriptor, &buffer, buffer.count)

      if bytesRead > 0 {
        collected.append(contentsOf: buffer.prefix(Int(bytesRead)))
        continue
      }

      if bytesRead == 0 {
        return (collected, true)
      }

      if errno == EAGAIN || errno == EWOULDBLOCK {
        return (collected, false)
      }

      throw TerminalHostError.failedToReadWindowSize(errno: errno)
    }
  }
}

private final class LifeRealTerminalEmptySignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

/// A `DispatchSource`-backed "the PTY has bytes" signal, with a wall-clock
/// safety net so a wait can never hang the suite. Mirrors
/// `GalleryTabSwitchTests.PTYReadableSource`.
private final class LifeRealTerminalPTYReadableSource {
  let events: AsyncStream<Void>
  private let source: any DispatchSourceRead
  private let cancelled = AsyncEvent()

  init(fileDescriptor: Int32, timeoutNanoseconds: UInt64 = 15_000_000_000) {
    let queue = DispatchQueue(label: "LifeTabRealTerminalTests.ptyReadable")
    let source = DispatchSource.makeReadSource(
      fileDescriptor: fileDescriptor,
      queue: queue
    )
    self.source = source

    var streamContinuation: AsyncStream<Void>.Continuation!
    events = AsyncStream<Void> { streamContinuation = $0 }
    let continuation = streamContinuation!
    let cancelledEvent = cancelled

    source.setEventHandler {
      continuation.yield(())
    }
    source.setCancelHandler {
      continuation.finish()
      cancelledEvent.fire()
    }
    source.resume()

    queue.asyncAfter(deadline: .now() + .nanoseconds(Int(timeoutNanoseconds))) {
      source.cancel()
    }
  }

  func cancel() async {
    source.cancel()
    await cancelled.wait()
  }
}

/// Minimal visible-screen model fed from raw PTY bytes. Mirrors
/// `GalleryTabSwitchTests.PTYVisibleScreen` (kept file-private there).
private struct PTYVisibleScreen {
  private var size: CellSize
  private var cells: [[Character]]
  private var cursor = CellPoint.zero
  private var pendingBytes: [UInt8] = []

  init(size: CellSize) {
    self.size = size
    cells = Array(
      repeating: Array(repeating: " ", count: max(1, size.width)),
      count: max(1, size.height)
    )
  }

  var renderedText: String {
    cells
      .map { row in
        var endIndex = row.endIndex
        while endIndex > row.startIndex, row[row.index(before: endIndex)] == " " {
          endIndex = row.index(before: endIndex)
        }
        return String(row[..<endIndex])
      }
      .joined(separator: "\n")
  }

  mutating func feed(_ bytes: [UInt8]) {
    pendingBytes.append(contentsOf: bytes)

    var index = 0
    while index < pendingBytes.count {
      let byte = pendingBytes[index]

      if byte == 0x1B {
        guard index + 1 < pendingBytes.count else {
          break
        }

        let next = pendingBytes[index + 1]
        if next == 0x5B {
          guard let consumed = consumeCSI(startingAt: index) else {
            break
          }
          index = consumed
          continue
        }

        if next == 0x5D || next == 0x5F {
          guard let consumed = consumeStringEscape(startingAt: index) else {
            break
          }
          index = consumed
          continue
        }

        index += 2
        continue
      }

      if byte == 0x0D {
        cursor.x = 0
        index += 1
        continue
      }

      if byte == 0x0A {
        cursor.x = 0
        cursor.y = min(max(0, size.height - 1), cursor.y + 1)
        index += 1
        continue
      }

      if byte < 0x20 {
        index += 1
        continue
      }

      if byte < 0x80 {
        write(Character(UnicodeScalar(Int(byte))!))
        index += 1
        continue
      }

      let sequenceLength = utf8SequenceLength(for: byte)
      guard index + sequenceLength <= pendingBytes.count else {
        break
      }
      let character =
        String(
          decoding: pendingBytes[index..<(index + sequenceLength)],
          as: UTF8.self
        ).first ?? "•"
      write(character)
      index += sequenceLength
    }

    if index > 0 {
      pendingBytes.removeFirst(index)
    }
  }

  private mutating func consumeCSI(startingAt startIndex: Int) -> Int? {
    var index = startIndex + 2
    while index < pendingBytes.count {
      let byte = pendingBytes[index]
      if (0x40...0x7E).contains(byte) {
        let parameters = Array(pendingBytes[(startIndex + 2)..<index])
        applyCSI(parameters: parameters, command: byte)
        return index + 1
      }
      index += 1
    }
    return nil
  }

  private mutating func consumeStringEscape(startingAt startIndex: Int) -> Int? {
    var index = startIndex + 2
    while index + 1 < pendingBytes.count {
      if pendingBytes[index] == 0x1B, pendingBytes[index + 1] == 0x5C {
        return index + 2
      }
      if pendingBytes[index] == 0x07 {
        return index + 1
      }
      index += 1
    }
    return nil
  }

  private mutating func applyCSI(parameters: [UInt8], command: UInt8) {
    let parameterString = String(decoding: parameters, as: UTF8.self)
    let privateMode = parameterString.hasPrefix("?")
    let cleanedParameters =
      privateMode
      ? String(parameterString.dropFirst())
      : parameterString
    let values = cleanedParameters.split(separator: ";").compactMap { Int($0) }

    switch command {
    case 0x48, 0x66:  // H, f
      let row = max(1, values.first ?? 1) - 1
      let column = max(1, values.dropFirst().first ?? 1) - 1
      cursor = CellPoint(
        x: min(max(0, size.width - 1), column),
        y: min(max(0, size.height - 1), row)
      )
    case 0x4A:  // J
      if values.first == 2 || values.isEmpty {
        clearAll()
      }
    case 0x4B:  // K
      eraseToEndOfLine()
    case 0x43:  // C
      cursor.x = min(max(0, size.width - 1), cursor.x + max(1, values.first ?? 1))
    case 0x44:  // D
      cursor.x = max(0, cursor.x - max(1, values.first ?? 1))
    case 0x41:  // A
      cursor.y = max(0, cursor.y - max(1, values.first ?? 1))
    case 0x42:  // B
      cursor.y = min(max(0, size.height - 1), cursor.y + max(1, values.first ?? 1))
    case 0x47:  // G
      cursor.x = min(max(0, size.width - 1), max(1, values.first ?? 1) - 1)
    case 0x6D, 0x68, 0x6C:  // m, h, l
      return
    default:
      return
    }
  }

  private mutating func clearAll() {
    for row in cells.indices {
      for column in cells[row].indices {
        cells[row][column] = " "
      }
    }
    cursor = .zero
  }

  private mutating func eraseToEndOfLine() {
    guard cursor.y >= 0, cursor.y < cells.count else {
      return
    }
    let row = cursor.y
    guard cursor.x >= 0, cursor.x < cells[row].count else {
      return
    }
    for column in cursor.x..<cells[row].count {
      cells[row][column] = " "
    }
  }

  private mutating func write(_ character: Character) {
    guard cursor.y >= 0, cursor.y < cells.count else {
      return
    }
    guard cursor.x >= 0, cursor.x < cells[cursor.y].count else {
      return
    }
    cells[cursor.y][cursor.x] = character
    cursor.x += 1
  }

  private func utf8SequenceLength(for byte: UInt8) -> Int {
    switch byte {
    case 0xC0...0xDF:
      2
    case 0xE0...0xEF:
      3
    case 0xF0...0xF7:
      4
    default:
      1
    }
  }
}
