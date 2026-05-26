import SwiftTUIRuntime

/// A fuzzy-filterable command-palette list used inside the Gallery's
/// palette sheet. The outer wrapper intentionally returns a
/// single-child `Group` so the stateful body becomes a DECLARED child
/// instead of the deferred payload's root view. In the graph-backed
/// runtime path, declared children are resolved through `resolveView`,
/// which gives the child its own `viewNode` and therefore safe local
/// `@State` / `@FocusState` storage.
///
/// Commands are passed in by the framework — `.paletteSheet`'s content
/// closure receives the snapshot of `paletteCommand` contributions
/// absorbed from the host scope's subtree (mirroring how
/// `.toolbar(style:)` absorbs toolbar items).
struct CommandPaletteList: View {
  let commands: [ActivePaletteCommand]
  let dismiss: @MainActor @Sendable () -> Void

  var body: some View {
    Group {
      CommandPaletteListBody(
        commands: commands,
        dismiss: dismiss
      )
    }
  }
}

private struct CommandPaletteListBody: View {
  private static let maximumVisibleRows = 12

  let commands: [ActivePaletteCommand]
  let dismiss: @MainActor @Sendable () -> Void

  @State private var query = ""
  @State private var selectedCommandKey: CommandPaletteCommandKey?
  @FocusState private var isQueryFocused: Bool
  @Namespace private var filterFocusNamespace

  private var matches: [CommandPaletteMatch] {
    if query.isEmpty {
      return commands.enumerated().map { offset, command in
        CommandPaletteMatch(command: command, score: offset)
      }
    }
    return
      commands
      .compactMap { command in
        fuzzyMatchScore(query: query, against: command.name)
          .map { CommandPaletteMatch(command: command, score: $0) }
      }
      .sorted { $0.score < $1.score }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      TextField("Filter commands…", text: $query)
        .focused($isQueryFocused)
        .prefersDefaultFocus(in: filterFocusNamespace)
        .onKeyPress(perform: handleFilterKeyPress)
      Divider()
      matchList
    }
    .padding(1)
    .frame(minWidth: 44, alignment: .leading)
    .focusScope(filterFocusNamespace)
    .onAppear {
      query = ""
    }
    .onChange(of: matchKeys, initial: true) { _, newKeys in
      reconcileSelection(for: newKeys)
    }
  }

  private var header: some View {
    HStack(spacing: 2) {
      Text("Command palette").bold()
      Spacer()
    }
  }

  @ViewBuilder
  private var matchList: some View {
    let rows = matches
    if rows.isEmpty {
      Text(commands.isEmpty ? "No commands in the current scope." : "No matches.")
        .foregroundStyle(.separator)
        .padding(.vertical, 1)
    } else {
      let visibleRange = visibleRange(in: rows)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(visibleRange), id: \.self) { index in
          let match = rows[index]
          row(for: match.command, isSelected: index == effectiveSelectedIndex)
        }
      }
    }
  }

  private var matchKeys: [CommandPaletteCommandKey] {
    matches.map(\.key)
  }

  private var selectedIndex: Int? {
    guard let selectedCommandKey else { return nil }
    return matches.firstIndex { $0.key == selectedCommandKey }
  }

  private var effectiveSelectedIndex: Int? {
    selectedIndex ?? (matches.isEmpty ? nil : 0)
  }

  private func visibleRange(in rows: [CommandPaletteMatch]) -> Range<Int> {
    guard rows.count > Self.maximumVisibleRows else {
      return 0..<rows.count
    }

    let selectedIndex = effectiveSelectedIndex ?? 0
    let start = min(
      max(0, selectedIndex - Self.maximumVisibleRows + 1),
      rows.count - Self.maximumVisibleRows
    )
    return start..<(start + Self.maximumVisibleRows)
  }

  private func row(
    for command: ActivePaletteCommand,
    isSelected: Bool
  ) -> some View {
    Button {
      perform(command)
    } label: {
      HStack(spacing: 1) {
        Text(isSelected ? ">" : " ")
          .foregroundStyle(isSelected ? .tint : .background)
        Text(command.name)
        if let description = command.description {
          Spacer()
          Text(description).foregroundStyle(.separator)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        if isSelected {
          Rectangle().fill(.selection)
        }
      }
    }
    .buttonStyle(.plain)
    .focusable(false)
    .onTapGesture {
      perform(command)
    }
    .disabled(!command.isEnabled)
  }

  private func handleFilterKeyPress(_ keyPress: KeyPress) -> KeyPressResult {
    if keyPress.modifiers == [] {
      switch keyPress.key {
      case .arrowDown, .tab:
        moveSelection(by: 1)
        return .handled
      case .arrowUp:
        moveSelection(by: -1)
        return .handled
      case .return:
        openSelectedCommand()
        return .handled
      default:
        return .ignored
      }
    }

    if keyPress == KeyPress(.tab, modifiers: .shift) {
      moveSelection(by: -1)
      return .handled
    }
    return .ignored
  }

  private func moveSelection(by delta: Int) {
    let rows = matches
    guard !rows.isEmpty else {
      selectedCommandKey = nil
      return
    }

    let currentIndex = effectiveSelectedIndex ?? 0
    let nextIndex = min(max(currentIndex + delta, 0), rows.count - 1)
    selectedCommandKey = rows[nextIndex].key
  }

  private func openSelectedCommand() {
    guard
      let effectiveSelectedIndex,
      matches.indices.contains(effectiveSelectedIndex)
    else {
      return
    }

    let command = matches[effectiveSelectedIndex].command
    guard command.isEnabled else { return }
    perform(command)
  }

  private func perform(_ command: ActivePaletteCommand) {
    guard command.isEnabled else { return }
    command.action()
    dismiss()
  }

  private func reconcileSelection(for keys: [CommandPaletteCommandKey]) {
    guard !keys.isEmpty else {
      selectedCommandKey = nil
      return
    }

    if let selectedCommandKey, keys.contains(selectedCommandKey) {
      return
    }
    selectedCommandKey = keys.first
  }
}

private struct CommandPaletteCommandKey: Equatable, Hashable {
  var name: String
  var description: String?
}

private struct CommandPaletteMatch {
  let command: ActivePaletteCommand
  let score: Int

  var key: CommandPaletteCommandKey {
    CommandPaletteCommandKey(
      name: command.name,
      description: command.description
    )
  }
}

/// Returns a fuzzy-match score for `query` against `candidate`, or
/// `nil` when the query is not a (case-insensitive) subsequence of
/// `candidate`. Lower scores are better matches.
///
/// The score is the total gap length between matched characters (plus
/// a leading-gap penalty for characters before the first match), so
/// tighter, earlier matches rank above looser, later ones. An empty
/// query matches everything with score 0.
private func fuzzyMatchScore(query: String, against candidate: String) -> Int? {
  guard !query.isEmpty else { return 0 }
  let queryChars = Array(query.lowercased())
  let candidateChars = Array(candidate.lowercased())

  var queryIndex = 0
  var lastMatch: Int? = nil
  var gapPenalty = 0
  for (index, char) in candidateChars.enumerated() {
    guard queryIndex < queryChars.count else { break }
    if char == queryChars[queryIndex] {
      if let lastMatch {
        gapPenalty += index - lastMatch - 1
      } else {
        // Leading gap penalty — tighter prefix matches rank best.
        gapPenalty += index
      }
      lastMatch = index
      queryIndex += 1
    }
  }
  return queryIndex == queryChars.count ? gapPenalty : nil
}
