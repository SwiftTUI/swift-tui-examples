import GIFEditorCore

/// Immutable capture of every piece of editor state an undo step must
/// restore: the document plus the selection-context fields (cursor,
/// frame/layer index, marquee selection) and the history generation in
/// effect when the snapshot was taken.
///
/// Kept here next to `EditorHistory` because the history stack is the
/// only thing that reads or writes whole snapshots; the coordinator
/// produces one with `EditorViewModel.snapshotState()` and applies one
/// with `EditorViewModel.restore(_:)`.
struct EditorSnapshot: Equatable {
  var document: GIFDocument
  var currentFrameIndex: Int
  var currentLayerIndex: Int
  var cursor: GIFEditorCore.PixelPoint
  var selection: Selection?
  var historyGeneration: Int
}

/// Undo/redo stack plus snapshot bookkeeping for the editor.
///
/// A value type owned by `EditorViewModel`: the coordinator captures its
/// own state into an `EditorSnapshot`, hands snapshots in, and applies
/// the snapshots this history returns. Keeping the generation counters
/// and the stacks here leaves the coordinator free to delegate without
/// changing the observable behavior — the dirty flag is still derived
/// from `currentGeneration != cleanGeneration`, and a stroke is still a
/// single grouped entry.
struct EditorHistory {
  private struct HistoryEntry {
    var snapshot: EditorSnapshot
    var label: String
  }

  private struct ActiveUndoGroup {
    var snapshot: EditorSnapshot
    var label: String
  }

  /// Outcome of an undo/redo request handed back to the coordinator so
  /// it can apply the restored snapshot and announce the result.
  struct RestoreResult {
    var snapshot: EditorSnapshot
    var label: String
  }

  private var undoStack: [HistoryEntry] = []
  private var redoStack: [HistoryEntry] = []
  private var activeUndoGroup: ActiveUndoGroup?
  private var currentGeneration: Int = 0
  private var cleanGeneration: Int = 0
  private var nextGeneration: Int = 1
  private let limit: Int = 100

  var canUndo: Bool {
    !undoStack.isEmpty
  }

  var canRedo: Bool {
    !redoStack.isEmpty
  }

  var isDirty: Bool {
    currentGeneration != cleanGeneration
  }

  /// The generation stamped into snapshots the coordinator captures, so
  /// a restored snapshot carries the matching dirty state forward.
  var currentHistoryGeneration: Int {
    currentGeneration
  }

  /// Marks the present generation clean (called after a successful save).
  mutating func markClean() {
    cleanGeneration = currentGeneration
  }

  /// Whether a grouped edit is currently open. Single edits made while a
  /// group is active fold into that group rather than pushing their own
  /// undo step.
  var hasActiveGroup: Bool {
    activeUndoGroup != nil
  }

  // MARK: - Undo / redo

  /// Pops the newest undo entry. Returns the snapshot to restore plus
  /// the redo entry to push (built from the caller's current state) so
  /// the coordinator can apply both atomically.
  mutating func undo(current: EditorSnapshot) -> RestoreResult? {
    guard let entry = undoStack.popLast() else { return nil }
    activeUndoGroup = nil
    redoStack.append(HistoryEntry(snapshot: current, label: entry.label))
    return RestoreResult(snapshot: entry.snapshot, label: entry.label)
  }

  mutating func redo(current: EditorSnapshot) -> RestoreResult? {
    guard let entry = redoStack.popLast() else { return nil }
    activeUndoGroup = nil
    undoStack.append(HistoryEntry(snapshot: current, label: entry.label))
    return RestoreResult(snapshot: entry.snapshot, label: entry.label)
  }

  /// Applies the generation carried by a restored snapshot. Pending
  /// groups are dropped — a restore always lands on a committed state.
  mutating func adoptRestored(generation: Int) {
    activeUndoGroup = nil
    currentGeneration = generation
  }

  // MARK: - Grouping

  /// Opens an undo group anchored at `before`. No-op if one is already
  /// open, so nested begins keep the outermost anchor.
  mutating func beginGroup(_ label: String, before: EditorSnapshot) {
    guard activeUndoGroup == nil else { return }
    activeUndoGroup = ActiveUndoGroup(snapshot: before, label: label)
  }

  /// Closes the active group, committing one undo step from its anchor.
  /// No-op if no group is open. An explicit `label` overrides the one
  /// captured at `beginGroup`.
  mutating func finishGroup(label: String? = nil, current document: GIFDocument) {
    guard let group = activeUndoGroup else { return }
    activeUndoGroup = nil
    commit(from: group.snapshot, label: label ?? group.label, current: document)
  }

  /// Commits a single undo step from `before` unless a group is open (in
  /// which case the edit has already folded into the group and is
  /// committed when the group finishes). The coordinator owns running the
  /// edit; this only records the step. The group check mirrors the
  /// original inline guard and never fires in practice because the
  /// coordinator skips this call entirely while a group is active — it is
  /// kept as defense-in-depth, not a discard path. The unchanged-document
  /// guard in `commit` is preserved.
  mutating func recordSingleEdit(
    from before: EditorSnapshot,
    label: String,
    current document: GIFDocument
  ) {
    if activeUndoGroup != nil { return }
    commit(from: before, label: label, current: document)
  }

  private mutating func commit(
    from before: EditorSnapshot,
    label: String,
    current document: GIFDocument
  ) {
    guard Self.documentChanged(from: before.document, to: document) else { return }

    undoStack.append(HistoryEntry(snapshot: before, label: label))
    if undoStack.count > limit {
      undoStack.removeFirst(undoStack.count - limit)
    }
    redoStack.removeAll()
    currentGeneration = nextGeneration
    nextGeneration += 1
  }

  /// Same boolean result as `current != before`, but short-circuits on the
  /// cheap scalar fields first so a structural edit (resize, frame add/delete,
  /// palette change) is decided without the `O(frames × layers × area)`
  /// pixel-by-pixel frame walk. Only a structurally-identical document falls
  /// through to the full frame compare — which itself short-circuits at the
  /// first differing frame. Behavior is identical to the synthesized `!=`.
  private static func documentChanged(
    from before: GIFDocument,
    to current: GIFDocument
  ) -> Bool {
    if before.size != current.size { return true }
    if before.frames.count != current.frames.count { return true }
    if before.loopCount != current.loopCount { return true }
    if before.path != current.path { return true }
    if before.palette != current.palette { return true }
    return before.frames != current.frames
  }
}
