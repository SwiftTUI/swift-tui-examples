import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct KindsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "kinds",
    abstract: "Commit-kind counts (feat / fix / refactor / …)."
  )

  @OptionGroup var opts: GitVizOptions
  @OptionGroup var repository: RepositoryOptions
  @OptionGroup var scan: ScanLimitOptions
  @OptionGroup var window: DateWindowOptions

  @MainActor func run() async throws {
    let workingDirectory = repository.resolvedPath
    let since = window.sinceDate
    let until = window.untilDate
    let maxCommits = scan.maxCommits
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
