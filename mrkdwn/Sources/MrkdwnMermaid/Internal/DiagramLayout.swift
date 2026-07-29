// Layout and glyph concepts adapted from grok-mermaid layout/canvas files at commit 6be6507;
// substantially modified for constrained sizing, family-specific geometry, topology-aware
// routing, structured cells, and allocation-time output budgets.

enum MermaidLayoutResult {
  case success(MermaidSurface)
  case failure(code: MermaidDiagnosticCode, message: String)
}

struct MermaidLayoutEngine {
  let configuration: MermaidConfiguration

  func minimumWidth(for diagram: ParsedMermaidDiagram) -> Int {
    let widestCluster = diagramText(diagram).reduce(into: 1) { result, character in
      result = max(
        result,
        MermaidUnicodeWidth.width(
          of: character,
          ambiguousWidth: configuration.ambiguousWidth
        )
      )
    }
    let familyMinimum: Int
    switch diagram.kind {
    case .sequence:
      familyMinimum = 24
    case .class, .er:
      familyMinimum = 18
    case .flowchart, .state:
      familyMinimum = 16
    case .xy:
      familyMinimum = 12
    }
    return max(familyMinimum, widestCluster + 6)
  }

  func idealWidth(for diagram: ParsedMermaidDiagram) -> Int {
    let width: Int
    switch diagram.kind {
    case .sequence:
      width = max(56, min(6, max(2, diagram.nodes.count)) * 16)
    case .xy:
      width = 72
    case .class, .er:
      let widest = diagram.nodes.map(nodeNaturalWidth).max() ?? 24
      width = max(56, min(120, widest * 2 + 9))
    case .flowchart, .state:
      let widest = diagram.nodes.map(nodeNaturalWidth).max() ?? 20
      width = max(48, min(120, widest * 2 + 9))
    }
    return min(120, max(minimumWidth(for: diagram), width))
  }

  func render(_ diagram: ParsedMermaidDiagram, width: Int) -> MermaidLayoutResult {
    let width = max(minimumWidth(for: diagram), width)
    let maximumCells =
      configuration.safetyLimits.validatedMaximumOutputCells
    guard semanticCellLowerBound(diagram) <= maximumCells else {
      return .failure(
        code: .resourceLimit,
        message:
          "Authored diagram content cannot fit within the configured "
          + "\(maximumCells)-cell output limit."
      )
    }

    var output = MermaidLineAccumulator(
      width: width,
      maximumCells: maximumCells,
      configuration: configuration
    )
    guard
      appendWrapped(
        MermaidStyledLine([
          .init(text: diagram.title ?? defaultTitle(for: diagram), role: .title)
        ]),
        to: &output
      ),
      output.append(.init())
    else {
      return output.failureResult
    }

    let rendered: Bool
    switch diagram.kind {
    case .flowchart, .state:
      rendered = renderFlowOrState(diagram, to: &output)
    case .sequence:
      rendered = renderSequence(diagram, to: &output)
    case .class, .er:
      rendered = renderEntityFamily(diagram, to: &output)
    case .xy:
      rendered = diagram.chart.map { renderChart($0, to: &output) } ?? false
    }
    guard rendered else { return output.failureResult }

    while output.lines.last?.segments.isEmpty == true {
      output.removeLast()
    }
    guard let surface = makeSurface(output.lines, maximumCells: maximumCells) else {
      return .failure(
        code: .resourceLimit,
        message:
          "Rendered diagram exceeds the configured \(maximumCells)-cell output limit."
      )
    }
    return .success(surface)
  }

  private func renderFlowOrState(
    _ diagram: ParsedMermaidDiagram,
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    guard renderSharedTopology(diagram, to: &output) else { return false }
    return appendAnnotations(diagram.annotations, to: &output)
  }

