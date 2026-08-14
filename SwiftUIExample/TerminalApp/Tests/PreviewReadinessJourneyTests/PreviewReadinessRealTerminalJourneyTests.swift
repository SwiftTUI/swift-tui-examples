import Dispatch
import Foundation
import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import Testing

#if canImport(CoreGraphics) && canImport(ImageIO)
  import CoreGraphics
  import ImageIO
#endif

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private let terminalJourneyEnabled =
  ProcessInfo.processInfo.environment["SWIFTTUI_PREVIEW_READINESS_TERMINAL_JOURNEY"] == "1"
private let terminalJourneyComment: Comment =
  "Real executable/PTY journey; run Scripts/run_preview_readiness_terminal_journey.sh."

@MainActor
@Suite(.serialized)
struct PreviewReadinessRealTerminalJourneyTests {
  @Test(
    "external package terminal covers editing, dormant tabs, completion criteria, and image alpha",
    .enabled(if: terminalJourneyEnabled, terminalJourneyComment),
    .timeLimit(.minutes(2))
  )
  func previewReadinessJourney() async throws {
    let size = CellSize(width: 96, height: 40)
    let terminal = try RealTerminalPTYPair.open(size: size)
    defer { terminal.close() }
    let process = try launchPreviewExecutable(terminal: terminal)

    var probe = TerminalProbe(size: size)
    do {
      let initial = try await probe.wait(
        on: terminal.master,
        deadline: .now() + .seconds(20),
        replyOn: terminal.master
      ) {
        $0.contains("Preview readiness host journey")
          && $0.contains("Editor state: seed")
      }
      #expect(initial.contains("Geometry cells:"))

      // The authored default focus is visible on launch. The explicit pointer
      // click then exercises the terminal host's input route before editing.
      try click("seed", in: initial, terminal: terminal)
      try writeAllBytes(Array("-terminal".utf8), to: terminal.master)
      let edited = try await probe.wait(
        on: terminal.master,
        deadline: .now() + .seconds(10),
        replyOn: terminal.master
      ) { $0.contains("Editor state:") && $0.contains("terminal") }

      // Pointer dispatch increments real state on the focused tab.
      try click("Pointer count: 0", in: edited, terminal: terminal)
      let incremented = try await probe.wait(
        on: terminal.master,
        deadline: .now() + .seconds(10),
        replyOn: terminal.master
      ) { $0.contains("Pointer count: 1") }

      // An authored button drives the real TabView selection through ordinary
      // pointer dispatch. The dormant branch releases active output while its
      // graph-owned state remains scoped to the TabView.
      try click("Show evidence", in: incremented, terminal: terminal)
      let evidence = try await probe.wait(
        on: terminal.master,
        deadline: .now() + .seconds(10),
        replyOn: terminal.master
      ) {
        $0.contains("Half-opacity red image on blue")
      }

      // Decode the production Kitty transfer itself. A format marker alone
      // cannot prove that opacity was applied, so the center pixel must carry
      // both the red image and blue backdrop contributions.
      _ = try await probe.waitForBytes(
        on: terminal.master,
        deadline: .now() + .seconds(10),
        replyOn: terminal.master
      ) { hasCompleteKittyTransfer(in: $0) }
      let imagePixel = try kittyTransferCenterPixel(in: probe.bytes)
      #expect(Int(imagePixel.red) > Int(imagePixel.green) + 35)
      #expect(Int(imagePixel.blue) > Int(imagePixel.green) + 35)
      #expect(abs(Int(imagePixel.red) - Int(imagePixel.blue)) < 90)
      #expect(imagePixel.alpha > 220)

      try click("Show editor", in: evidence, terminal: terminal)
      let restored = try await probe.wait(
        on: terminal.master,
        deadline: .now() + .seconds(10),
        replyOn: terminal.master
      ) {
        $0.contains("Editor state:") && $0.contains("terminal")
          && $0.contains("Pointer count: 1")
      }

      // Exercise both public completion barriers after dormant state has been
      // restored so each count remains an independent observable outcome.
      try click("Run logical completion", in: restored, terminal: terminal)
      let logical = try await probe.wait(
        on: terminal.master,
        deadline: .now() + .seconds(10),
        replyOn: terminal.master
      ) { $0.contains("Completion counts: logical 1, removed 0") }

      try click("Run removed completion", in: logical, terminal: terminal)
      let removed = try await probe.wait(
        on: terminal.master,
        deadline: .now() + .seconds(10),
        replyOn: terminal.master
      ) { $0.contains("Completion counts: logical 1, removed 1") }

      _ = removed
      try await terminateAndReap(process, terminal: terminal)
    } catch let journeyError {
      do {
        try await terminateAndReap(process, terminal: terminal)
      } catch let teardownError {
        throw JourneyFailure.teardownFailed(
          journey: String(describing: journeyError),
          teardown: String(describing: teardownError)
        )
      }
      throw journeyError
    }
  }

