import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct KindsShareCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "kinds-share",
    abstract: "Quarterly share of each commit kind (one stacked bar per quarter)."
  )

  @OptionGroup var opts: GitVizOptions

  @Option(name: .long, help: "Number of trailing quarters to chart.")
  var quarters: Int = 8

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
    let quarters = BarEntryAdapters.quarterlyKindShare(commits, quarters: quarters)

    GitVizRunOnce.print(
      VStack(alignment: .leading, spacing: 0) {
        Text("Commit-kind share per quarter").bold()
        Divider()
        ForEach(quarters, id: \.label) { quarter in
          StackedBarChart(quarter.label, entries: quarter.entries, barWidth: 20)
        }
      },
      opts: opts
    )
  }
}