  private func renderSequence(
    _ diagram: ParsedMermaidDiagram,
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    let participants = diagram.nodes
    let count = participants.count
    guard count > 0 else {
      output.recordLayoutFailure("A sequence diagram has no participants.")
      return false
    }
    let gap = 2
    let laneWidth = (output.width - max(0, count - 1) * gap) / max(1, count)
    let fullLifelines = count <= 6 && laneWidth >= 8

    if fullLifelines {
      let headers = participants.map { renderCompactHeader($0, width: laneWidth) }
      let headerHeight = headers.map(\.count).max() ?? 0
      for row in 0..<headerHeight {
        var line = MermaidStyledLine()
        for (index, header) in headers.enumerated() {
          if index > 0 {
            line.append(String(repeating: " ", count: gap), role: .background)
          }
          line.append(
            contentsOf:
              header.indices.contains(row)
              ? header[row].padded(to: laneWidth, configuration: configuration)
              : MermaidStyledLine().padded(to: laneWidth, configuration: configuration)
          )
        }
        guard output.append(line) else { return false }
      }

      let centers = participants.indices.map { index in
        index * (laneWidth + gap) + laneWidth / 2
      }
      let participantIndices = Dictionary(
        uniqueKeysWithValues: participants.enumerated().map { ($0.element.id, $0.offset) }
      )
      for (number, edge) in diagram.edges.enumerated() {
        guard
          let fromIndex = participantIndices[edge.from],
          let toIndex = participantIndices[edge.to]
        else {
          output.recordLayoutFailure("A sequence message references an unknown participant.")
          return false
        }
        guard appendMessageCaption(edge, number: number + 1, to: &output) else { return false }
        let geometry = sequenceGeometryLine(
          centers: centers,
          from: fromIndex,
          to: toIndex,
          edge: edge,
          width: output.width
        )
        guard output.append(geometry) else { return false }
      }
      guard output.append(sequenceLifelineLine(centers: centers, width: output.width)) else {
        return false
      }
    } else {
      guard
        appendWrapped(
          MermaidStyledLine([.init(text: "Participants", role: .title)]),
          to: &output
        )
      else {
        return false
      }
      for (index, participant) in participants.enumerated() {
        guard
          appendWrapped(
            MermaidStyledLine([
              .init(text: "\(index + 1). ", role: .edgeLabel),
              .init(text: "\(participant.label) [\(participant.id)]", role: .text),
            ]),
            to: &output
          )
        else {
          return false
        }
      }
      if !diagram.edges.isEmpty, !output.append(.init()) { return false }
      for (number, edge) in diagram.edges.enumerated() {
        guard
          appendMessageCaption(edge, number: number + 1, to: &output),
          appendCentered(
            "\(verticalGlyph)\(horizontalGlyph)\(horizontalGlyph)\(arrowGlyph)\(verticalGlyph)",
            role: .edge,
            to: &output
          )
        else {
          return false
        }
      }
    }
    return appendAnnotations(diagram.annotations, to: &output)
  }

  private func renderEntityFamily(
    _ diagram: ParsedMermaidDiagram,
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    guard renderSharedTopology(diagram, to: &output) else { return false }
    return appendAnnotations(diagram.annotations, to: &output)
  }

