import ArgumentParser
import Foundation
import SwiftTUI
import SwiftTUICLI

/// A `YYYY-MM-DD` calendar day.
///
/// Exists so ArgumentParser rejects a malformed date at parse time, before any
/// command body runs. Parsing this as a plain `String` and converting later
/// cannot distinguish "absent" from "unparseable", so `--since yesterday`
/// silently meant *no lower bound* and rendered a plausible-looking wrong
/// chart.
struct CalendarDay: ExpressibleByArgument, Sendable, Equatable {
  let date: Date

  init?(argument: String) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    // The round-trip is the strictness. `.withFullDate` alone still accepts a
    // full timestamp like `2024-03-17T09:00:00Z` and silently discards the
    // time; requiring the formatted date to equal the input rejects anything
    // that is not exactly a calendar day.
    guard
      let date = formatter.date(from: argument),
      formatter.string(from: date) == argument
    else { return nil }
    self.date = date
  }

  static var defaultValueDescription: String { "YYYY-MM-DD" }
}

/// Rendering options, flattened into every subcommand.
///
/// Every subcommand renders, so every subcommand declares this one — it is
/// what ``GitVizRunOnce`` needs. The framework's own colour / glyph / motion
/// flags nest inside it as a separate `--help` section.
struct GitVizOptions: ParsableArguments {
  @Option(name: .long, help: "Output width in cells (defaults to terminal width).")
  var width: Int?

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions
}

extension GitVizOptions {
  /// Eagerly resolves the effective output width. Used by chart primitives
  /// that lock their internal plot width at construction time (LineChart,
  /// for instance) — without this they fall back to a 60-cell default and
  /// look "disjoint" from their title chrome on wider terminals.
  func resolvedWidth(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Int {
    width ?? RenderOnce.resolveTerminalWidth(environment: environment)
  }
}

/// Which repository to read. Declared by every subcommand that opens one —
/// which is all of them except `index`, whose output is a static listing.
struct RepositoryOptions: ParsableArguments {
  @Option(name: .long, help: "Repository path (defaults to cwd).")
  var path: String = "."
}

extension RepositoryOptions {
  /// Repository path, tilde-expanded. `URL(fileURLWithPath:)` already
  /// resolves a relative path against the process cwd, so no manual joining
  /// is needed — an earlier hand-rolled fallback for that case was
  /// unreachable.
  var resolvedPath: URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
  }
}

/// How much history to scan. Declared by the subcommands that walk commits;
/// the ones reading only refs (`releases`) or taking an explicit bound of
/// their own (`dag`) do not.
struct ScanLimitOptions: ParsableArguments {
  @Option(name: .long, help: "Limit each scan to the last N commits.")
  var maxCommits: Int = 10_000
}

/// The date window to restrict history to.
///
/// Declared only by subcommands that pass it through to git. Charts whose
/// window *is* their definition — `activity` (a calendar year), `health`
/// (one year), `pulse` (five weeks), `recent-vs-all` (30 days versus all
/// time) — deliberately do not accept it, because overriding the window
/// would change what the chart means rather than what it covers.
struct DateWindowOptions: ParsableArguments {
  @Option(name: .long, help: "Only consider commits since this date.")
  var since: CalendarDay?

  @Option(name: .long, help: "Only consider commits until this date.")
  var until: CalendarDay?
}

extension DateWindowOptions {
  var sinceDate: Date? { since?.date }
  var untilDate: Date? { until?.date }
}

/// Top-N for the subcommands that rank something.
struct RankingOptions: ParsableArguments {
  @Option(name: .long, help: "Top-N for ranking subcommands.")
  var top: Int = 10
}
