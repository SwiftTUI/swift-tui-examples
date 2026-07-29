import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct VolatilityCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "volatility",
    abstract: "Top-N most-changed files (lifetime change count)."
  )

  @OptionGroup var opts: GitVizOptions
  @OptionGroup var repository: RepositoryOptions
  @OptionGroup var scan: ScanLimitOptions
  @OptionGroup var window: DateWindowOptions
  @OptionGroup var ranking: RankingOptions

  @MainActor func run() async throws {
    let workingDirectory = repository.resolvedPath
    let maxCommits = scan.maxCommits
    let since = window.sinceDate
    let until = window.untilDate
    let files = try await GitRepo.perform(workingDirectory: workingDirectory) { repo in
      try repo.fileChangeCounts(since: since, until: until, max: maxCommits)
    }
    let entries = BarEntryAdapters.volatilityBars(files, top: ranking.top)
    GitVizRunOnce.print(
      BarChart(
        "Most-changed files (top \(ranking.top))",
        entries: entries,
        barWidth: 16,
        labelWidth: 30
      ),
      opts: opts
    )
  }
}
