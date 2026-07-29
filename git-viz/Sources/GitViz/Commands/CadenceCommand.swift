import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct CadenceCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "cadence",
    abstract: "Commit activity by hour-of-day (24-cell heat strip)."
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
    let entries = DateValueAdapters.hourlyCommitCounts(commits: commits)
    GitVizRunOnce.print(
      HeatStrip("Commits by hour-of-day", entries: entries, cellWidth: 2),
      opts: opts
    )
  }
}
