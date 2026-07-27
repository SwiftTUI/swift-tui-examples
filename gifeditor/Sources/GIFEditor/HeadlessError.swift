import Foundation
import GIFEditorCore

/// Why a headless subcommand stopped, and what the process exits with.
///
/// The audience for this surface is a shell script, and a script can only
/// branch on the number. A private `1 / 2 / 3` ladder would mean nothing to
/// anyone who had not read this file, so the codes are the `sysexits.h`
/// values every other command-line tool on the machine already uses:
///
/// | Code | Name | Meaning here |
/// | --- | --- | --- |
/// | 0 | — | the subcommand did what it was asked |
/// | 64 | `EX_USAGE` | bad arguments — raised by swift-argument-parser, not here |
/// | 65 | `EX_DATAERR` | the file is not something this build can read |
/// | 66 | `EX_NOINPUT` | the file is not there, or could not be read at all |
/// | 70 | `EX_SOFTWARE` | the file read fine and the work after it failed |
///
/// The split that matters is 66 against 65: "you gave me a path that does
/// not exist" is the caller's typo, and "this is not a GIF" is a statement
/// about the bytes. A script that retries on one must not retry on the
/// other. 70 is the third bucket on purpose — an export that ran out of
/// disk is neither a bad path nor a bad file, and reporting it as either
/// would send the operator looking in the wrong place.
public enum HeadlessError: Error, Hashable, Sendable, CustomStringConvertible {
  /// Nothing exists at that path.
  case fileNotFound(URL)

  /// The path exists and the bytes could not be read — a directory, a
  /// permission failure, a device that went away mid-read.
  case unreadable(URL, detail: String)

  /// The bytes are neither a GIF nor a project envelope. Reported before
  /// any decoder sees them, so the caller is told "this is not a file I
  /// read" rather than being handed a JSON parse error about a byte
  /// offset inside a GIF.
  case unrecognizedFormat(URL)

  /// The bytes announce a format this build reads, and then fail to
  /// decode as one: a truncated GIF, a project file with a damaged pixel
  /// plane or a `formatVersion` from the future.
  case damaged(URL, detail: String)

  /// A file this build reads, of the wrong kind for this subcommand —
  /// `optimize` handed a project, for instance. Still a statement about
  /// the bytes, so it shares 65 with the two cases above.
  case wrongFormat(URL, expected: String, found: String)

  /// The file decoded and the work after it did not: an encoder that
  /// threw, a directory that could not be created, a write that failed.
  case operationFailed(detail: String)

  /// The process exit status for this failure.
  public var exitCode: Int32 {
    switch self {
    case .fileNotFound, .unreadable:
      return HeadlessExitStatus.noInput
    case .unrecognizedFormat, .damaged, .wrongFormat:
      return HeadlessExitStatus.dataError
    case .operationFailed:
      return HeadlessExitStatus.softwareError
    }
  }

  /// One line, no trailing newline, written to standard error by the
  /// subcommand. Names the file first because a script's log is usually
  /// read long after the invocation that produced it.
  public var description: String {
    switch self {
    case .fileNotFound(let url):
      return "\(url.lastPathComponent): no such file (\(url.path))"
    case .unreadable(let url, let detail):
      return "\(url.lastPathComponent): could not be read — \(detail)"
    case .unrecognizedFormat(let url):
      return
        "\(url.lastPathComponent): neither a GIF nor a .\(ProjectFile.fileExtension) project"
    case .damaged(let url, let detail):
      return "\(url.lastPathComponent): damaged — \(detail)"
    case .wrongFormat(let url, let expected, let found):
      return "\(url.lastPathComponent): expected \(expected), found \(found)"
    case .operationFailed(let detail):
      return detail
    }
  }
}

/// The exit statuses ``HeadlessError`` maps onto, named so the numbers are
/// spelled once and the table in that type's documentation has something
/// to point at.
public enum HeadlessExitStatus {
  /// The subcommand did what it was asked.
  public static let success: Int32 = 0
  /// `EX_DATAERR` — the input is not something this build can read.
  public static let dataError: Int32 = 65
  /// `EX_NOINPUT` — the input is missing or unreadable.
  public static let noInput: Int32 = 66
  /// `EX_SOFTWARE` — the input was fine and the work after it failed.
  public static let softwareError: Int32 = 70
}