  private func renderSharedTopology(
    _ diagram: ParsedMermaidDiagram,
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    var order = topologyOrder(diagram)
    let direction = (diagram.direction ?? "TD").uppercased()
    if direction == "BT" || direction == "RL" {
      order.reverse()
    }
    let positions = Dictionary(
      uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) }
    )
    var outgoing: [String: [(offset: Int, edge: MermaidEdge)]] = [:]
    for (offset, edge) in diagram.edges.enumerated() {
      guard diagram.node(forID: edge.from) != nil, diagram.node(forID: edge.to) != nil else {
        output.recordLayoutFailure("A topology relation references an unknown node.")
        return false
      }
      outgoing[edge.from, default: []].append((offset, edge))
    }

    for (nodeOffset, id) in order.enumerated() {
      guard let node = diagram.node(forID: id) else {
        output.recordLayoutFailure("A topology node could not be placed.")
        return false
      }
      guard appendBox(node, to: &output) else { return false }
      let routes = (outgoing[id] ?? []).sorted { left, right in
        let leftTarget = positions[left.edge.to] ?? Int.max
        let rightTarget = positions[right.edge.to] ?? Int.max
        if leftTarget != rightTarget { return leftTarget < rightTarget }
        return left.offset < right.offset
      }
      for (routeOffset, route) in routes.enumerated() {
        let backEdge = (positions[route.edge.to] ?? 0) <= (positions[id] ?? 0)
        guard
          appendTopologyRoute(
            route.edge,
            isLast: routeOffset == routes.count - 1,
            direction: direction,
            backEdge: backEdge,
            to: &output
          )
        else {
          return false
        }
      }
      if nodeOffset + 1 < order.count, !output.append(.init()) { return false }
    }
    return true
  }

  private func appendTopologyRoute(
    _ edge: MermaidEdge,
    isLast: Bool,
    direction: String,
    backEdge: Bool,
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    let branch: String
    if configuration.glyphMode == .ascii {
      branch = "+-"
    } else {
      branch = isLast ? "└─" : "├─"
    }
    let axisGlyph: String
    switch direction {
    case "RL":
      axisGlyph = leftArrowGlyph
    case "BT":
      axisGlyph = upArrowGlyph
    case "TD", "TB":
      axisGlyph = downArrowGlyph
    default:
      axisGlyph = arrowGlyph
    }
    var line = MermaidStyledLine()
    line.append(branch + axisGlyph + " ", role: .edge)
    line.append("[\(edge.connector)] ", role: .edge)
    line.append(edge.to, role: .text)
    if let label = edge.label, !label.isEmpty {
      line.append(": ", role: .edge)
      line.append(label, role: .edgeLabel)
    }
    if backEdge {
      line.append(" " + backwardRouteGlyph, role: .edge)
    }
    return appendWrapped(line, to: &output)
  }

  private func renderChart(
    _ chart: MermaidChart,
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    let allValues = chart.series.flatMap(\.values)
    guard let observedMinimum = allValues.min(), let observedMaximum = allValues.max() else {
      output.recordLayoutFailure("An XY chart has no finite values.")
      return false
    }
    var minimum = chart.yMinimum ?? min(0, observedMinimum)
    var maximum = chart.yMaximum ?? max(0, observedMaximum)
    if !(minimum < maximum) {
      minimum = min(0, observedMinimum)
      maximum = max(1, observedMaximum)
    }
    guard minimum.isFinite, maximum.isFinite, minimum < maximum else {
      output.recordLayoutFailure("The XY axis does not have finite, ordered bounds.")
      return false
    }

    let plotHeight = 8
    let axisWidth = 7
    let plotWidth = max(4, output.width - axisWidth - 1)
    let count = max(chart.xLabels.count, chart.series.map(\.values.count).max() ?? 0)
    let plotColumns = max(1, min(count, plotWidth))
    let baseline = chartLevel(
      for: min(max(0, minimum), maximum),
      minimum: minimum,
      maximum: maximum,
      height: plotHeight
    )
    let buckets = chart.series.map { series in
      aggregate(
        series,
        sourceCount: count,
        columns: plotColumns,
        minimum: minimum,
        maximum: maximum,
        height: plotHeight
      )
    }

    for row in stride(from: plotHeight, through: 0, by: -1) {
      let threshold = interpolate(minimum, maximum, fraction: Double(row) / Double(plotHeight))
      var line = MermaidStyledLine([
        .init(
          text: leftPad(axisNumber(threshold, width: axisWidth), to: axisWidth), role: .edgeLabel),
        .init(text: verticalGlyph, role: .border),
      ])
      for column in 0..<plotColumns {
        var glyph = " "
        var role = MermaidRole.background
        for (seriesIndex, series) in chart.series.enumerated() {
          let bucket = buckets[seriesIndex][column]
          if series.isLine {
            if bucket.minimumLevel <= row, row <= bucket.maximumLevel {
              glyph = row == bucket.representativeLevel ? linePointGlyph : verticalGlyph
              role = .edge
            }
          } else {
            let lower = min(baseline, bucket.minimumLevel)
            let upper = max(baseline, bucket.maximumLevel)
            if lower <= row, row <= upper, row != baseline {
              glyph = barGlyph
              role = .border
            }
          }
        }
        line.append(glyph, role: role)
      }
      if plotColumns < plotWidth {
        line.append(
          String(repeating: " ", count: plotWidth - plotColumns),
          role: .background
        )
      }
      guard output.append(line) else { return false }
    }
    guard
      output.append(
        MermaidStyledLine([
          .init(text: String(repeating: " ", count: axisWidth), role: .background),
          .init(
            text: bottomLeftAxisGlyph + String(repeating: horizontalGlyph, count: plotWidth),
            role: .border
          ),
        ])
      )
    else {
      return false
    }

    if !chart.xLabels.isEmpty {
      guard
        output.append(.init()),
        appendWrapped(
          MermaidStyledLine([
            .init(text: "X: ", role: .edgeLabel),
            .init(text: chart.xLabels.joined(separator: " · "), role: .text),
          ]),
          to: &output
        )
      else {
        return false
      }
    }
    guard
      appendWrapped(
        yAxisLegend(minimum: minimum, maximum: maximum),
        to: &output
      )
    else {
      return false
    }
    for series in chart.series {
      guard
        appendWrapped(
          MermaidStyledLine([
            .init(text: "\(series.name): ", role: .edgeLabel),
            .init(text: series.values.map(numberText).joined(separator: ", "), role: .text),
          ]),
          to: &output
        )
      else {
        return false
      }
    }
    return true
  }

  private func aggregate(
    _ series: MermaidChartSeries,
    sourceCount: Int,
    columns: Int,
    minimum: Double,
    maximum: Double,
    height: Int
  ) -> [ChartBucket] {
    (0..<columns).map { column in
      let lower = column * sourceCount / columns
      let upper = max(lower + 1, (column + 1) * sourceCount / columns)
      let values = (lower..<upper).compactMap { index in
        series.values.indices.contains(index) ? series.values[index] : nil
      }
      guard let smallest = values.min(), let largest = values.max() else {
        let level = chartLevel(for: minimum, minimum: minimum, maximum: maximum, height: height)
        return ChartBucket(
          minimumLevel: level,
          maximumLevel: level,
          representativeLevel: level
        )
      }
      let representative = values[values.count / 2]
      return ChartBucket(
        minimumLevel: chartLevel(
          for: smallest,
          minimum: minimum,
          maximum: maximum,
          height: height
        ),
        maximumLevel: chartLevel(
          for: largest,
          minimum: minimum,
          maximum: maximum,
          height: height
        ),
        representativeLevel: chartLevel(
          for: representative,
          minimum: minimum,
          maximum: maximum,
          height: height
        )
      )
    }
  }

  private func chartLevel(
    for value: Double,
    minimum: Double,
    maximum: Double,
    height: Int
  ) -> Int {
    let scale = max(abs(minimum), abs(maximum), abs(value), 1)
    let normalizedMinimum = minimum / scale
    let normalizedMaximum = maximum / scale
    let normalizedValue = value / scale
    let denominator = normalizedMaximum - normalizedMinimum
    guard denominator.isFinite, denominator > 0 else { return 0 }
    let fraction = min(1, max(0, (normalizedValue - normalizedMinimum) / denominator))
    return min(height, max(0, Int((fraction * Double(height)).rounded())))
  }

  private func interpolate(_ lower: Double, _ upper: Double, fraction: Double) -> Double {
    if (upper - lower).isFinite {
      return lower + (upper - lower) * fraction
    }
    return lower * (1 - fraction) + upper * fraction
  }

  private func renderBox(_ node: MermaidNode, width: Int) -> [MermaidStyledLine] {
    let width = max(6, width)
    let insideWidth = width - 2
    let frame = nodeFrame(for: node)

    var rows = [
      MermaidStyledLine([
        .init(text: frame.topLeft, role: .border),
        .init(text: String(repeating: frame.horizontal, count: insideWidth), role: .border),
        .init(text: frame.topRight, role: .border),
      ])
    ]
    if frame.hasCylinderCap {
      rows.append(
        MermaidStyledLine([
          .init(text: frame.middleLeft, role: .border),
          .init(text: String(repeating: frame.horizontal, count: insideWidth), role: .border),
          .init(text: frame.middleRight, role: .border),
        ])
      )
    }
    var label = MermaidStyledLine()
    switch node.kind {
    case .start:
      label.append(configuration.glyphMode == .ascii ? "*" : "●", role: .edge)
    case .end:
      label.append(configuration.glyphMode == .ascii ? "*" : "◎", role: .edge)
    case .choice:
      label.append(configuration.glyphMode == .ascii ? "<>" : "◇", role: .edge)
    case .participant:
      label.append(configuration.glyphMode == .ascii ? "@" : "♙", role: .edge)
    case .entity, .normal:
      break
    }
    if !label.segments.isEmpty {
      label.append(" ", role: .background)
    }
    label.append(node.label, role: .text)
    if node.label != node.id, node.kind != .start, node.kind != .end {
      label.append(" [\(node.id)]", role: .text)
    }

    for line in wrap(label, at: max(1, insideWidth - 2)) {
      rows.append(
        boxContentLine(
          line,
          width: insideWidth,
          leftBorder: frame.contentLeft,
          rightBorder: frame.contentRight
        )
      )
    }
    if !node.details.isEmpty {
      rows.append(
        MermaidStyledLine([
          .init(text: frame.middleLeft, role: .border),
          .init(text: String(repeating: frame.horizontal, count: insideWidth), role: .border),
          .init(text: frame.middleRight, role: .border),
        ])
      )
      for detail in node.details {
        for line in wrap(
          MermaidStyledLine([.init(text: detail, role: .text)]),
          at: max(1, insideWidth - 2)
        ) {
          rows.append(
            boxContentLine(
              line,
              width: insideWidth,
              leftBorder: frame.contentLeft,
              rightBorder: frame.contentRight
            )
          )
        }
      }
    }
    rows.append(
      MermaidStyledLine([
        .init(text: frame.bottomLeft, role: .border),
        .init(text: String(repeating: frame.horizontal, count: insideWidth), role: .border),
        .init(text: frame.bottomRight, role: .border),
      ])
    )
    return rows
  }

  private func nodeFrame(for node: MermaidNode) -> MermaidNodeFrame {
    if node.kind != .normal {
      return configuration.glyphMode == .ascii ? .asciiRectangle : .unicodeRectangle
    }
    switch (configuration.glyphMode, node.shape) {
    case (.ascii, .rectangle):
      return .asciiRectangle
    case (.ascii, .rounded):
      return .init(".", ".", "'", "'", "|", "|", "+", "+", "-")
    case (.ascii, .stadium):
      return .init("(", ")", "(", ")", "(", ")", "(", ")", "-")
    case (.ascii, .subroutine):
      return .init("[", "]", "[", "]", "[", "]", "[", "]", "=")
    case (.ascii, .cylinder):
      return .init("(", ")", "(", ")", "|", "|", "+", "+", "-", hasCylinderCap: true)
    case (.ascii, .circle):
      return .init("/", "\\", "\\", "/", "(", ")", "+", "+", "-")
    case (.ascii, .diamond):
      return .init("/", "\\", "\\", "/", "<", ">", "+", "+", "-")
    case (.ascii, .hexagon):
      return .init("/", "\\", "\\", "/", "|", "|", "+", "+", "-")
    case (.ascii, .asymmetric):
      return .init(">", "]", ">", "]", ">", "]", ">", "]", "-")
    case (.unicode, .rectangle):
      return .unicodeRectangle
    case (.unicode, .rounded):
      return .init("╭", "╮", "╰", "╯", "│", "│", "├", "┤", "─")
    case (.unicode, .stadium):
      return .init("(", ")", "(", ")", "(", ")", "(", ")", "─")
    case (.unicode, .subroutine):
      return .init("╔", "╗", "╚", "╝", "║", "║", "╠", "╣", "═")
    case (.unicode, .cylinder):
      return .init(
        "╭", "╮", "╰", "╯", "│", "│", "├", "┤", "─",
        hasCylinderCap: true
      )
    case (.unicode, .circle):
      return .init("╭", "╮", "╰", "╯", "(", ")", "├", "┤", "─")
    case (.unicode, .diamond):
      return .init("╱", "╲", "╲", "╱", "⟨", "⟩", "◆", "◆", "─")
    case (.unicode, .hexagon):
      return .init("╱", "╲", "╲", "╱", "│", "│", "├", "┤", "─")
    case (.unicode, .asymmetric):
      return .init(">", "┐", ">", "┘", ">", "│", ">", "┤", "─")
    }
  }

  private func appendBox(
    _ node: MermaidNode,
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    for line in renderBox(node, width: output.width) {
      guard output.append(line) else { return false }
    }
    return true
  }

  private func renderCompactHeader(
    _ node: MermaidNode,
    width: Int
  ) -> [MermaidStyledLine] {
    renderBox(
      MermaidNode(id: node.id, label: node.label, kind: .participant),
      width: width
    )
  }

  private func boxContentLine(
    _ content: MermaidStyledLine,
    width: Int,
    leftBorder: String,
    rightBorder: String
  ) -> MermaidStyledLine {
    let contentWidth = content.displayWidth(configuration: configuration)
    var line = MermaidStyledLine([
      .init(text: leftBorder, role: .border),
      .init(text: " ", role: .background),
    ])
    line.append(contentsOf: content)
    line.append(
      String(repeating: " ", count: max(0, width - contentWidth - 1)),
      role: .background
    )
    line.append(rightBorder, role: .border)
    return line
  }

  private func yAxisLegend(minimum: Double, maximum: Double) -> MermaidStyledLine {
    MermaidStyledLine([
      .init(text: "Y: ", role: .edgeLabel),
      .init(text: "\(numberText(minimum)) ", role: .text),
      .init(text: forwardRouteGlyph + arrowGlyph, role: .edge),
      .init(text: " \(numberText(maximum))", role: .text),
    ])
  }

  private func appendMessageCaption(
    _ edge: MermaidEdge,
    number: Int,
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    var line = MermaidStyledLine([
      .init(text: "\(number). ", role: .edgeLabel),
      .init(text: edge.from, role: .text),
      .init(text: " \(edge.connector) ", role: .edge),
      .init(text: edge.to, role: .text),
    ])
    if let label = edge.label, !label.isEmpty {
      line.append(": ", role: .edge)
      line.append(label, role: .edgeLabel)
    }
    return appendWrapped(line, to: &output)
  }

  private func sequenceGeometryLine(
    centers: [Int],
    from: Int,
    to: Int,
    edge: MermaidEdge,
    width: Int
  ) -> MermaidStyledLine {
    var cells = Array(
      repeating: MermaidPaintCell(text: " ", role: .background),
      count: width
    )
    for center in centers where cells.indices.contains(center) {
      cells[center] = .init(text: verticalGlyph, role: .edge)
    }
    let source = centers[from]
    let target = centers[to]
    if source == target {
      cells[source] = .init(
        text: configuration.glyphMode == .ascii ? "@" : "↻",
        role: .edge
      )
    } else {
      let lower = min(source, target)
      let upper = max(source, target)
      for column in lower...upper {
        cells[column] = .init(text: horizontalGlyph, role: .edge)
      }
      cells[source] = .init(
        text: edge.startEndpoint == .none ? teeGlyph : arrowToward(source, from: target),
        role: .edge
      )
      cells[target] = .init(
        text: edge.endEndpoint == .none ? teeGlyph : arrowToward(target, from: source),
        role: .edge
      )
    }
    return styledLine(cells)
  }

  private func sequenceLifelineLine(
    centers: [Int],
    width: Int
  ) -> MermaidStyledLine {
    var cells = Array(
      repeating: MermaidPaintCell(text: " ", role: .background),
      count: width
    )
    for center in centers where cells.indices.contains(center) {
      cells[center] = .init(text: verticalGlyph, role: .edge)
    }
    return styledLine(cells)
  }

  private func styledLine(_ cells: [MermaidPaintCell]) -> MermaidStyledLine {
    var line = MermaidStyledLine()
    for cell in cells {
      line.append(cell.text, role: cell.role)
    }
    return line
  }

  private func arrowToward(_ destination: Int, from source: Int) -> String {
    if configuration.glyphMode == .ascii {
      return destination < source ? "<" : ">"
    }
    return destination < source ? "◀" : "▶"
  }

  private func appendAnnotations(
    _ annotations: [String],
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    guard !annotations.isEmpty else { return true }
    guard
      output.append(.init()),
      appendWrapped(
        MermaidStyledLine([.init(text: "Notes", role: .title)]),
        to: &output
      )
    else {
      return false
    }
    for annotation in annotations {
      guard
        appendWrapped(
          MermaidStyledLine([
            .init(text: "\(configuration.glyphMode == .ascii ? "*" : "•") ", role: .edge),
            .init(text: annotation, role: .edgeLabel),
          ]),
          to: &output
        )
      else {
        return false
      }
    }
    return true
  }

  private func appendCentered(
    _ text: String,
    role: MermaidRole,
    to output: inout MermaidLineAccumulator
  ) -> Bool {
    appendWrapped(
      MermaidStyledLine([.init(text: text, role: role)]),
      to: &output,
      centered: true
    )
  }

  private func appendWrapped(
    _ line: MermaidStyledLine,
    to output: inout MermaidLineAccumulator,
    centered: Bool = false
  ) -> Bool {
    for wrapped in wrap(line, at: output.width) {
      let finalLine = centered ? center(wrapped, in: output.width) : wrapped
      guard output.append(finalLine) else { return false }
    }
    return true
  }

  private func center(_ line: MermaidStyledLine, in width: Int) -> MermaidStyledLine {
    let lineWidth = line.displayWidth(configuration: configuration)
    let prefix = max(0, (width - lineWidth) / 2)
    var result = MermaidStyledLine()
    result.append(String(repeating: " ", count: prefix), role: .background)
    result.append(contentsOf: line)
    return result
  }

  private func makeSurface(
    _ lines: [MermaidStyledLine],
    maximumCells: Int
  ) -> MermaidSurface? {
    var converted: [[MermaidCell]] = []
    converted.reserveCapacity(lines.count)
    var maximumWidth = 0

    for line in lines {
      var cells: [MermaidCell] = []
      for segment in line.segments {
        for character in segment.text {
          let mapped = mermaidSerializedGrapheme(
            String(character),
            role: segment.role,
            glyphMode: configuration.glyphMode
          )
          for paintedCharacter in mapped {
            let spanWidth = mermaidStyledWidth(
              of: paintedCharacter,
              role: segment.role,
              configuration: configuration
            )
            guard spanWidth > 0 else { continue }
            let (nextCount, overflow) = cells.count.addingReportingOverflow(spanWidth)
            guard !overflow, nextCount <= maximumCells else {
              return nil
            }
            let lead = cells.count
            cells.append(
              .grapheme(String(paintedCharacter), role: segment.role, spanWidth: spanWidth)
            )
            if spanWidth > 1 {
              for _ in 1..<spanWidth {
                cells.append(.continuation(leadColumn: lead, role: segment.role))
              }
            }
          }
        }
      }
      maximumWidth = max(maximumWidth, cells.count)
      let (projected, overflow) = maximumWidth.multipliedReportingOverflow(
        by: converted.count + 1
      )
      guard !overflow, projected <= maximumCells else { return nil }
      converted.append(cells)
    }

    let (finalCells, overflow) = maximumWidth.multipliedReportingOverflow(by: converted.count)
    guard !overflow, finalCells <= maximumCells else { return nil }
    let rectangular = converted.map { row in
      row
        + Array(
          repeating: MermaidCell.empty(role: .background),
          count: maximumWidth - row.count
        )
    }
    return MermaidSurface(validating: rectangular)
  }

  private func wrap(_ line: MermaidStyledLine, at width: Int) -> [MermaidStyledLine] {
    guard line.displayWidth(configuration: configuration) > width else { return [line] }
    var result: [MermaidStyledLine] = []
    var current = MermaidStyledLine()
    var currentWidth = 0

    for segment in line.segments {
      for character in segment.text {
        let characterWidth = mermaidStyledWidth(
          of: character,
          role: segment.role,
          configuration: configuration
        )
        if currentWidth > 0, currentWidth + characterWidth > width {
          result.append(current)
          current = MermaidStyledLine()
          currentWidth = 0
        }
        current.append(String(character), role: segment.role)
        currentWidth += characterWidth
      }
    }
    if !current.segments.isEmpty {
      result.append(current)
    }
    return result
  }

  private func wrapText(_ text: String, at width: Int) -> [String] {
    guard width > 0 else { return [text] }
    var lines: [String] = []
    var current = ""
    var currentWidth = 0
    let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    if words.isEmpty { return [""] }

    for word in words {
      let wordWidth = MermaidUnicodeWidth.displayWidth(
        of: word,
        ambiguousWidth: configuration.ambiguousWidth
      )
      if !current.isEmpty, currentWidth + 1 + wordWidth <= width {
        current += " " + word
        currentWidth += 1 + wordWidth
      } else if wordWidth <= width {
        if !current.isEmpty { lines.append(current) }
        current = word
        currentWidth = wordWidth
      } else {
        if !current.isEmpty {
          lines.append(current)
          current = ""
          currentWidth = 0
        }
        for character in word {
          let characterWidth = MermaidUnicodeWidth.width(
            of: character,
            ambiguousWidth: configuration.ambiguousWidth
          )
          if currentWidth > 0, currentWidth + characterWidth > width {
            lines.append(current)
            current = ""
            currentWidth = 0
          }
          current.append(character)
          currentWidth += characterWidth
        }
      }
    }
    if !current.isEmpty { lines.append(current) }
    return lines.isEmpty ? [""] : lines
  }

  private func topologyOrder(_ diagram: ParsedMermaidDiagram) -> [String] {
    let nodeIDs = diagram.nodes.map(\.id)
    let known = Set(nodeIDs)
    var indegree = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, 0) })
    var adjacency = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, [String]()) })
    for edge in diagram.edges where known.contains(edge.from) && known.contains(edge.to) {
      adjacency[edge.from, default: []].append(edge.to)
      indegree[edge.to, default: 0] += 1
    }

    var queue = nodeIDs.filter { indegree[$0] == 0 }
    var head = 0
    var result: [String] = []
    result.reserveCapacity(nodeIDs.count)
    while head < queue.count {
      let node = queue[head]
      head += 1
      result.append(node)
      for target in adjacency[node] ?? [] {
        indegree[target, default: 0] -= 1
        if indegree[target] == 0 {
          queue.append(target)
        }
      }
    }
    let visited = Set(result)
    result.append(contentsOf: nodeIDs.filter { !visited.contains($0) })
    return result
  }

  private func semanticCellLowerBound(_ diagram: ParsedMermaidDiagram) -> Int {
    var total = 0
    let values =
      [diagram.title ?? defaultTitle(for: diagram)]
      + diagram.nodes.flatMap { [$0.id, $0.label] + $0.details }
      + diagram.edges.flatMap { [$0.from, $0.connector, $0.to, $0.label ?? ""] }
      + diagram.annotations
      + (diagram.chart?.xLabels ?? [])
      + (diagram.chart?.series.flatMap { series in
        [series.name] + series.values.map(numberText)
      } ?? [])
    for value in values {
      let width = MermaidUnicodeWidth.displayWidth(
        of: value,
        ambiguousWidth: configuration.ambiguousWidth
      )
      let (next, overflow) = total.addingReportingOverflow(width)
      if overflow { return Int.max }
      total = next
    }
    return total
  }

  private func nodeNaturalWidth(_ node: MermaidNode) -> Int {
    let contents = [node.label] + node.details
    let widest =
      contents.map {
        MermaidUnicodeWidth.displayWidth(
          of: $0,
          ambiguousWidth: configuration.ambiguousWidth
        )
      }.max() ?? 1
    return min(40, max(12, widest + 4))
  }

  private func diagramText(_ diagram: ParsedMermaidDiagram) -> String {
    var result = diagram.nodes.flatMap { [$0.label] + $0.details }.joined(separator: " ")
    result += " " + diagram.edges.compactMap(\.label).joined(separator: " ")
    result += " " + diagram.annotations.joined(separator: " ")
    if let chart = diagram.chart {
      result += " " + chart.xLabels.joined(separator: " ")
    }
    return result
  }

  private func defaultTitle(for diagram: ParsedMermaidDiagram) -> String {
    switch diagram.kind {
    case .flowchart:
      "Flowchart\(diagram.direction.map { " · \($0)" } ?? "")"
    case .state:
      "State diagram"
    case .sequence:
      "Sequence diagram"
    case .class:
      "Class diagram"
    case .er:
      "Entity relationship diagram"
    case .xy:
      "XY chart"
    }
  }

  private func numberText(_ number: Double) -> String {
    guard number.isFinite else { return "invalid" }
    if number.rounded() == number, number > Double(Int.min), number < Double(Int.max) {
      return String(Int(number))
    }
    return String(number)
  }

  private func axisNumber(_ number: Double, width: Int) -> String {
    let text = numberText(number)
    guard text.count > width else { return text }
    return String(text.prefix(width))
  }

  private func leftPad(_ text: String, to width: Int) -> String {
    let displayWidth = MermaidUnicodeWidth.displayWidth(
      of: text,
      ambiguousWidth: configuration.ambiguousWidth
    )
    return String(repeating: " ", count: max(0, width - displayWidth)) + text
  }

  private var horizontalGlyph: String {
    configuration.glyphMode == .ascii ? "-" : "─"
  }

  private var verticalGlyph: String {
    configuration.glyphMode == .ascii ? "|" : "│"
  }

  private var forwardRouteGlyph: String {
    configuration.glyphMode == .ascii ? "-" : "─"
  }

  private var backwardRouteGlyph: String {
    configuration.glyphMode == .ascii ? "<" : "↶"
  }

  private var arrowGlyph: String {
    configuration.glyphMode == .ascii ? ">" : "▶"
  }

  private var leftArrowGlyph: String {
    configuration.glyphMode == .ascii ? "<" : "◀"
  }

  private var downArrowGlyph: String {
    configuration.glyphMode == .ascii ? "v" : "▼"
  }

  private var upArrowGlyph: String {
    configuration.glyphMode == .ascii ? "^" : "▲"
  }

  private var teeGlyph: String {
    configuration.glyphMode == .ascii ? "+" : "┼"
  }

  private var linePointGlyph: String {
    configuration.glyphMode == .ascii ? "*" : "●"
  }

  private var barGlyph: String {
    configuration.glyphMode == .ascii ? "#" : "█"
  }

  private var bottomLeftAxisGlyph: String {
    configuration.glyphMode == .ascii ? "+" : "└"
  }
}

