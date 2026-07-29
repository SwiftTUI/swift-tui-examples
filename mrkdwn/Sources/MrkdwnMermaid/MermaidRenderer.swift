public struct MermaidRenderer: Sendable {
  public let configuration: MermaidConfiguration

  public init(configuration: MermaidConfiguration = .init()) {
    self.configuration = configuration
  }

  public func layoutMetrics(
    for source: String
  ) -> MermaidReport<MermaidLayoutMetrics> {
    switch prepare(source) {
    case .failure(let report):
      return unavailable(from: report)
    case .success(let prepared):
      let engine = MermaidLayoutEngine(configuration: configuration)
      let minimumWidth = engine.minimumWidth(for: prepared.diagram)
      let idealSurface: MermaidSurface
      switch engine.render(
        prepared.diagram,
        width: engine.idealWidth(for: prepared.diagram)
      ) {
      case .success(let surface):
        idealSurface = surface
      case .failure(let code, let message):
        return unavailable(code: code, message: message)
      }
      return available(
        MermaidLayoutMetrics(minimumWidth: minimumWidth, idealSize: idealSurface.size),
        diagnostics: prepared.diagnostics
      )
    }
  }

  public func measure(
    _ source: String,
    forWidth width: Int
  ) -> MermaidReport<MermaidSize> {
    let report = resolveSurface(source, width: width)
    guard let surface = report.output else {
      return unavailable(from: report)
    }
    return MermaidReport(
      output: surface.size,
      diagnostics: report.diagnostics,
      fidelity: report.fidelity
    )
  }

  public func renderSurface(
    _ source: String,
    forWidth width: Int
  ) -> MermaidReport<MermaidSurface> {
    resolveSurface(source, width: width)
  }

  private func resolveSurface(
    _ source: String,
    width: Int
  ) -> MermaidReport<MermaidSurface> {
    switch prepare(source) {
    case .failure(let report):
      return report
    case .success(let prepared):
      let engine = MermaidLayoutEngine(configuration: configuration)
      let minimumWidth = engine.minimumWidth(for: prepared.diagram)
      var diagnostics = prepared.diagnostics
      let normalizedWidth: Int
      if width < minimumWidth {
        normalizedWidth = minimumWidth
        diagnostics.append(
          MermaidDiagnostic(
            code: .widthClamped,
            message:
              "Requested width \(width) is below the diagram minimum of \(minimumWidth); "
              + "the minimum width was used."
          )
        )
      } else {
        normalizedWidth = width
      }

      let idealSize: MermaidSize
      switch engine.render(
        prepared.diagram,
        width: engine.idealWidth(for: prepared.diagram)
      ) {
      case .success(let idealSurface):
        idealSize = idealSurface.size
        let selectedWidth = min(max(minimumWidth, normalizedWidth), idealSize.width)
        if selectedWidth == idealSize.width {
          return available(idealSurface, diagnostics: diagnostics)
        }
      case .failure(let code, let message):
        return unavailable(code: code, message: message)
      }

      let selectedWidth = min(max(minimumWidth, normalizedWidth), idealSize.width)
      switch engine.render(prepared.diagram, width: selectedWidth) {
      case .success(let surface):
        return available(surface, diagnostics: diagnostics)
      case .failure(let code, let message):
        return unavailable(code: code, message: message)
      }
    }
  }

  private func prepare(_ source: String) -> Preparation {
    let maximumInputBytes =
      configuration.safetyLimits.validatedMaximumInputBytes
    guard source.utf8.count <= maximumInputBytes else {
      return .failure(
        unavailable(
          code: .resourceLimit,
          message:
            "Diagram input is \(source.utf8.count) bytes; the configured limit is "
            + "\(maximumInputBytes) bytes."
        )
      )
    }
    guard !MermaidUnicodeWidth.containsBidiControl(source) else {
      return .failure(
        unavailable(
          code: .bidiControlUnsupported,
          message: "Unicode bidirectional control characters are not accepted in diagrams."
        )
      )
    }
    guard !MermaidUnicodeWidth.containsRejectedControl(source) else {
      return .failure(
        unavailable(
          code: .controlCharacterUnsupported,
          message: "C0, C1, and escape control characters are not accepted in diagrams."
        )
      )
    }
    guard !MermaidUnicodeWidth.containsStandaloneZeroWidthCharacter(source) else {
      return .failure(
        unavailable(
          code: .controlCharacterUnsupported,
          message: "Standalone zero-width formatting characters are not accepted in diagrams."
        )
      )
    }

    var normalized = normalizeNewlines(source)
    var diagnostics: [MermaidDiagnostic] = []
    if normalized.firstIndex(of: "\t") != nil {
      normalized = replacingTabs(in: normalized)
      diagnostics.append(
        MermaidDiagnostic(
          code: .controlCharacterEscaped,
          message: "Tab characters were expanded to four spaces before parsing."
        )
      )
    }
    if MermaidUnicodeWidth.containsStrongRTL(normalized) {
      diagnostics.append(
        MermaidDiagnostic(
          code: .rtlVisualOrderUnsupported,
          message:
            "Right-to-left text is preserved in logical source order; visual bidi ordering "
            + "is not implemented."
        )
      )
    }

    let parsed = MermaidDiagramParser(
      limits: MermaidParserLimits(
        maximumDiagnostics:
          configuration.safetyLimits.validatedMaximumDiagnostics,
        maximumDiagnosticBytes:
          configuration.safetyLimits.validatedMaximumDiagnosticMessageBytes
      )
    ).parse(normalized)
    guard let diagram = parsed.output else {
      return .failure(
        MermaidReport(
          output: nil,
          diagnostics: bounded(diagnostics + parsed.diagnostics),
          fidelity: .unavailable
        )
      )
    }
    return .success(
      PreparedDiagram(
        diagram: diagram,
        diagnostics: bounded(diagnostics + parsed.diagnostics)
      )
    )
  }

  private func available<Output>(
    _ output: Output,
    diagnostics: [MermaidDiagnostic]
  ) -> MermaidReport<Output>
  where Output: Equatable & Sendable {
    let diagnostics = bounded(diagnostics)
    return MermaidReport(
      output: output,
      diagnostics: diagnostics,
      fidelity: diagnostics.isEmpty ? .complete : .partial
    )
  }

  private func unavailable<Output>(
    code: MermaidDiagnosticCode,
    message: String
  ) -> MermaidReport<Output>
  where Output: Equatable & Sendable {
    MermaidReport(
      output: nil,
      diagnostics: bounded([MermaidDiagnostic(code: code, message: message)]),
      fidelity: .unavailable
    )
  }

  private func unavailable<Input, Output>(
    from report: MermaidReport<Input>
  ) -> MermaidReport<Output>
  where Input: Equatable & Sendable, Output: Equatable & Sendable {
    MermaidReport(
      output: nil,
      diagnostics: report.diagnostics,
      fidelity: .unavailable
    )
  }

  private func bounded(_ diagnostics: [MermaidDiagnostic]) -> [MermaidDiagnostic] {
    let limit = configuration.safetyLimits.validatedMaximumDiagnostics
    let messageLimit =
      configuration.safetyLimits.validatedMaximumDiagnosticMessageBytes
    var result = diagnostics.prefix(limit).map { diagnostic in
      MermaidDiagnostic(
        code: diagnostic.code,
        message: truncate(diagnostic.message, toUTF8Bytes: messageLimit),
        line: diagnostic.line,
        sourceExcerpt: diagnostic.sourceExcerpt.map {
          truncate($0, toUTF8Bytes: messageLimit)
        }
      )
    }
    if diagnostics.count > limit {
      let sentinel = MermaidDiagnostic(
        code: .diagnosticsTruncated,
        message: "Additional diagnostics were omitted by the configured limit."
      )
      if result.count == limit {
        result[result.count - 1] = sentinel
      } else {
        result.append(sentinel)
      }
    }
    return result
  }
}

private enum Preparation {
  case success(PreparedDiagram)
  case failure(MermaidReport<MermaidSurface>)
}

private struct PreparedDiagram {
  var diagram: ParsedMermaidDiagram
  var diagnostics: [MermaidDiagnostic]
}

private func normalizeNewlines(_ source: String) -> String {
  var output = ""
  var previousWasCarriageReturn = false
  for scalar in source.unicodeScalars {
    if scalar.value == 0x0A, previousWasCarriageReturn {
      previousWasCarriageReturn = false
      continue
    }
    if scalar.value == 0x0D {
      output.append("\n")
      previousWasCarriageReturn = true
    } else {
      output += String(scalar)
      previousWasCarriageReturn = false
    }
  }
  return output
}

private func replacingTabs(in source: String) -> String {
  var output = ""
  for character in source {
    output += character == "\t" ? "    " : String(character)
  }
  return output
}

private func truncate(_ value: String, toUTF8Bytes limit: Int) -> String {
  guard value.utf8.count > limit else { return value }
  var output = ""
  for character in value {
    let next = output + String(character)
    if next.utf8.count + 3 > limit { break }
    output = next
  }
  return output + "..."
}
