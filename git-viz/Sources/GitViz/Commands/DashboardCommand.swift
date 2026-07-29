import ArgumentParser

struct DashboardCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dashboard",
    abstract: "Run info, activity, deltas, kinds, volatility, and releases back-to-back.",
    discussion: """
      Long output. Pipe to `less -R` if you only want to scan parts of it.
      """
  )

  @OptionGroup var opts: GitVizOptions
  @OptionGroup var repository: RepositoryOptions
  @OptionGroup var scan: ScanLimitOptions
  @OptionGroup var window: DateWindowOptions
  @OptionGroup var ranking: RankingOptions

  @MainActor func run() async throws {
    // Each child command's body is short; reuse them by parsing default
    // instances and substituting the shared options before invoking `run()`.
    //
    // Children declare different option groups, so each substitution names
    // exactly the ones that child honours. That is deliberately explicit:
    // you can read off which of the dashboard's options reach which section,
    // and adding a group to a child is a compile error here until it is
    // forwarded.
    try await runChild { (cmd: inout InfoCommand) in
      cmd.opts = opts
      cmd.repository = repository
      cmd.scan = scan
    }
    try await runChild { (cmd: inout ActivityCommand) in
      cmd.opts = opts
      cmd.repository = repository
      cmd.scan = scan
    }
    try await runChild { (cmd: inout DeltasCommand) in
      cmd.opts = opts
      cmd.repository = repository
      cmd.scan = scan
      cmd.window = window
    }
    try await runChild { (cmd: inout KindsCommand) in
      cmd.opts = opts
      cmd.repository = repository
      cmd.scan = scan
      cmd.window = window
    }
    try await runChild { (cmd: inout VolatilityCommand) in
      cmd.opts = opts
      cmd.repository = repository
      cmd.scan = scan
      cmd.window = window
      cmd.ranking = ranking
    }
    try await runChild { (cmd: inout ReleasesCommand) in
      cmd.opts = opts
      cmd.repository = repository
    }
  }

  /// Parses a default-state instance of the child command type, lets the
  /// caller substitute fields, then invokes `run()`. Using `parseAsRoot([])`
  /// rather than the bare initializer ensures ArgumentParser-managed
  /// properties are fully populated (otherwise `@Flag verbose: Int` would
  /// trap on first access).
  @MainActor
  private func runChild<C: AsyncParsableCommand>(
    _ mutate: (inout C) -> Void
  ) async throws {
    guard var child = try await C.parseAsRoot([]) as? C else { return }
    mutate(&child)
    try await child.run()
  }
}