private struct MermaidNodeFrame {
  var topLeft: String
  var topRight: String
  var bottomLeft: String
  var bottomRight: String
  var contentLeft: String
  var contentRight: String
  var middleLeft: String
  var middleRight: String
  var horizontal: String
  var hasCylinderCap: Bool

  init(
    _ topLeft: String,
    _ topRight: String,
    _ bottomLeft: String,
    _ bottomRight: String,
    _ contentLeft: String,
    _ contentRight: String,
    _ middleLeft: String,
    _ middleRight: String,
    _ horizontal: String,
    hasCylinderCap: Bool = false
  ) {
    self.topLeft = topLeft
    self.topRight = topRight
    self.bottomLeft = bottomLeft
    self.bottomRight = bottomRight
    self.contentLeft = contentLeft
    self.contentRight = contentRight
    self.middleLeft = middleLeft
    self.middleRight = middleRight
    self.horizontal = horizontal
    self.hasCylinderCap = hasCylinderCap
  }

  static let asciiRectangle = Self("+", "+", "+", "+", "|", "|", "+", "+", "-")
  static let unicodeRectangle = Self("┌", "┐", "└", "┘", "│", "│", "├", "┤", "─")
}

private struct ChartBucket {
  var minimumLevel: Int
  var maximumLevel: Int
  var representativeLevel: Int
}