  private func click(
    _ label: String,
    probe: inout TerminalProbe,
    terminal: RealTerminalPTYPair
  ) throws {
    try click(label, in: probe.screen.renderedText, terminal: terminal)
  }

  private func click(
    _ label: String,
    in rendered: String,
    terminal: RealTerminalPTYPair
  ) throws {
    let point = try #require(center(of: label, in: rendered))
    let cell = point.containingCell
    let down = "\u{001B}[<0;\(cell.x + 1);\(cell.y + 1)M"
    let up = "\u{001B}[<0;\(cell.x + 1);\(cell.y + 1)m"
    try writeAllBytes(Array((down + up).utf8), to: terminal.master)
  }

  private func center(of label: String, in rendered: String) -> Point? {
    for (row, line) in rendered.split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
    {
      guard let range = line.range(of: label) else { continue }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + label.count / 2, y: row))
    }
    return nil
  }
}

@Suite
struct KittyTransferParserTests {
  @Test("chunked Kitty RGBA transfers are reassembled before pixel sampling")
  func chunkedRGBA() throws {
    let rgba: [UInt8] = [
      10, 20, 30, 255,
      128, 0, 127, 255,
    ]
    let encoded = Data(rgba).base64EncodedString()
    let split = encoded.index(encoded.startIndex, offsetBy: 4)
    let output =
      "prefix\u{001B}_Ga=T,q=2,t=d,f=32,s=2,v=1,m=1;\(encoded[..<split])\u{001B}\\"
      + "\u{001B}_Gm=0;\(encoded[split...])\u{001B}\\suffix"

    #expect(hasCompleteKittyTransfer(in: Array(output.utf8)))
    let pixel = try kittyTransferCenterPixel(in: Array(output.utf8))
    #expect(pixel.red == 128)
    #expect(pixel.green == 0)
    #expect(pixel.blue == 127)
    #expect(pixel.alpha == 255)
  }

  @Test("unfinished Kitty transfer is not accepted as pixel evidence")
  func incompleteTransfer() {
    let output = "\u{001B}_Ga=T,q=2,t=d,f=32,s=1,v=1,m=1;AAAA\u{001B}\\"
    #expect(!hasCompleteKittyTransfer(in: Array(output.utf8)))
  }
}

private enum JourneyFailure: Error, CustomStringConvertible {
  case executableNotFound(String)
  case processTimedOut
  case signalFailed(signal: Int32, errno: Int32)
  case signalEscalationFailed(termErrno: Int32, killErrno: Int32)
  case teardownFailed(journey: String, teardown: String)

