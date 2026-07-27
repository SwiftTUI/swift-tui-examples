import Foundation
import GIFEditorCore
import SwiftTUI

/// Dithering as a command-line value.
///
/// `Quantizer.Dithering` is a `GIFEditorCore` type and `ExpressibleByArgument`
/// comes from swift-argument-parser, so conforming one to the other here would
/// be a retroactive conformance on two types this module owns neither of. A
/// mapped enum also gets to spell the case the way it would be typed.
public enum DitheringOption: String, Hashable, Sendable, CaseIterable, ExpressibleByArgument {
  case none
  case floydSteinberg = "floyd-steinberg"

  public var dithering: Quantizer.Dithering {
    switch self {
    case .none:
      return .none
    case .floydSteinberg:
      return .floydSteinberg
    }
  }
}

extension FrameCodingOption: ExpressibleByArgument {}

/// `--spritesheet` / `--frames` / `--apng`, exactly one of which is
/// required. Per-case help because one string across three flags would
/// have to describe all of them and therefore none.
extension ExportFormat: EnumerableFlag {
  public static func help(for value: ExportFormat) -> ArgumentHelp? {
    switch value {
    case .spritesheet:
      return "One PNG grid plus the JSON sidecar that maps frames to cells."
    case .frames:
      return "One PNG per frame, zero-padded so a listing is frame order."
    case .apng:
      return "A single animated PNG."
    }
  }
}

/// `halfcell info <file>` — say what a file is.
///
/// Reads both formats, because the question "what am I looking at" is the
/// one asked most often of a file whose extension is missing or wrong.
public struct InfoCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "info",
    abstract: "Report what a GIF or halfcell project contains."
  )

  @Argument(help: "Path to a .gif or .halfcell file.")
  var path: String

  @Flag(name: .long, help: "Emit JSON instead of the human-readable report.")
  var json = false

  public init() {}

  public func run() throws {
    try HeadlessRun.perform {
      let report = try HeadlessInfo.report(contentsOf: URL(fileURLWithPath: path))
      return json
        ? try HeadlessRun.jsonText(for: report)
        : HeadlessInfo.text(for: report)
    }
  }
}

/// `halfcell optimize <in.gif> -o <out.gif>` — re-encode a GIF and say what
/// it cost.
public struct OptimizeCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "optimize",
    abstract: "Re-encode a GIF with delta frames and report the size change."
  )

  @Argument(help: "Path to the GIF to re-encode.")
  var input: String

  @Option(name: [.short, .customLong("output")], help: "Where to write the re-encoded GIF.")
  var output: String

  @Option(
    name: .customLong("frame-coding"),
    help: "How frames are laid out: delta (changed rectangles) or full (whole canvas)."
  )
  var frameCoding: FrameCodingOption = .delta

  @Option(name: .customLong("dither"), help: "Dithering used on import: none or floyd-steinberg.")
  var dither: DitheringOption = .none

  @Flag(name: .long, help: "Emit JSON instead of the human-readable report.")
  var json = false

  public init() {}

  public func run() throws {
    try HeadlessRun.perform {
      let inputURL = URL(fileURLWithPath: input)
      let outputURL = URL(fileURLWithPath: output)
      let report = try HeadlessOptimize.run(
        input: inputURL,
        output: outputURL,
        frameCoding: frameCoding,
        dithering: dither.dithering
      )
      return json
        ? try HeadlessRun.jsonText(for: report)
        : HeadlessOptimize.text(for: report, input: inputURL, output: outputURL)
    }
  }
}

/// `halfcell export <file> --spritesheet | --frames | --apng` — the PNG
/// family.
public struct ExportCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "export",
    abstract: "Export a GIF or halfcell project as a spritesheet, frame PNGs, or an APNG."
  )

  @Argument(help: "Path to a .gif or .halfcell file.")
  var input: String

  @Flag
  var format: ExportFormat

  @Option(
    name: [.short, .customLong("output")],
    help: """
      Where the export goes: a base path for --spritesheet (.png and .json are \
      appended), a directory for --frames, a file for --apng. Defaults to a \
      sibling of the input named after it.
      """
  )
  var output: String?

  @Option(help: "Spritesheet columns. Defaults to the smallest near-square grid.")
  var columns: Int?

  @Option(name: .customLong("dither"), help: "Dithering used on import: none or floyd-steinberg.")
  var dither: DitheringOption = .none

  @Flag(name: .long, help: "Emit JSON instead of the human-readable report.")
  var json = false

  public init() {}

  public func run() throws {
    try HeadlessRun.perform {
      let report = try HeadlessExport.run(
        input: URL(fileURLWithPath: input),
        format: format,
        output: output,
        columns: columns,
        dithering: dither.dithering
      )
      return json ? try HeadlessRun.jsonText(for: report) : HeadlessExport.text(for: report)
    }
  }
}

// Routing these verbs used to need a dispatcher here, because a root command
// that declares a positional argument shadows its own subcommands. SwiftTUI now
// owns that: `GIFEditorApp.swiftTUIRootSubcommand(forRawArguments:)` claims the
// verb from the raw arguments, and the framework's own launch sequence runs it
// and attributes any failure to the verb rather than to the editor.

/// The three-line body every subcommand shares: run the pure work, print
/// what it produced, and turn a ``HeadlessError`` into the exit status it
/// declares.
///
/// This is the whole reason the subcommands above are thin. Everything
/// interesting is a function of already-resolved inputs that returns a
/// value; the only thing `run()` adds is the process, and the process is the
/// part a unit test cannot enter.
enum HeadlessRun {
  static func perform(_ body: () throws -> String) throws {
    do {
      let text = try body()
      if !text.isEmpty {
        print(text)
      }
    } catch let error as HeadlessError {
      writeToStandardError("halfcell: \(error.description)\n")
      throw ExitCode(error.exitCode)
    }
  }

  /// Sorted keys so a re-run over unchanged input is byte-stable and diffs
  /// cleanly; pretty-printed because the human who pipes this into `jq` is
  /// also going to read it once without.
  static func jsonText(for value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    do {
      let data = try encoder.encode(value)
      guard let text = String(data: data, encoding: .utf8) else {
        throw HeadlessError.operationFailed(detail: "report is not valid UTF-8")
      }
      return text
    } catch let error as HeadlessError {
      throw error
    } catch {
      throw HeadlessError.operationFailed(
        detail: "could not encode the report — \(String(describing: error))"
      )
    }
  }

  private static func writeToStandardError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
  }
}