private struct MermaidPaintCell {
  var text: String
  var role: MermaidRole
}

private struct MermaidStyledSegment {
  var text: String
  var role: MermaidRole
}

private struct MermaidStyledLine {
  var segments: [MermaidStyledSegment]

  init(_ segments: [MermaidStyledSegment] = []) {
    self.segments = segments
  }

  mutating func append(_ text: String, role: MermaidRole) {
    guard !text.isEmpty else { return }
    if let last = segments.indices.last, segments[last].role == role {
      segments[last].text += text
    } else {
      segments.append(.init(text: text, role: role))
    }
  }

  mutating func append(contentsOf line: MermaidStyledLine) {
    for segment in line.segments {
      append(segment.text, role: segment.role)
    }
  }

  func displayWidth(configuration: MermaidConfiguration) -> Int {
    segments.reduce(into: 0) { result, segment in
      for character in segment.text {
        result += mermaidStyledWidth(
          of: character,
          role: segment.role,
          configuration: configuration
        )
      }
    }
  }

  func padded(
    to width: Int,
    configuration: MermaidConfiguration
  ) -> MermaidStyledLine {
    var result = self
    result.append(
      String(repeating: " ", count: max(0, width - displayWidth(configuration: configuration))),
      role: .background
    )
    return result
  }
}

