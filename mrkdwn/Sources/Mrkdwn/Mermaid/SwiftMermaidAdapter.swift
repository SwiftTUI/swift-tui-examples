import SwiftMermaid

enum SwiftMermaidAdapter {
  private static let coordinator = MermaidRenderCoordinator()

  static func render(_ request: MermaidRenderRequest) async -> MermaidPresentation {
    await coordinator.render(request)
  }
}

actor MermaidRenderCoordinator {
  private struct CacheEntry: Sendable {
    var presentation: MermaidPresentation
    var lastAccess: UInt64
    var estimatedBytes: Int
  }

  private let limiter = AsyncJobLimiter(limit: 2)
  private var cache: [MermaidRenderRequest: CacheEntry] = [:]
  private var accessCounter: UInt64 = 0
  private var retainedBytes = 0
  private let maximumEntries = 32
  private let maximumBytes = 4 * 1_024 * 1_024

  func render(_ request: MermaidRenderRequest) async -> MermaidPresentation {
    accessCounter &+= 1
    if var entry = cache[request] {
      entry.lastAccess = accessCounter
      cache[request] = entry
      return entry.presentation
    }

    let presentation: MermaidPresentation
    do {
      presentation = try await limiter.run {
        await Task.detached {
          Self.renderUncached(request)
        }.value
      }
    } catch {
      return .unavailable(
        diagnostic: "Mermaid rendering was cancelled."
      )
    }
    guard !Task.isCancelled else { return presentation }
    accessCounter &+= 1
    if var existing = cache[request] {
      existing.lastAccess = accessCounter
      cache[request] = existing
      return existing.presentation
    }
    let entry = CacheEntry(
      presentation: presentation,
      lastAccess: accessCounter,
      estimatedBytes: Self.estimatedBytes(
        of: presentation,
        request: request
      )
    )
    if let replaced = cache.updateValue(entry, forKey: request) {
      retainedBytes -= replaced.estimatedBytes
    }
    retainedBytes += entry.estimatedBytes
    evictIfNeeded()
    return presentation
  }

  var occupancy: (entries: Int, bytes: Int) {
    (cache.count, retainedBytes)
  }

  nonisolated private static func renderUncached(
    _ request: MermaidRenderRequest
  ) -> MermaidPresentation {
    let renderer = MermaidRenderer(
      configuration: MermaidConfiguration(
        glyphMode: request.configuration.glyphMode == .ascii ? .ascii : .unicode,
        ambiguousWidth: request.configuration.ambiguousWidth == .wide ? .wide : .narrow
      )
    )
    let metricsReport = renderer.layoutMetrics(for: request.source)
    guard let metrics = metricsReport.output else {
      return unavailable(
        source: request.source,
        diagnostics: metricsReport.diagnostics.map(\.message)
      )
    }

    let selectedWidth = max(1, max(request.width, metrics.minimumWidth))
    let measurement = renderer.measure(request.source, forWidth: selectedWidth)
    let surfaceReport = renderer.renderSurface(request.source, forWidth: selectedWidth)
    guard
      let measuredSize = measurement.output,
      let surface = surfaceReport.output
    else {
      return unavailable(
        source: request.source,
        diagnostics: (measurement.diagnostics + surfaceReport.diagnostics).map(\.message)
      )
    }
    guard
      measuredSize.width == surface.size.width,
      measuredSize.height == surface.size.height
    else {
      return .unavailable(
        diagnostic: "SwiftMermaid measured and rendered different surface sizes."
      )
    }

    let diagnostics = deduplicated(
      metricsReport.diagnostics.map(\.message)
        + measurement.diagnostics.map(\.message)
        + surfaceReport.diagnostics.map(\.message)
    )
    let cells = surface.rows.map { row in
      row.map {
        Self.map(
          $0,
          glyphMode: request.configuration.glyphMode
        )
      }
    }
    return .ready(
      RenderedMermaid(
        width: surface.size.width,
        height: surface.size.height,
        cells: cells,
        diagnostics: diagnostics,
        isPartial: metricsReport.fidelity == .partial
          || measurement.fidelity == .partial
          || surfaceReport.fidelity == .partial
      )
    )
  }

  nonisolated private static func map(
    _ cell: MermaidCell,
    glyphMode: ViewerMermaidGlyphMode
  ) -> MermaidPaintCell {
    switch cell {
    case .empty(let role):
      return MermaidPaintCell(role: map(role))
    case .grapheme(let grapheme, let role, let spanWidth):
      let character = grapheme.first ?? " "
      guard glyphMode == .ascii else {
        return MermaidPaintCell(
          character: character,
          spanWidth: spanWidth,
          role: map(role)
        )
      }
      return MermaidPaintCell(
        character: asciiGlyph(for: character, role: role),
        spanWidth: 1,
        role: map(role)
      )
    case .continuation(let leadColumn, let role):
      guard glyphMode != .ascii else {
        // Replacing a wide source grapheme with a single-cell ASCII fallback
        // leaves its continuation column as ordinary background.
        return MermaidPaintCell(role: map(role))
      }
      return MermaidPaintCell(
        spanWidth: 0,
        continuationLeadX: leadColumn,
        role: map(role)
      )
    }
  }

  nonisolated private static func asciiGlyph(
    for character: Character,
    role: MermaidRole
  ) -> Character {
    if character.unicodeScalars.allSatisfy(\.isASCII) {
      return character
    }
    switch character {
    case "→", "⇒", "▶", "►": return ">"
    case "←", "⇐", "◀", "◄": return "<"
    case "↑", "⇑": return "^"
    case "↓", "⇓": return "v"
    case "─", "━", "═", "╌", "╍", "┄", "┅": return "-"
    case "│", "┃", "║", "╎", "╏", "┆", "┇": return "|"
    default:
      switch role {
      case .border: return "+"
      case .edge: return "-"
      default: return "?"
      }
    }
  }

  nonisolated private static func map(_ role: MermaidRole) -> MermaidPaintRole {
    switch role {
    case .background: .background
    case .border: .border
    case .text: .text
    case .edge: .edge
    case .edgeLabel: .edgeLabel
    case .title: .title
    default: .unknown
    }
  }

  nonisolated private static func unavailable(
    source: String,
    diagnostics: [String]
  ) -> MermaidPresentation {
    .unavailable(
      diagnostic: diagnostics.first ?? "SwiftMermaid could not render this diagram."
    )
  }

  nonisolated private static func deduplicated(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
  }

  private func evictIfNeeded() {
    while cache.count > maximumEntries || retainedBytes > maximumBytes {
      let oldest = cache.min { $0.value.lastAccess < $1.value.lastAccess }?.key
      guard let oldest, let removed = cache.removeValue(forKey: oldest) else {
        return
      }
      retainedBytes -= removed.estimatedBytes
    }
  }

  nonisolated static func estimatedBytes(
    of presentation: MermaidPresentation,
    request: MermaidRenderRequest
  ) -> Int {
    let keyBytes =
      request.source.utf8.count + request.blockID.rawValue.utf8.count
      + MemoryLayout<Int>.size + 2
    let presentationBytes: Int
    switch presentation {
    case .pending:
      presentationBytes = 0
    case .ready(let rendered), .reflowing(let rendered):
      let (cellCount, overflow) = rendered.width.multipliedReportingOverflow(
        by: rendered.height
      )
      guard !overflow else { return 4 * 1_024 * 1_024 + 1 }
      let (cellBytes, byteOverflow) = cellCount.multipliedReportingOverflow(by: 48)
      guard !byteOverflow else { return 4 * 1_024 * 1_024 + 1 }
      presentationBytes =
        cellBytes
        + rendered.diagnostics.reduce(0) { $0 + $1.utf8.count }
    case .unavailable(let diagnostic):
      presentationBytes = diagnostic.utf8.count
    }
    let (total, overflow) = keyBytes.addingReportingOverflow(presentationBytes)
    return overflow ? 4 * 1_024 * 1_024 + 1 : total
  }
}