  var description: String {
    switch self {
    case .executableNotFound(let path):
      "Preview-readiness executable was not found below \(path)"
    case .processTimedOut:
      "Preview-readiness process did not exit before the deadline"
    case .signalFailed(let signal, let errorNumber):
      "Sending signal \(signal) failed with errno \(errorNumber)"
    case .signalEscalationFailed(let termErrno, let killErrno):
      "Sending SIGTERM failed with errno \(termErrno), and SIGKILL escalation failed with errno \(killErrno)"
    case .teardownFailed(let journey, let teardown):
      "Journey failed with \(journey); child teardown also failed with \(teardown)"
    }
  }
}

@MainActor
private func launchPreviewExecutable(terminal: RealTerminalPTYPair) throws -> Process {
  let executable = try previewExecutableURL()
  let process = Process()
  process.executableURL = executable
  var environment = ProcessInfo.processInfo.environment
  environment["TERM"] = "xterm-kitty"
  environment["TERM_PROGRAM"] = "kitty"
  environment["LANG"] = "en_US.UTF-8"
  environment["LC_ALL"] = "en_US.UTF-8"
  environment["SWIFTTUI_KITTY_KEYBOARD"] = "0"
  process.environment = environment
  let handle = FileHandle(fileDescriptor: terminal.slave, closeOnDealloc: false)
  process.standardInput = handle
  process.standardOutput = handle
  process.standardError = handle
  try process.run()
  return process
}