private func mermaidStyledWidth(
  of character: Character,
  role: MermaidRole,
  configuration: MermaidConfiguration
) -> Int {
  if role == .border || role == .edge {
    switch character {
    case "─", "━", "╌", "═", "│", "┃", "╎", "║", "┌", "┐", "└", "┘", "├",
      "┤", "┬", "┴", "┼", "╭", "╮", "╰", "╯", "╔", "╗", "╚", "╝", "╠", "╣",
      "▶", "▷", "►", "◀", "◁", "◄", "▲", "△", "▼", "▽", "↶", "●", "○",
      "◎", "◆", "◇", "♙", "█", "•", "↻", "╱", "╲", "⟨", "⟩":
      return 1
    default:
      break
    }
  }
  return MermaidUnicodeWidth.width(
    of: character,
    ambiguousWidth: configuration.ambiguousWidth
  )
}

private struct MermaidLineAccumulator {
  let width: Int
  let maximumCells: Int
  let configuration: MermaidConfiguration
  private(set) var lines: [MermaidStyledLine] = []
  private(set) var failure: (code: MermaidDiagnosticCode, message: String)?
  private var maximumLineWidth = 0

  init(
    width: Int,
    maximumCells: Int,
    configuration: MermaidConfiguration
  ) {
    self.width = width
    self.maximumCells = maximumCells
    self.configuration = configuration
  }

