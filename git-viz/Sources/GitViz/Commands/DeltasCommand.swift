import ArgumentParser
import Foundation
import SwiftTUI
import SwiftTUICharts

struct DeltasCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "deltas",
    abstract: "Insertions and deletions over time."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let workingDirectory = opts.resolvedPath
    let since = opts.sinceDate
    let until = opts.untilDate
    let maxCommits = opts.maxCommits
    let deltas = try await GitRepo.perform(workingDirectory: workingDirectory) { repo in
      try repo.numstat(
        since: since,
        until: until,
        max: maxCommits
      )
    }
    let (insertions, deletions) = LineSeriesAdapters.dailyDeltas(deltas)

    let chart = LineChart(
      "Insertions vs Deletions",
      series: [insertions, deletions],
      height: 8,
      width: opts.resolvedWidth()
    )
    .chartXAxis(.dates(every: .week, format: .dateTime.month(.abbreviated).day()))
    .chartYAxis(.values(count: 5, format: .number.notation(.compactName)))
    .chartLegend(.bottom)

    GitVizRunOnce.print(chart, opts: opts)
  }
}
