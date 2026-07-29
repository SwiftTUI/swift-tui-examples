import ArgumentParser

@main
struct GitVizApp: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "git-viz",
    abstract: "Visualize information about a git repository using SwiftTUICharts.",
    discussion: """
      git-viz exercises every chart primitive in SwiftTUICharts against the
      current git repository. Run `git-viz` with no arguments for an index of
      available subcommands.
      """,
    subcommands: [
      IndexCommand.self,
      InfoCommand.self,
      ActivityCommand.self,
      CadenceCommand.self,
      TempoCommand.self,
      DeltasCommand.self,
      LocCommand.self,
      VolatilityCommand.self,
      KindsCommand.self,
      KindsShareCommand.self,
      PulseCommand.self,
      RecentVsAllCommand.self,
      HealthCommand.self,
      ConcentrationCommand.self,
      ReleasesCommand.self,
      DagCommand.self,
      DashboardCommand.self,
    ],
    defaultSubcommand: IndexCommand.self
  )
}
