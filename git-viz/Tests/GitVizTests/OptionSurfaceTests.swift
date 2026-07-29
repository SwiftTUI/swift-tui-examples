import ArgumentParser
import Foundation
import Testing

@testable import GitViz

/// Pins the option surface each subcommand exposes.
///
/// Every subcommand used to flatten one wide option group, so `--help`
/// advertised `--since`, `--until` and `--top` everywhere while two-thirds of
/// the subcommands ignored them — passing one produced a silently unchanged
/// chart rather than an error. Options now live in groups a subcommand opts
/// into, and these tests assert the membership, so a group added or dropped
/// shows up here rather than in a user's terminal.
@Suite("Option surface")
struct OptionSurfaceTests {
  // MARK: - Date window

  /// Subcommands that pass a date window through to git.
  static let acceptsDateWindow: [(String, any ParsableCommand.Type)] = [
    ("cadence", CadenceCommand.self),
    ("deltas", DeltasCommand.self),
    ("loc", LocCommand.self),
    ("kinds", KindsCommand.self),
    ("kinds-share", KindsShareCommand.self),
    ("tempo", TempoCommand.self),
    ("volatility", VolatilityCommand.self),
    ("concentration", ConcentrationCommand.self),
    ("dashboard", DashboardCommand.self),
  ]

  /// Subcommands that do not. Either they read refs rather than commits, or
  /// their window *is* the chart's definition and overriding it would change
  /// what the chart means.
  static let rejectsDateWindow: [(String, any ParsableCommand.Type)] = [
    ("index", IndexCommand.self),
    ("info", InfoCommand.self),
    ("activity", ActivityCommand.self),
    ("pulse", PulseCommand.self),
    ("health", HealthCommand.self),
    ("recent-vs-all", RecentVsAllCommand.self),
    ("releases", ReleasesCommand.self),
    ("dag", DagCommand.self),
  ]

  @Test("every subcommand either honours --since or refuses it")
  func dateWindowMembershipIsTotal() {
    let named = Set(
      (Self.acceptsDateWindow + Self.rejectsDateWindow).map(\.0)
    )
    let registered = Set(
      GitVizApp.configuration.subcommands.compactMap { $0.configuration.commandName }
    )
    // If this fails, a subcommand was added without deciding which side of
    // the date-window seam it belongs on.
    #expect(named == registered)
  }

  @Test("subcommands that honour a date window accept --since")
  func windowSubcommandsAcceptSince() throws {
    for (name, type) in Self.acceptsDateWindow {
      #expect(throws: Never.self, "\(name) should accept --since") {
        _ = try type.parseAsRoot(["--since", "2024-01-01"])
      }
    }
  }

  @Test("subcommands that ignore a date window reject --since")
  func nonWindowSubcommandsRejectSince() throws {
    for (name, type) in Self.rejectsDateWindow {
      #expect(throws: (any Error).self, "\(name) should reject --since") {
        _ = try type.parseAsRoot(["--since", "2024-01-01"])
      }
    }
  }

  // MARK: - Ranking

  @Test("--top is accepted only by the subcommands that rank")
  func rankingSurface() throws {
    let ranks: [(String, any ParsableCommand.Type)] = [
      ("tempo", TempoCommand.self),
      ("volatility", VolatilityCommand.self),
      ("concentration", ConcentrationCommand.self),
      ("recent-vs-all", RecentVsAllCommand.self),
    ]
    for (name, type) in ranks {
      #expect(throws: Never.self, "\(name) ranks, so --top applies") {
        _ = try type.parseAsRoot(["--top", "3"])
      }
    }

    // `releases` orders by date and bounds with its own --max; `cadence`
    // renders a fixed 24-hour strip. Neither ranks.
    #expect(throws: (any Error).self) {
      _ = try ReleasesCommand.parseAsRoot(["--top", "3"])
    }
    #expect(throws: (any Error).self) {
      _ = try CadenceCommand.parseAsRoot(["--top", "3"])
    }
  }

  // MARK: - Repository

  @Test("index takes no --path because it opens no repository")
  func indexHasNoRepositoryOptions() {
    #expect(throws: (any Error).self) {
      _ = try IndexCommand.parseAsRoot(["--path", "/tmp"])
    }
    #expect(throws: Never.self) {
      _ = try InfoCommand.parseAsRoot(["--path", "/tmp"])
    }
  }

  // MARK: - Date parsing

  @Test("CalendarDay accepts a full ISO date")
  func calendarDayAcceptsFullDate() throws {
    let day = try #require(CalendarDay(argument: "2024-03-17"))
    let parts = Calendar(identifier: .gregorian).dateComponents(
      in: TimeZone(identifier: "UTC")!,
      from: day.date
    )
    #expect(parts.year == 2024)
    #expect(parts.month == 3)
    #expect(parts.day == 17)
  }

  @Test(
    "CalendarDay rejects what used to be silently treated as no bound",
    arguments: ["yesterday", "2024-13-45", "2024-03", "17/03/2024", "", "2024-03-17T09:00:00Z"]
  )
  func calendarDayRejectsMalformed(_ argument: String) {
    #expect(CalendarDay(argument: argument) == nil)
  }

  @Test("a malformed --since fails parsing rather than defaulting to no bound")
  func malformedSinceFailsParsing() {
    #expect(throws: (any Error).self) {
      _ = try DeltasCommand.parseAsRoot(["--since", "yesterday"])
    }
  }

  @Test("a parsed window reaches the command as a Date")
  func parsedWindowReachesTheCommand() throws {
    let root = try DeltasCommand.parseAsRoot(["--since", "2024-01-01", "--until", "2024-06-30"])
    let command = try #require(root as? DeltasCommand)
    #expect(command.window.sinceDate == CalendarDay(argument: "2024-01-01")?.date)
    #expect(command.window.untilDate == CalendarDay(argument: "2024-06-30")?.date)
  }

  // MARK: - Path resolution

  @Test("resolvedPath expands a tilde and absolutizes a relative path")
  func resolvedPathExpandsAndAbsolutizes() throws {
    var options = RepositoryOptions()
    options.path = "~/somewhere"
    #expect(options.resolvedPath.path == NSHomeDirectory() + "/somewhere")

    options.path = "relative/dir"
    // `URL(fileURLWithPath:)` resolves against the process cwd on its own,
    // which is why the old hand-rolled fallback for this case was dead code.
    #expect(options.resolvedPath.path.hasPrefix("/"))
    #expect(options.resolvedPath.path.hasSuffix("relative/dir"))
  }
}
