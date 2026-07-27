import Foundation

struct PersistentStateClient: Sendable {
  var load: @Sendable () throws -> SextantPersistentState
  var save: @Sendable (SextantPersistentState) throws -> Void

  init(
    load: @escaping @Sendable () throws -> SextantPersistentState,
    save: @escaping @Sendable (SextantPersistentState) throws -> Void
  ) {
    self.load = load
    self.save = save
  }

  static func jsonFile(at url: URL) -> PersistentStateClient {
    let store = JSONFileStore<SextantPersistentState>(url: url)
    return PersistentStateClient(
      load: {
        try store.load(default: SextantPersistentState())
      },
      save: {
        try store.save($0)
      }
    )
  }
}

actor SextantStateRepository {
  private let client: PersistentStateClient
  private var state: SextantPersistentState?

  init(client: PersistentStateClient) {
    self.client = client
  }

  func load() throws -> SextantPersistentState {
    if let state {
      return state
    }
    let loaded = try client.load()
    guard loaded.version == 1 else {
      throw StateFailure.unsupportedVersion(loaded.version)
    }
    state = normalized(loaded)
    return state!
  }

  func markHelpSeen() throws {
    var state = try load()
    guard !state.hasSeenHelp else {
      return
    }
    state.hasSeenHelp = true
    try persist(state)
  }

  func recordRecent(_ url: URL) throws {
    var state = try load()
    let path = url.standardizedFileURL.path
    state.recents.removeAll { $0 == path }
    state.recents.insert(path, at: 0)
    state.recents = Array(state.recents.prefix(50))
    try persist(state)
  }

  func toggleBookmark(_ url: URL) throws -> Bool {
    var state = try load()
    let path = url.standardizedFileURL.path
    if let index = state.bookmarks.firstIndex(of: path) {
      state.bookmarks.remove(at: index)
      try persist(state)
      return false
    }
    state.bookmarks.append(path)
    state.bookmarks = Array(state.bookmarks.suffix(200))
    try persist(state)
    return true
  }

  private func persist(_ state: SextantPersistentState) throws {
    let normalized = normalized(state)
    try client.save(normalized)
    self.state = normalized
  }

  private func normalized(
    _ state: SextantPersistentState
  ) -> SextantPersistentState {
    var state = state
    state.bookmarks = unique(state.bookmarks)
    state.recents = Array(unique(state.recents).prefix(50))
    return state
  }

  private func unique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
  }
}

enum StateFailure: Error, Equatable, Sendable {
  case unsupportedVersion(Int)
}