private func previewExecutableURL() throws -> URL {
  if let explicit = ProcessInfo.processInfo.environment[
    "SWIFTTUI_PREVIEW_READINESS_TERMINAL_EXECUTABLE"
  ] {
    let url = URL(fileURLWithPath: explicit)
    if FileManager.default.isExecutableFile(atPath: url.path) { return url }
  }

  let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)
  let platformDirectories =
    (try? FileManager.default.contentsOfDirectory(
      at: buildRoot,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []
  for directory in platformDirectories {
    let candidate =
      directory
      .appendingPathComponent("debug")
      .appendingPathComponent("preview-readiness-terminal")
    if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
  }
  throw JourneyFailure.executableNotFound(buildRoot.path)
}

private struct TerminalProbe {
  private static let capturedByteBudget = 256 * 1_024
  private static let diagnosticTailBudget = 512

  var screen: ANSIVisibleScreen
  private(set) var bytes: [UInt8] = []
  private var totalByteCount = 0
  private var diagnosticTail: [UInt8] = []
  private var repliedToKitty = false
  private var repliedToPixels = false

  init(size: CellSize) {
    screen = ANSIVisibleScreen(size: size)
  }

  @MainActor
  mutating func wait(
    on fileDescriptor: Int32,
    deadline: DispatchTime,
    replyOn inputFileDescriptor: Int32,
    condition: (String) -> Bool
  ) async throws -> String {
    if condition(screen.renderedText) { return screen.renderedText }
    while DispatchTime.now() < deadline {
      if try readAndRecord(from: fileDescriptor, replyOn: inputFileDescriptor),
        condition(screen.renderedText)
      {
        return screen.renderedText
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw TerminalProbeFailure.timedOut(
      rendered: screen.renderedText,
      byteCount: totalByteCount,
      tail: diagnosticTail
    )
  }

  @MainActor
  mutating func waitForBytes(
    on fileDescriptor: Int32,
    deadline: DispatchTime,
    replyOn inputFileDescriptor: Int32,
    condition: ([UInt8]) -> Bool
  ) async throws -> [UInt8] {
    if condition(bytes) { return bytes }
    while DispatchTime.now() < deadline {
      if try readAndRecord(from: fileDescriptor, replyOn: inputFileDescriptor),
        condition(bytes)
      {
        return bytes
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw TerminalProbeFailure.timedOut(
      rendered: screen.renderedText,
      byteCount: totalByteCount,
      tail: diagnosticTail
    )
  }

  private mutating func readAndRecord(
    from fileDescriptor: Int32,
    replyOn inputFileDescriptor: Int32
  ) throws -> Bool {
    var chunk = [UInt8](repeating: 0, count: 16_384)
    let count = unsafe read(fileDescriptor, &chunk, chunk.count)
    if count > 0 {
      chunk.removeSubrange(Int(count)..<chunk.count)
      record(chunk)
      screen.feed(chunk)
      try respondToCapabilityQueries(on: inputFileDescriptor)
      return true
    }
    if count == 0 {
      throw TerminalProbeFailure.reachedEndOfFile(
        rendered: screen.renderedText,
        byteCount: totalByteCount,
        tail: diagnosticTail
      )
    }
    if errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR {
      throw RealTerminalJourneyError.operationFailed(operation: "read", errno: errno)
    }
    return false
  }

  private mutating func record(_ chunk: [UInt8]) {
    totalByteCount += chunk.count
    bytes.append(contentsOf: chunk)
    if bytes.count > Self.capturedByteBudget {
      bytes.removeFirst(bytes.count - Self.capturedByteBudget)
    }
    diagnosticTail.append(contentsOf: chunk)
    if diagnosticTail.count > Self.diagnosticTailBudget {
      diagnosticTail.removeFirst(diagnosticTail.count - Self.diagnosticTailBudget)
    }
  }

  private mutating func respondToCapabilityQueries(on fileDescriptor: Int32) throws {
    let text = String(decoding: bytes.suffix(8_192), as: UTF8.self)
    if !repliedToKitty,
      let query = text.range(of: "\u{001B}_Gi="),
      let delimiter = text[query.upperBound...].firstIndex(of: ",")
    {
      let id = text[query.upperBound..<delimiter]
      let response = "\u{001B}_Gi=\(id);OK\u{001B}\\\u{001B}[?1;2c"
      try writeAllBytes(Array(response.utf8), to: fileDescriptor)
      repliedToKitty = true
    }
    if !repliedToPixels, text.contains("\u{001B}[16t") {
      try writeAllBytes(Array("\u{001B}[6;16;8t".utf8), to: fileDescriptor)
      repliedToPixels = true
    }
  }
}

private enum TerminalProbeFailure: Error, CustomStringConvertible {
  case reachedEndOfFile(rendered: String, byteCount: Int, tail: [UInt8])
  case timedOut(rendered: String, byteCount: Int, tail: [UInt8])

  var description: String {
    switch self {
    case .reachedEndOfFile(let rendered, let byteCount, let tail):
      "PTY reached end of file after \(byteCount) bytes. Tail: \(escaped(tail))\n"
        + "Last screen:\n\(rendered)"
    case .timedOut(let rendered, let byteCount, let tail):
      "PTY wait timed out after \(byteCount) bytes. Tail: \(escaped(tail))\n"
        + "Last screen:\n\(rendered)"
    }
  }

  private func escaped(_ bytes: [UInt8]) -> String {
    var result = ""
    for byte in bytes {
      switch byte {
      case 0x1B: result += "\\e"
      case 0x0A: result += "\\n"
      case 0x0D: result += "\\r"
      case 0x09: result += "\\t"
      case 0x5C: result += "\\\\"
      case 0x20...0x7E: result.append(Character(UnicodeScalar(byte)))
      default: result += "\\x" + String(byte, radix: 16, uppercase: true)
      }
    }
    return result
  }
}

private struct RGBABytePixel {
  let red: UInt8
  let green: UInt8
  let blue: UInt8
  let alpha: UInt8
}

private enum KittyTransferFailure: Error, CustomStringConvertible {
  case missingTransfer
  case incompleteTransfer
  case malformedControlData
  case malformedPayload
  case unsupportedFormat(String)
  case pngDecodingUnavailable

  var description: String {
    switch self {
    case .missingTransfer:
      "No Kitty transmit-and-display command was captured"
    case .incompleteTransfer:
      "The Kitty transmit-and-display command was incomplete"
    case .malformedControlData:
      "The Kitty transfer control data was malformed"
    case .malformedPayload:
      "The Kitty transfer payload did not match its declared format"
    case .unsupportedFormat(let format):
      "Unsupported Kitty transfer pixel format \(format)"
    case .pngDecodingUnavailable:
      "PNG decoding is unavailable on this test platform"
    }
  }
}

private func kittyTransferCenterPixel(in bytes: [UInt8]) throws -> RGBABytePixel {
  let transfer = try kittyTransfer(in: bytes)
  guard
    let payload = Data(base64Encoded: transfer.encodedPayload),
    let format = transfer.attributes["f"]
  else {
    throw KittyTransferFailure.malformedPayload
  }

  switch format {
  case "100":
    return try decodedPNGCenterPixel(payload)
  case "32":
    guard
      let widthText = transfer.attributes["s"],
      let heightText = transfer.attributes["v"],
      let width = Int(widthText),
      let height = Int(heightText),
      width > 0,
      height > 0
    else {
      throw KittyTransferFailure.malformedControlData
    }
    let index = ((height / 2) * width + (width / 2)) * 4
    guard index + 3 < payload.count else {
      throw KittyTransferFailure.malformedPayload
    }
    return payload.withUnsafeBytes { buffer in
      RGBABytePixel(
        red: buffer[index],
        green: buffer[index + 1],
        blue: buffer[index + 2],
        alpha: buffer[index + 3]
      )
    }
  case "24":
    guard
      let widthText = transfer.attributes["s"],
      let heightText = transfer.attributes["v"],
      let width = Int(widthText),
      let height = Int(heightText),
      width > 0,
      height > 0
    else {
      throw KittyTransferFailure.malformedControlData
    }
    let index = ((height / 2) * width + (width / 2)) * 3
    guard index + 2 < payload.count else {
      throw KittyTransferFailure.malformedPayload
    }
    return payload.withUnsafeBytes { buffer in
      RGBABytePixel(
        red: buffer[index],
        green: buffer[index + 1],
        blue: buffer[index + 2],
        alpha: 255
      )
    }
  default:
    throw KittyTransferFailure.unsupportedFormat(format)
  }
}

private struct CapturedKittyTransfer {
  let attributes: [String: String]
  let encodedPayload: String
}

private struct CapturedKittyCommand {
  let attributes: [String: String]
  let payload: Substring
  let endIndex: String.Index
}

private func hasCompleteKittyTransfer(in bytes: [UInt8]) -> Bool {
  (try? kittyTransfer(in: bytes)) != nil
}

private func kittyTransfer(in bytes: [UInt8]) throws -> CapturedKittyTransfer {
  let output = String(decoding: bytes, as: UTF8.self)
  guard let marker = output.range(of: "\u{001B}_Ga=T,") else {
    throw KittyTransferFailure.missingTransfer
  }

  var command = try kittyCommand(in: output, startingAt: marker.lowerBound)
  var payload = String(command.payload)
  let transferAttributes = command.attributes
  var hasMore = command.attributes["m"]

  while hasMore == "1" {
    guard
      let continuation = output.range(
        of: "\u{001B}_G",
        range: command.endIndex..<output.endIndex
      )
    else {
      throw KittyTransferFailure.incompleteTransfer
    }
    command = try kittyCommand(in: output, startingAt: continuation.lowerBound)
    guard command.attributes["a"] == nil else {
      throw KittyTransferFailure.malformedControlData
    }
    payload += String(command.payload)
    hasMore = command.attributes["m"]
  }

  guard hasMore == "0" else {
    throw KittyTransferFailure.malformedControlData
  }
  return CapturedKittyTransfer(
    attributes: transferAttributes,
    encodedPayload: payload
  )
}

private func kittyCommand(
  in output: String,
  startingAt start: String.Index
) throws -> CapturedKittyCommand {
  let controlStart = output.index(start, offsetBy: 3)
  guard
    let terminator = output.range(
      of: "\u{001B}\\",
      range: controlStart..<output.endIndex
    )
  else {
    throw KittyTransferFailure.incompleteTransfer
  }
  guard
    let separator = output[controlStart..<terminator.lowerBound].firstIndex(of: ";")
  else {
    throw KittyTransferFailure.malformedControlData
  }

  let attributePairs: [(String, String)] = output[controlStart..<separator]
    .split(separator: ",")
    .compactMap { field -> (String, String)? in
      let parts = field.split(
        separator: "=",
        maxSplits: 1,
        omittingEmptySubsequences: false
      )
      guard parts.count == 2 else { return nil }
      return (String(parts[0]), String(parts[1]))
    }
  guard attributePairs.count == output[controlStart..<separator].split(separator: ",").count
  else {
    throw KittyTransferFailure.malformedControlData
  }

  return CapturedKittyCommand(
    attributes: Dictionary(uniqueKeysWithValues: attributePairs),
    payload: output[output.index(after: separator)..<terminator.lowerBound],
    endIndex: terminator.upperBound
  )
}

private func decodedPNGCenterPixel(_ data: Data) throws -> RGBABytePixel {
  #if canImport(CoreGraphics) && canImport(ImageIO)
    guard
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw KittyTransferFailure.malformedPayload
    }

    var pixel = [UInt8](repeating: 0, count: 4)
    return try pixel.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: 1,
          height: 1,
          bitsPerComponent: 8,
          bytesPerRow: 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else {
        throw KittyTransferFailure.malformedPayload
      }
      context.interpolationQuality = .none
      context.draw(
        image,
        in: CGRect(
          x: 0.5 - CGFloat(image.width) / 2,
          y: 0.5 - CGFloat(image.height) / 2,
          width: CGFloat(image.width),
          height: CGFloat(image.height)
        )
      )
      return RGBABytePixel(
        red: buffer[0],
        green: buffer[1],
        blue: buffer[2],
        alpha: buffer[3]
      )
    }
  #else
    throw KittyTransferFailure.pngDecodingUnavailable
  #endif
}

@MainActor
private func waitForExit(_ process: Process, timeout: Duration) async throws -> Int32 {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while process.isRunning, clock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  guard !process.isRunning else { throw JourneyFailure.processTimedOut }
  return process.terminationStatus
}

@MainActor
private func terminateAndReap(
  _ process: Process,
  terminal: RealTerminalPTYPair
) async throws {
  guard process.isRunning else { return }

  let processID = process.processIdentifier
  let terminateResult = kill(processID, SIGTERM)
  let terminateErrno = errno
  let terminateFailure =
    terminateResult != 0 && terminateErrno != ESRCH
    ? terminateErrno
    : nil
  terminal.closeMaster()

  do {
    _ = try await waitForExit(process, timeout: .seconds(2))
    if let terminateFailure {
      throw JourneyFailure.signalFailed(signal: SIGTERM, errno: terminateFailure)
    }
    return
  } catch JourneyFailure.processTimedOut {
    // Escalate below and still reap the child before returning the journey
    // failure to the caller.
  }

  let killResult = kill(processID, SIGKILL)
  let killErrno = errno
  if killResult != 0, killErrno != ESRCH {
    if let terminateFailure {
      throw JourneyFailure.signalEscalationFailed(
        termErrno: terminateFailure,
        killErrno: killErrno
      )
    }
    throw JourneyFailure.signalFailed(signal: SIGKILL, errno: killErrno)
  }
  _ = try await waitForExit(process, timeout: .seconds(5))
  if let terminateFailure {
    throw JourneyFailure.signalFailed(signal: SIGTERM, errno: terminateFailure)
  }
}

extension Array where Element: Equatable {
  fileprivate func containsSubsequence(_ candidate: [Element]) -> Bool {
    guard !candidate.isEmpty, candidate.count <= count else { return false }
    return indices.dropLast(candidate.count - 1).contains { start in
      Array(self[start..<(start + candidate.count)]) == candidate
    }
  }
}
