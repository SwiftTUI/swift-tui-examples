import Observation
import SwiftTUIRuntime

/// Conway's Game of Life, rendered through SwiftTUI at three zoom
/// levels and editable by tap or click-and-drag.
///
/// **Zoom modes** (most → least dense):
///   - braille (8×): 2×4 game cells per terminal cell, Unicode required
///   - half-cell (2×): 1×2 game cells per terminal cell, Unicode required
///   - square (1×): 1 game cell per pair of terminal cells (always available)
///
/// **Interactivity**:
///   - tap: toggles the cell under the pointer
///   - drag: paints every cell touched along the drag path with the
///     opposite of the starting cell's state. So starting on an alive
///     cell erases; starting on a dead cell stamps.
///
/// **Capability gating** is enforced by the `Picker` options: when a
/// host environment one day exposes a `glyphLevel` value, modes that
/// require Unicode are filtered out for ASCII-only profiles. Today the
/// demo trusts the iframe / WASI host to advertise Unicode, which the
/// browser always does.
///
/// **State shape**: game state lives in an `@Observable` model so the
/// auto-tick's `grid` writes invalidate only the views that *read* the
/// grid (the header's counters and the board). Holding the grid as
/// `@State` on `LifeTab` itself would invalidate the tab's own identity
/// every generation, pulling the whole scene — controls included — into
/// every tick's recompute cone and defeating subtree reuse.
public struct LifeTab: View {
  public init() {}

  @State private var model = LifeModel()

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      LifeHeader(model: model)
      Divider()
      LifeBoard(model: model)
      Divider()
      LifeControls(model: model)
    }
    .task(id: AutoTickKey(running: model.isRunning, intervalMs: Int(model.tickIntervalMs))) {
      @MainActor in
      await model.runAutoTick()
    }
  }
}

// MARK: - Model

/// Game, tick, and zoom state. `@Observable` so invalidation is
/// per-reader: `grid.step()` reaches the header counters and the board,
/// never the controls row or the tab shell.
@Observable
@MainActor
final class LifeModel {
  // Game state
  var grid = LifeGrid()
  var didSeedDefault = false
  var lastFitWidth: Int = 0
  var lastFitHeight: Int = 0

  // Auto-tick state
  var isRunning: Bool = true
  var tickIntervalMs: Double = 200

  // Zoom & rendering
  var zoom: LifeZoom = .halfCell

  // Drag-paint state. `paintMode` is `nil` while idle and latches to
  // either `true` (stamp alive) or `false` (erase) on the first touch
  // of a drag. The set tracks already-stamped game cells across the
  // drag so traversing the same cell does not re-toggle it.
  var paintMode: Bool? = nil
  var stampedCells: Set<Int> = []

  // MARK: Drag painting

  func handlePaint(at point: Point, gridSize: (width: Int, height: Int)) {
    guard let cell = zoom.gameCell(at: point, gridSize: gridSize) else { return }
    let index = cell.y * LifeGrid.maxWidth + cell.x

    if paintMode == nil {
      // First touch of this drag — latch the paint mode to the inverse
      // of the starting cell so dragging from an alive cell erases and
      // dragging from a dead cell stamps.
      paintMode = !grid.at(cell.x, cell.y)
    }

    // Skip cells already stamped during this drag.
    guard !stampedCells.contains(index) else { return }
    stampedCells.insert(index)

    if let mode = paintMode {
      grid.set(cell.x, cell.y, mode)
    }
  }

  // MARK: Auto-tick loop

  func runAutoTick() async {
    guard isRunning else { return }
    let intervalNs = UInt64(max(20.0, tickIntervalMs)) * 1_000_000

    while !Task.isCancelled, isRunning {
      try? await Task.sleep(nanoseconds: intervalNs)
      guard !Task.isCancelled, isRunning else { return }
      grid.step()
    }
  }
}

// MARK: - Header

private struct LifeHeader: View {
  let model: LifeModel

  var body: some View {
    HStack(spacing: 1) {
      Text("Conway's Life").bold()
      Text("·").foregroundStyle(.separator)
      Text("\(model.grid.population) live").foregroundStyle(.muted)
      Text("·").foregroundStyle(.separator)
      Text("gen \(model.grid.generation)").foregroundStyle(.muted)
      Spacer()
      Text(model.zoom.label).foregroundStyle(.tint)
    }
    .padding(.horizontal, 1)
  }
}

// MARK: - Grid surface

private struct LifeBoard: View {
  let model: LifeModel

  var body: some View {
    GeometryReader { proxy in
      let dims = model.zoom.gridDimensions(for: proxy.size)
      let termSize = model.zoom.terminalSize(
        forGameWidth: dims.width, gameHeight: dims.height
      )
      let drawing = LifeDrawing(
        cells: LifeRenderer.snapshot(of: model.grid, width: dims.width, height: dims.height),
        width: dims.width,
        height: dims.height,
        zoom: model.zoom
      )

      Canvas(drawing, grid: model.zoom.canvasGrid)
        .foregroundStyle(.tint)
        .frame(width: termSize.width, height: termSize.height, alignment: .topLeading)
        .contentShape(
          CellRect(
            origin: .init(x: 0, y: 0),
            size: proxy.size
          )
        )
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              model.handlePaint(at: value.location, gridSize: dims)
            }
            .onEnded { _ in
              model.paintMode = nil
              model.stampedCells.removeAll(keepingCapacity: true)
            }
        )
        .onAppear {
          guard !model.didSeedDefault else { return }
          model.didSeedDefault = true
          model.grid.resize(width: dims.width, height: dims.height)
          model.grid.seedDefault()
          model.lastFitWidth = dims.width
          model.lastFitHeight = dims.height
        }
        .onChange(of: dims.width) { _, newValue in
          if newValue != model.lastFitWidth {
            model.lastFitWidth = newValue
            model.grid.resize(width: dims.width, height: dims.height)
          }
        }
        .onChange(of: dims.height) { _, newValue in
          if newValue != model.lastFitHeight {
            model.lastFitHeight = newValue
            model.grid.resize(width: dims.width, height: dims.height)
          }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Controls

private struct LifeControls: View {
  @Bindable var model: LifeModel

  var body: some View {
    HStack(spacing: 2) {
      Button(model.isRunning ? "Pause" : "Play") {
        model.isRunning.toggle()
      }
      .buttonStyle(.borderedProminent)

      Button("Step") {
        model.grid.step()
      }
      .disabled(model.isRunning)

      Button("Random") {
        model.grid.randomize()
      }

      Button("Clear") {
        model.grid.clear()
      }

      Spacer()

      Picker("Zoom", selection: $model.zoom) {
        ForEach(LifeZoom.allCases, id: \.self) { level in
          Text(level.label).tag(level)
        }
      }
    }
    .focusSection()
    .padding(.horizontal, 1)
  }
}

// MARK: - Auto-tick key

/// `.task(id:)` re-runs the body when this key changes, so flipping
/// `isRunning` or `tickIntervalMs` cleanly cancels the prior loop and
/// starts a fresh one. Sendable so it satisfies the `id`'s
/// `Equatable + Sendable` constraint under strict concurrency.
private struct AutoTickKey: Hashable, Sendable {
  let running: Bool
  let intervalMs: Int
}