  mutating func append(_ line: MermaidStyledLine) -> Bool {
    guard failure == nil else { return false }
    let lineWidth = line.displayWidth(configuration: configuration)
    guard lineWidth <= width else {
      recordLayoutFailure(
        "A layout row measured \(lineWidth) columns for a \(width)-column plan."
      )
      return false
    }
    let newMaximum = max(maximumLineWidth, lineWidth)
    let (projectedCells, overflow) = newMaximum.multipliedReportingOverflow(
      by: lines.count + 1
    )
    guard !overflow, projectedCells <= maximumCells else {
      failure = (
        .resourceLimit,
        "Rendered diagram exceeds the configured \(maximumCells)-cell output limit."
      )
      return false
    }
    lines.append(line)
    maximumLineWidth = newMaximum
    return true
  }

  mutating func removeLast() {
    guard !lines.isEmpty else { return }
    lines.removeLast()
    maximumLineWidth =
      lines.map { $0.displayWidth(configuration: configuration) }.max() ?? 0
  }

  mutating func recordLayoutFailure(_ message: String) {
    guard failure == nil else { return }
    failure = (.layoutFailure, message)
  }

  var failureResult: MermaidLayoutResult {
    let failure =
      failure
      ?? (
        .layoutFailure,
        "The diagram could not be represented by the selected family layout."
      )
    return .failure(code: failure.code, message: failure.message)
  }
}
