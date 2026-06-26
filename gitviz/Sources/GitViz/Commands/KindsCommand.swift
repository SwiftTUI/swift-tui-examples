import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct KindsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "kinds",
    abstract: "Commit-kind counts (feat / fix / refactor / …)."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let workingDirectory = opts.resolvedPath
    let since = opts.sinceDate
    let until = opts.untilDate
    let maxCommits = opts.maxCommits
    let commits = try await GitRepo.perform(workingDirectory: workingDirectory) { repo in
      try repo.commits(
        since: since,
        until: until,
        max: maxCommits
      )
    }
    let entries = BarEntryAdapters.commitKindCounts(commits)
    GitVizRunOnce.print(
      ColumnChart(
        "Commit kinds",
        entries: entries,
        chartHeight: 6,
        columnWidth: 4
      ),
      opts: opts
    )
  }
}
