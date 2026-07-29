// Parser behavior adapted from grok-mermaid parse.ts/labels.ts at commit 6be6507;
// substantially modified for typed recovery, bounded allocation, scoped tokenization,
// and the independently implemented XY subset.

struct MermaidParserLimits {
  var maximumStatements = 4_096
  var maximumStatementBytes = 65_536
  var maximumConnectorCandidates = 16_384
  var maximumNodes = 512
  var maximumEdges = 1_024
  var maximumDetailsPerNode = 512
  var maximumAnnotations = 512
  var maximumChartValues = 16_384
  var maximumDiagnostics: Int
  var maximumDiagnosticBytes: Int
}

struct MermaidDiagramParser {
  let limits: MermaidParserLimits

  func parse(_ source: String) -> MermaidReport<ParsedMermaidDiagram> {
    let statements: [SourceStatement]
    switch splitStatements(source) {
    case .success(let value):
      statements = value
    case .failure(let diagnostic):
      return unavailable(diagnostic)
    }

    guard let header = statements.first else {
      return unavailable(
        .malformedDiagram,
        "A Mermaid diagram must start with a diagram header."
      )
    }
    if let lexicalError = header.lexicalError {
      return unavailable(
        .malformedDiagram,
        "Malformed Mermaid header. \(lexicalError)",
        line: header.line,
        excerpt: header.text
      )
    }

    let words = splitWords(header.text)
    guard let headerWord = words.first else {
      return unavailable(.malformedDiagram, "The Mermaid diagram header is empty.")
    }

    let headerKey = asciiLower(headerWord)
    guard validHeader(words, family: headerKey) else {
      return unavailable(
        .malformedDiagram,
        "Malformed or unsupported \(headerWord) diagram header.",
        line: header.line,
        excerpt: header.text
      )
    }

    let parsed: FamilyParseResult
    switch headerKey {
    case "graph", "flowchart":
      parsed = parseFlowchart(statements)
    case "statediagram", "statediagram-v2":
      parsed = parseState(statements)
    case "sequencediagram":
      parsed = parseSequence(statements)
    case "classdiagram":
      parsed = parseClass(statements)
    case "erdiagram":
      parsed = parseER(statements)
    case "xychart", "xychart-beta":
      parsed = parseXY(statements)
    default:
      return unavailable(
        .unsupportedDiagram,
        "Unsupported Mermaid diagram family '\(headerWord)'.",
        line: header.line,
        excerpt: header.text
      )
    }

    guard case .success(var diagram) = parsed else {
      if case .failure(let diagnostic) = parsed {
        return unavailable(diagnostic)
      }
      preconditionFailure("unreachable family parse result")
    }

    guard !diagram.nodes.isEmpty || diagram.chart?.series.isEmpty == false else {
      return unavailable(
        .malformedDiagram,
        "The \(headerWord) diagram does not contain any renderable content.",
        line: header.line,
        excerpt: header.text
      )
    }

    diagram.diagnostics = coalesceContentElision(diagram.diagnostics)
    let fidelity: MermaidFidelity = diagram.diagnostics.isEmpty ? .complete : .partial
    return MermaidReport(
      output: diagram,
      diagnostics: diagram.diagnostics,
      fidelity: fidelity
    )
  }

  private func parseFlowchart(_ statements: [SourceStatement]) -> FamilyParseResult {
    let headerWords = splitWords(statements[0].text)
    var diagram = ParsedMermaidDiagram(
      kind: .flowchart,
      direction: headerWords.count > 1 ? asciiUpper(headerWords[1]) : "TD"
    )
    var groupDepth = 0

    for statement in statements.dropFirst() {
      let text = trim(statement.text)
      if let lexicalError = statement.lexicalError {
        appendWarning(
          .contentElided,
          "The flowchart statement was omitted. \(lexicalError)",
          statement,
          to: &diagram
        )
        continue
      }
      let first = asciiLower(splitWords(text).first ?? "")
      switch first {
      case "subgraph":
        groupDepth += 1
        let label = trim(String(text.dropFirst((splitWords(text).first ?? "").count)))
        guard !label.isEmpty else {
          return malformed(statement, family: "flowchart", reason: "A subgraph needs a label.")
        }
        guard appendAnnotation("subgraph \(label)", to: &diagram) else {
          return resourceFailure("Diagram exceeds the private annotation safety limit.")
        }
        continue
      case "end":
        if groupDepth == 0 {
          appendWarning(
            .contentElided,
            "An unmatched subgraph end marker was omitted.",
            statement,
            to: &diagram
          )
        } else {
          groupDepth -= 1
        }
        continue
      case "direction":
        let words = splitWords(text)
        guard words.count == 2, isDirection(words[1]) else {
          return malformed(
            statement,
            family: "flowchart",
            reason: "A direction statement requires TD, TB, BT, LR, or RL."
          )
        }
        diagram.direction = asciiUpper(words[1])
        continue
      case "classdef", "class", "style", "linkstyle":
        appendWarning(
          .unsupportedConstruct,
          "Visual Mermaid styling is intentionally ignored by the terminal renderer.",
          statement,
          to: &diagram
        )
        continue
      case "click":
        appendWarning(
          .unsupportedConstruct,
          "Mermaid click directives are not executed.",
          statement,
          to: &diagram
        )
        continue
      default:
        break
      }

      if let edge = parseEdgeStatement(text, syntax: .flowchart) {
        guard insert(edge.from, in: &diagram), insert(edge.to, in: &diagram) else {
          return resourceFailure("Diagram exceeds the private node safety limit.")
        }
        guard appendEdge(edge, to: &diagram) else {
          return resourceFailure("Diagram exceeds the private relation safety limit.")
        }
        if edge.remainder != nil {
          appendWarning(
            .contentElided,
            "Only the first relation in a chained flowchart statement was rendered.",
            statement,
            to: &diagram
          )
        }
      } else if let node = parseNodeToken(text) {
        guard insert(node, in: &diagram) else {
          return resourceFailure("Diagram exceeds the private node safety limit.")
        }
      } else {
        appendWarning(
          .contentElided,
          "The flowchart statement could not be represented.",
          statement,
          to: &diagram
        )
      }
    }

    if groupDepth > 0 {
      appendDiagnostic(
        MermaidDiagnostic(
          code: .contentElided,
          message: "An unterminated subgraph was flattened into the containing diagram."
        ),
        to: &diagram
      )
    }
    return .success(diagram)
  }

  private func parseState(_ statements: [SourceStatement]) -> FamilyParseResult {
    var diagram = ParsedMermaidDiagram(kind: .state, direction: "TD")
    var compositeDepth = 0

    for index in statements.indices.dropFirst() {
      let statement = statements[index]
      if statement.lexicalError != nil {
        guard recoverStrict(statement, at: index, in: statements, diagram: &diagram) else {
          return malformedStrict(statement, family: "state")
        }
        continue
      }
      let text = trim(statement.text)
      let lower = asciiLower(text)
      let words = splitWords(text)
      let first = asciiLower(words.first ?? "")
      if first == "direction" {
        guard words.count == 2, isDirection(words[1]) else {
          return malformed(
            statement,
            family: "state",
            reason: "A direction statement requires TD, TB, BT, LR, or RL."
          )
        }
        diagram.direction = asciiUpper(words[1])
        continue
      }
      if text == "}" {
        guard compositeDepth > 0 else {
          return malformed(
            statement,
            family: "state",
            reason: "A composite state has an unmatched closing brace."
          )
        }
        compositeDepth -= 1
        continue
      }
      if ["note", "classdef", "class", "style", "fork", "join"].contains(first)
        || text == "--"
      {
        appendWarning(
          .unsupportedConstruct,
          "This recognized state construct is not represented by the terminal renderer.",
          statement,
          to: &diagram
        )
        continue
      }
      if lower.hasPrefix("state ") {
        let declaration = trim(String(text.dropFirst("state".count)))
        if declaration.hasSuffix("{") {
          let id = trim(String(declaration.dropLast()))
          guard splitWords(id).count == 1 else {
            return malformed(
              statement,
              family: "state",
              reason: "A composite state declaration requires one identifier."
            )
          }
          guard insert(.init(id: id, label: id), in: &diagram) else {
            return resourceFailure("Diagram exceeds the private node safety limit.")
          }
          compositeDepth += 1
          appendWarning(
            .unsupportedConstruct,
            "Composite state contents are flattened in the terminal renderer.",
            statement,
            to: &diagram
          )
          continue
        }
        if let choiceRange = rangeOfASCIICaseInsensitive("<<choice>>", in: declaration) {
          let id = trim(
            String(declaration[..<choiceRange.lowerBound])
              + String(declaration[choiceRange.upperBound...])
          )
          guard isSingleIdentifier(id) else {
            return malformed(
              statement,
              family: "state",
              reason: "A choice declaration requires exactly one identifier."
            )
          }
          guard
            diagram.upsertNode(
              id: id,
              kind: .choice,
              maximumNodes: limits.maximumNodes
            )
          else {
            return resourceFailure("Diagram exceeds the private node safety limit.")
          }
          continue
        }
        if let range = rangeOfASCIICaseInsensitive(" as ", in: declaration) {
          let left = trim(String(declaration[..<range.lowerBound]))
          let right = trim(String(declaration[range.upperBound...]))
          guard
            !left.isEmpty,
            !right.isEmpty,
            isQuoted(left)
              ? isSingleIdentifier(right)
              : isSingleIdentifier(left)
                && (isQuoted(right) || isSingleIdentifier(right))
          else {
            return malformed(
              statement,
              family: "state",
              reason: "A state alias needs one identifier and one quoted or single-word label."
            )
          }
          let node =
            left.first == "\""
            ? ParsedNodeToken(id: right, label: unquote(left))
            : ParsedNodeToken(id: left, label: unquote(right))
          guard insert(node, in: &diagram) else {
            return resourceFailure("Diagram exceeds the private node safety limit.")
          }
          continue
        }
        if splitWords(declaration).count == 1 {
          guard insert(.init(id: declaration, label: declaration), in: &diagram) else {
            return resourceFailure("Diagram exceeds the private node safety limit.")
          }
          continue
        }
      }
      if let edge = parseEdgeStatement(text, syntax: .state) {
        let from = stateNode(edge.from, isSource: true)
        let to = stateNode(edge.to, isSource: false)
        guard
          diagram.upsertNode(
            id: from.id,
            label: from.label,
            kind: from.kind,
            maximumNodes: limits.maximumNodes
          ),
          diagram.upsertNode(
            id: to.id,
            label: to.label,
            kind: to.kind,
            maximumNodes: limits.maximumNodes
          )
        else {
          return resourceFailure("Diagram exceeds the private node safety limit.")
        }
        guard appendEdge(edge, fromID: from.id, toID: to.id, to: &diagram) else {
          return resourceFailure("Diagram exceeds the private relation safety limit.")
        }
        continue
      }
      if let colon = firstTopLevelCharacter(":", in: text) {
        let id = trim(String(text[..<colon]))
        let detail = trim(String(text[text.index(after: colon)...]))
        guard isSingleIdentifier(id), !detail.isEmpty else {
          return malformed(
            statement,
            family: "state",
            reason: "A state description needs one identifier and nonempty text."
          )
        }
        guard
          diagram.upsertNode(id: id, maximumNodes: limits.maximumNodes),
          diagram.appendDetail(
            detail,
            toNode: id,
            maximumDetails: limits.maximumDetailsPerNode
          )
        else {
          return resourceFailure("Diagram exceeds the private node or detail safety limit.")
        }
        continue
      }
      if let choiceRange = rangeOfASCIICaseInsensitive("<<choice>>", in: text) {
        let id = trim(
          String(text[..<choiceRange.lowerBound]) + String(text[choiceRange.upperBound...])
        )
        guard isSingleIdentifier(id) else {
          return malformed(
            statement,
            family: "state",
            reason: "A choice declaration requires exactly one identifier."
          )
        }
        guard
          diagram.upsertNode(
            id: id,
            kind: .choice,
            maximumNodes: limits.maximumNodes
          )
        else {
          return resourceFailure("Diagram exceeds the private node safety limit.")
        }
        continue
      }
      guard recoverStrict(statement, at: index, in: statements, diagram: &diagram) else {
        return malformedStrict(statement, family: "state")
      }
    }
    guard compositeDepth == 0 else {
      return .failure(
        MermaidDiagnostic(
          code: .malformedDiagram,
          message: "A composite state body is missing its closing brace."
        )
      )
    }
    return .success(diagram)
  }

  private func parseSequence(_ statements: [SourceStatement]) -> FamilyParseResult {
    var diagram = ParsedMermaidDiagram(kind: .sequence, direction: "LR")
    var sectionStack: [String] = []

    for index in statements.indices.dropFirst() {
      let statement = statements[index]
      if statement.lexicalError != nil {
        guard recoverStrict(statement, at: index, in: statements, diagram: &diagram) else {
          return malformedStrict(statement, family: "sequence")
        }
        continue
      }
      let text = trim(statement.text)
      let words = splitWords(text)
      let first = asciiLower(words.first ?? "")
      if first == "participant" || first == "actor" {
        let declaration = trim(String(text.dropFirst((words.first ?? "").count)))
        let node: ParsedNodeToken
        if let range = rangeOfASCIICaseInsensitive(" as ", in: declaration) {
          let id = trim(String(declaration[..<range.lowerBound]))
          let label = trim(String(declaration[range.upperBound...]))
          guard isSingleIdentifier(id), !label.isEmpty else {
            return malformed(
              statement,
              family: "sequence",
              reason: "A participant alias needs one identifier and a nonempty label."
            )
          }
          node = ParsedNodeToken(
            id: id,
            label: unquote(label)
          )
        } else {
          guard isSingleIdentifier(declaration) else {
            return malformed(
              statement,
              family: "sequence",
              reason: "A participant declaration needs exactly one identifier."
            )
          }
          node = ParsedNodeToken(id: declaration, label: declaration)
        }
        guard insert(node, kind: .participant, in: &diagram) else {
          return resourceFailure("Diagram exceeds the private participant safety limit.")
        }
        continue
      }
      if ["loop", "alt", "opt", "par", "critical", "break"].contains(first) {
        guard sectionStack.count < limits.maximumAnnotations else {
          return resourceFailure("Diagram exceeds the private section nesting safety limit.")
        }
        sectionStack.append(first)
        let label = trim(String(text.dropFirst((words.first ?? "").count)))
        guard appendAnnotation("\(first): \(label)", to: &diagram) else {
          return resourceFailure("Diagram exceeds the private annotation safety limit.")
        }
        continue
      }
      if first == "else" || first == "and" {
        guard appendAnnotation(text, to: &diagram) else {
          return resourceFailure("Diagram exceeds the private annotation safety limit.")
        }
        continue
      }
      if first == "end" {
        guard !sectionStack.isEmpty else {
          return malformed(
            statement,
            family: "sequence",
            reason: "A sequence section has an unmatched closing 'end'."
          )
        }
        sectionStack.removeLast()
        continue
      }
      if first == "autonumber" || first == "note" {
        guard appendAnnotation(text, to: &diagram) else {
          return resourceFailure("Diagram exceeds the private annotation safety limit.")
        }
        continue
      }
      if ["activate", "deactivate", "rect", "box", "create", "destroy", "link", "links"]
        .contains(first)
      {
        appendWarning(
          .unsupportedConstruct,
          "This recognized sequence construct is not represented by the terminal renderer.",
          statement,
          to: &diagram
        )
        continue
      }
      if let edge = parseEdgeStatement(text, syntax: .sequence) {
        guard
          insert(edge.from, kind: .participant, in: &diagram),
          insert(edge.to, kind: .participant, in: &diagram)
        else {
          return resourceFailure("Diagram exceeds the private participant safety limit.")
        }
        guard appendEdge(edge, to: &diagram) else {
          return resourceFailure("Diagram exceeds the private message safety limit.")
        }
        continue
      }
      guard recoverStrict(statement, at: index, in: statements, diagram: &diagram) else {
        return malformedStrict(statement, family: "sequence")
      }
    }
    guard sectionStack.isEmpty else {
      return .failure(
        MermaidDiagnostic(
          code: .malformedDiagram,
          message: "A sequence section is missing its closing 'end'."
        )
      )
    }
    return .success(diagram)
  }

  private func parseClass(_ statements: [SourceStatement]) -> FamilyParseResult {
    var diagram = ParsedMermaidDiagram(kind: .class, direction: "LR")
    var activeClass: String?

    for index in statements.indices.dropFirst() {
      let statement = statements[index]
      if statement.lexicalError != nil {
        guard recoverStrict(statement, at: index, in: statements, diagram: &diagram) else {
          return malformedStrict(statement, family: "class")
        }
        continue
      }
      let text = trim(statement.text)
      let lower = asciiLower(text)
      let words = splitWords(text)
      let first = asciiLower(words.first ?? "")
      if text == "}" {
        guard activeClass != nil else {
          return malformed(
            statement,
            family: "class",
            reason: "A class body has an unmatched closing brace."
          )
        }
        activeClass = nil
        continue
      }
      if first == "direction" {
        guard words.count == 2, isDirection(words[1]) else {
          return malformed(
            statement,
            family: "class",
            reason: "A direction statement requires TD, TB, BT, LR, or RL."
          )
        }
        diagram.direction = asciiUpper(words[1])
        continue
      }
      if ["style", "classdef", "cssclass", "click", "namespace"].contains(first) {
        appendWarning(
          .unsupportedConstruct,
          "This recognized class-diagram construct is not represented by the terminal renderer.",
          statement,
          to: &diagram
        )
        continue
      }
      if lower.hasPrefix("class ") {
        guard activeClass == nil else {
          return malformed(
            statement,
            family: "class",
            reason: "Nested class bodies are outside the supported syntax profile."
          )
        }
        var declaration = trim(String(text.dropFirst("class".count)))
        let opens = declaration.hasSuffix("{")
        if opens { declaration = trim(String(declaration.dropLast())) }
        guard splitWords(declaration).count == 1 else {
          guard recoverStrict(statement, at: index, in: statements, diagram: &diagram) else {
            return malformedStrict(statement, family: "class")
          }
          continue
        }
        let id = declaration
        guard
          diagram.upsertNode(
            id: id,
            kind: .entity,
            maximumNodes: limits.maximumNodes
          )
        else {
          return resourceFailure("Diagram exceeds the private class safety limit.")
        }
        if opens { activeClass = id }
        continue
      }
      if let activeClass {
        guard
          diagram.appendDetail(
            text,
            toNode: activeClass,
            maximumDetails: limits.maximumDetailsPerNode
          )
        else {
          return resourceFailure("Diagram exceeds the private class-member safety limit.")
        }
        continue
      }
      if let edge = parseEdgeStatement(text, syntax: .classDiagram) {
        guard
          insert(edge.from, kind: .entity, in: &diagram),
          insert(edge.to, kind: .entity, in: &diagram)
        else {
          return resourceFailure("Diagram exceeds the private class safety limit.")
        }
        guard appendEdge(edge, to: &diagram) else {
          return resourceFailure("Diagram exceeds the private relation safety limit.")
        }
        continue
      }
      if let colon = firstTopLevelCharacter(":", in: text) {
        let id = trim(String(text[..<colon]))
        let member = trim(String(text[text.index(after: colon)...]))
        guard isSingleIdentifier(id), !member.isEmpty else {
          return malformed(
            statement,
            family: "class",
            reason: "A colon member needs one class identifier and nonempty member text."
          )
        }
        guard
          diagram.upsertNode(
            id: id,
            kind: .entity,
            maximumNodes: limits.maximumNodes
          ),
          diagram.appendDetail(
            member,
            toNode: id,
            maximumDetails: limits.maximumDetailsPerNode
          )
        else {
          return resourceFailure("Diagram exceeds the private class-member safety limit.")
        }
        continue
      }
      if text.hasPrefix("<<"), let close = firstRange(of: ">>", in: text) {
        let annotation = String(text[..<close.upperBound])
        let id = trim(String(text[close.upperBound...]))
        guard isSingleIdentifier(id) else {
          return malformed(
            statement,
            family: "class",
            reason: "A class annotation needs exactly one class identifier."
          )
        }
        guard
          diagram.upsertNode(
            id: id,
            kind: .entity,
            maximumNodes: limits.maximumNodes
          ),
          diagram.appendDetail(
            annotation,
            toNode: id,
            maximumDetails: limits.maximumDetailsPerNode
          )
        else {
          return resourceFailure("Diagram exceeds the private class-member safety limit.")
        }
        continue
      }
      guard recoverStrict(statement, at: index, in: statements, diagram: &diagram) else {
        return malformedStrict(statement, family: "class")
      }
    }
    guard activeClass == nil else {
      return .failure(
        MermaidDiagnostic(
          code: .malformedDiagram,
          message: "A class body is missing its closing brace."
        )
      )
    }
    return .success(diagram)
  }

  private func parseER(_ statements: [SourceStatement]) -> FamilyParseResult {
    var diagram = ParsedMermaidDiagram(kind: .er, direction: "LR")
    var activeEntity: String?

    for index in statements.indices.dropFirst() {
      let statement = statements[index]
      if statement.lexicalError != nil {
        guard recoverStrict(statement, at: index, in: statements, diagram: &diagram) else {
          return malformedStrict(statement, family: "ER")
        }
        continue
      }
      let text = trim(statement.text)
      if text == "}" {
        guard activeEntity != nil else {
          return malformed(
            statement,
            family: "ER",
            reason: "An entity body has an unmatched closing brace."
          )
        }
        activeEntity = nil
        continue
      }
      if text.hasSuffix("{") {
        let id = trim(String(text.dropLast()))
        guard activeEntity == nil, isSingleIdentifier(id) else {
          return malformed(
            statement,
            family: "ER",
            reason: "Nested entity bodies and multi-word entity identifiers are unsupported."
          )
        }
        guard
          diagram.upsertNode(
            id: id,
            kind: .entity,
            maximumNodes: limits.maximumNodes
          )
        else {
          return resourceFailure("Diagram exceeds the private entity safety limit.")
        }
        activeEntity = id
        continue
      }
      if let activeEntity {
        guard
          diagram.appendDetail(
            text,
            toNode: activeEntity,
            maximumDetails: limits.maximumDetailsPerNode
          )
        else {
          return resourceFailure("Diagram exceeds the private attribute safety limit.")
        }
        continue
      }
      if let edge = parseEdgeStatement(text, syntax: .er) {
        guard
          insert(edge.from, kind: .entity, in: &diagram),
          insert(edge.to, kind: .entity, in: &diagram)
        else {
          return resourceFailure("Diagram exceeds the private entity safety limit.")
        }
        guard appendEdge(edge, to: &diagram) else {
          return resourceFailure("Diagram exceeds the private relation safety limit.")
        }
        continue
      }
      guard recoverStrict(statement, at: index, in: statements, diagram: &diagram) else {
        return malformedStrict(statement, family: "ER")
      }
    }
    guard activeEntity == nil else {
      return .failure(
        MermaidDiagnostic(
          code: .malformedDiagram,
          message: "An ER entity body is missing its closing brace."
        )
      )
    }
    return .success(diagram)
  }

  private func parseXY(_ statements: [SourceStatement]) -> FamilyParseResult {
    var chart = MermaidChart()
    var seriesOrigins: [SourceStatement] = []
    var valueCount = 0
    var diagram = ParsedMermaidDiagram(kind: .xy, direction: "LR")

    for statement in statements.dropFirst() {
      if let lexicalError = statement.lexicalError {
        return malformed(
          statement,
          family: "XY",
          reason: lexicalError
        )
      }
      let text = trim(statement.text)
      let words = splitWords(text)
      let first = asciiLower(words.first ?? "")
      switch first {
      case "title":
        let title = trim(String(text.dropFirst("title".count)))
        guard isQuoted(title) else {
          return malformed(
            statement,
            family: "XY",
            reason: "A chart title must be enclosed in double quotes."
          )
        }
        diagram.title = unquote(title)
      case "x-axis":
        let rest = trim(String(text.dropFirst("x-axis".count)))
        switch parseBracketList(rest, maximumItems: limits.maximumChartValues) {
        case .values(let values):
          chart.xLabels = values.map(unquote)
        case .limitExceeded:
          return resourceFailure("XY labels exceed the private chart-value safety limit.")
        case .malformed:
          appendWarning(
            .contentElided,
            "The XY x-axis labels were not understood.",
            statement,
            to: &diagram
          )
        }
      case "y-axis":
        let rest = trim(String(text.dropFirst("y-axis".count)))
        if let bounds = parseFiniteAxisRange(rest) {
          chart.yMinimum = bounds.minimum
          chart.yMaximum = bounds.maximum
        } else {
          appendWarning(
            .contentElided,
            "The XY y-axis requires two finite, ordered bounds.",
            statement,
            to: &diagram
          )
        }
      case "bar", "line":
        let rest = trim(String(text.dropFirst((words.first ?? "").count)))
        switch parseBracketList(
          rest,
          maximumItems: limits.maximumChartValues - min(valueCount, limits.maximumChartValues)
        ) {
        case .values(let authoredValues):
          let values = authoredValues.compactMap(Double.init)
          guard
            !values.isEmpty,
            values.count == authoredValues.count,
            values.allSatisfy(\.isFinite)
          else {
            appendWarning(
              .contentElided,
              "The XY series values were not understood.",
              statement,
              to: &diagram
            )
            continue
          }
          valueCount += values.count
          chart.series.append(
            MermaidChartSeries(
              name: "\(first) \(chart.series.count + 1)",
              values: values,
              isLine: first == "line"
            )
          )
          seriesOrigins.append(statement)
        case .limitExceeded:
          return resourceFailure("XY values exceed the private chart-value safety limit.")
        case .malformed:
          appendWarning(
            .contentElided,
            "The XY series values were not understood.",
            statement,
            to: &diagram
          )
        }
      default:
        appendWarning(
          .contentElided,
          "The XY statement could not be represented.",
          statement,
          to: &diagram
        )
      }
    }

    if !chart.series.isEmpty {
      let expectedCount = chart.xLabels.isEmpty ? chart.series[0].values.count : chart.xLabels.count
      var retainedSeries: [MermaidChartSeries] = []
      for (index, series) in chart.series.enumerated() {
        if series.values.count == expectedCount {
          retainedSeries.append(series)
        } else {
          appendWarning(
            .contentElided,
            "An XY series has \(series.values.count) values but the chart shape requires "
              + "\(expectedCount); that series was omitted.",
            seriesOrigins[index],
            to: &diagram
          )
        }
      }
      if retainedSeries.isEmpty {
        let origin = seriesOrigins.first
        return .failure(
          MermaidDiagnostic(
            code: .malformedDiagram,
            message: "No XY series matches the chart's authored observation shape.",
            line: origin?.line,
            sourceExcerpt: origin.map { truncated($0.text) }
          )
        )
      }
      chart.series = retainedSeries
    }

    diagram.chart = chart
    if !chart.series.isEmpty {
      guard
        diagram.upsertNode(
          id: "chart",
          label: diagram.title ?? "XY chart",
          kind: .entity,
          maximumNodes: limits.maximumNodes
        )
      else {
        return resourceFailure("Diagram exceeds the private node safety limit.")
      }
    }
    return .success(diagram)
  }

  private func insert(
    _ token: ParsedNodeToken,
    kind: MermaidNodeKind = .normal,
    in diagram: inout ParsedMermaidDiagram
  ) -> Bool {
    diagram.upsertNode(
      id: token.id,
      label: token.label,
      kind: kind,
      shape: token.shape,
      maximumNodes: limits.maximumNodes
    )
  }

  private func appendEdge(
    _ token: ParsedEdgeToken,
    fromID: String? = nil,
    toID: String? = nil,
    to diagram: inout ParsedMermaidDiagram
  ) -> Bool {
    diagram.appendEdge(
      MermaidEdge(
        from: fromID ?? token.from.id,
        to: toID ?? token.to.id,
        label: token.label,
        connector: token.connector,
        line: token.line,
        startEndpoint: token.startEndpoint,
        endEndpoint: token.endEndpoint
      ),
      maximumEdges: limits.maximumEdges
    )
  }

  private func appendAnnotation(
    _ annotation: String,
    to diagram: inout ParsedMermaidDiagram
  ) -> Bool {
    guard diagram.annotations.count < limits.maximumAnnotations else { return false }
    diagram.annotations.append(annotation)
    return true
  }

  private func recoverStrict(
    _ statement: SourceStatement,
    at index: Int,
    in statements: [SourceStatement],
    diagram: inout ParsedMermaidDiagram
  ) -> Bool {
    guard index == statements.indices.last else { return false }
    appendWarning(
      .contentElided,
      "The unreadable final statement was omitted.",
      statement,
      to: &diagram
    )
    return true
  }

  private func malformedStrict(
    _ statement: SourceStatement,
    family: String
  ) -> FamilyParseResult {
    .failure(
      MermaidDiagnostic(
        code: .malformedDiagram,
        message:
          "An unreadable \(family) statement appears before the end of the diagram; "
          + "only one unreadable final line may be salvaged.",
        line: statement.line,
        sourceExcerpt: truncated(statement.text)
      )
    )
  }

  private func malformed(
    _ statement: SourceStatement,
    family: String,
    reason: String
  ) -> FamilyParseResult {
    .failure(
      MermaidDiagnostic(
        code: .malformedDiagram,
        message: "Malformed \(family) statement. \(reason)",
        line: statement.line,
        sourceExcerpt: truncated(statement.text)
      )
    )
  }

  private func resourceFailure(_ message: String) -> FamilyParseResult {
    .failure(MermaidDiagnostic(code: .resourceLimit, message: message))
  }

  private func stateNode(_ token: ParsedNodeToken, isSource: Bool) -> (
    id: String, label: String, kind: MermaidNodeKind
  ) {
    if token.id == "[*]" {
      return isSource ? ("__start", "start", .start) : ("__end", "end", .end)
    }
    return (token.id, token.label, .normal)
  }

  private func parseEdgeStatement(
    _ text: String,
    syntax: MermaidEdgeSyntax
  ) -> ParsedEdgeToken? {
    let connectors = syntax.connectors

    guard let match = firstTopLevelConnector(in: text, connectors: connectors) else {
      return nil
    }
    let leftText = trim(String(text[..<match.range.lowerBound]))
    var rightText = trim(String(text[match.range.upperBound...]))
    guard let left = parseNodeToken(leftText) else { return nil }

    var label: String?
    if rightText.first == "|", let close = closingPipe(in: rightText) {
      label = unescapeQuoted(
        String(rightText[rightText.index(after: rightText.startIndex)..<close])
      )
      rightText = trim(String(rightText[rightText.index(after: close)...]))
    }

    var trailingLabel: String?
    if let colon = firstTopLevelCharacter(":", in: rightText) {
      trailingLabel = trim(String(rightText[rightText.index(after: colon)...]))
      rightText = trim(String(rightText[..<colon]))
    }

    var remainder: String?
    if let next = firstTopLevelConnector(in: rightText, connectors: connectors) {
      remainder = String(rightText[next.range.lowerBound...])
      rightText = trim(String(rightText[..<next.range.lowerBound]))
    }
    guard let right = parseNodeToken(rightText) else { return nil }

    let connector = match.connector
    let dotted = connector.contains(".")
    let thick = connector.contains("=")
    let endpoints = syntax.endpoints(for: connector)
    return ParsedEdgeToken(
      from: left,
      to: right,
      label: label ?? trailingLabel,
      connector: connector,
      line: thick ? .thick : (dotted ? .dotted : .solid),
      startEndpoint: endpoints.start,
      endEndpoint: endpoints.end,
      remainder: remainder
    )
  }

  private func parseNodeToken(_ raw: String) -> ParsedNodeToken? {
    let text = trim(raw)
    guard !text.isEmpty else { return nil }
    if text == "[*]" {
      return ParsedNodeToken(id: "[*]", label: "●")
    }

    var idEnd = text.endIndex
    for marker: Character in ["[", "(", "{", ">"] {
      if let index = text.firstIndex(of: marker), index < idEnd {
        idEnd = index
      }
    }
    if let space = text.firstIndex(where: \.isWhitespace), space < idEnd {
      idEnd = space
    }
    let id = trim(String(text[..<idEnd]))
    guard
      !id.isEmpty,
      !id.contains("]"),
      !id.contains(")"),
      !id.contains("}")
    else {
      return nil
    }

    let suffix = trim(String(text[idEnd...]))
    guard !suffix.isEmpty else {
      return ParsedNodeToken(id: id, label: id, shape: nil)
    }
    let pairs: [(String, String, MermaidNodeShape)] = [
      ("[[", "]]", .subroutine),
      ("((", "))", .circle),
      ("[(", ")]", .cylinder),
      ("([", "])", .stadium),
      ("{{", "}}", .hexagon),
      ("[", "]", .rectangle),
      ("(", ")", .rounded),
      ("{", "}", .diamond),
      (">", "]", .asymmetric),
    ]
    for (open, close, shape) in pairs where suffix.hasPrefix(open) {
      guard suffix.hasSuffix(close), suffix.count >= open.count + close.count else {
        return nil
      }
      let bodyStart = suffix.index(suffix.startIndex, offsetBy: open.count)
      let bodyEnd = suffix.index(suffix.endIndex, offsetBy: -close.count)
      let body = String(suffix[bodyStart..<bodyEnd])
      guard balancedNodeLabelBody(body) else { return nil }
      return ParsedNodeToken(
        id: id,
        label: cleanLabel(body),
        shape: shape
      )
    }
    return nil
  }

  private func splitStatements(_ source: String) -> StatementSplitResult {
    var result: [SourceStatement] = []
    result.reserveCapacity(min(64, limits.maximumStatements))
    var lineNumber = 1
    var current = ""
    var quoted = false
    var escaped = false
    var brackets: [Character] = []
    var inComment = false
    var currentUTF8Bytes = 0
    var connectorCandidates = 0
    var index = source.startIndex

    while index < source.endIndex {
      let character = source[index]
      let nextIndex = source.index(after: index)
      let next = nextIndex < source.endIndex ? source[nextIndex] : nil

      if character == "\n" {
        let lexicalError =
          quoted
          ? "A quoted string or escape sequence is unterminated at the end of the line."
          : nil
        guard
          appendStatement(
            current,
            line: lineNumber,
            lexicalError: lexicalError,
            to: &result
          )
        else {
          return statementLimitFailure()
        }
        current.removeAll(keepingCapacity: true)
        currentUTF8Bytes = 0
        quoted = false
        escaped = false
        brackets.removeAll(keepingCapacity: true)
        inComment = false
        lineNumber += 1
        index = nextIndex
        continue
      }
      if inComment {
        index = nextIndex
        continue
      }
      if quoted {
        guard
          appendSourceCharacter(
            character,
            to: &current,
            utf8Bytes: &currentUTF8Bytes
          )
        else {
          return statementByteLimitFailure()
        }
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == "\"" {
          quoted = false
        }
        index = nextIndex
        continue
      }

      if character == "\"" {
        quoted = true
        guard
          appendSourceCharacter(
            character,
            to: &current,
            utf8Bytes: &currentUTF8Bytes
          )
        else {
          return statementByteLimitFailure()
        }
      } else if character == "%", next == "%", brackets.isEmpty {
        inComment = true
      } else if character == ";", brackets.isEmpty {
        guard
          appendStatement(
            current,
            line: lineNumber,
            lexicalError: nil,
            to: &result
          )
        else {
          return statementLimitFailure()
        }
        current.removeAll(keepingCapacity: true)
        currentUTF8Bytes = 0
      } else {
        if brackets.isEmpty, isConnectorLeadingCharacter(character) {
          connectorCandidates += 1
          guard connectorCandidates <= limits.maximumConnectorCandidates else {
            return connectorWorkLimitFailure()
          }
        }
        updateBracketStack(
          character,
          stack: &brackets,
          opensAsymmetricShape: character == ">" && canOpenAsymmetricShape(after: current)
        )
        guard
          appendSourceCharacter(
            character,
            to: &current,
            utf8Bytes: &currentUTF8Bytes
          )
        else {
          return statementByteLimitFailure()
        }
      }
      index = nextIndex
    }

    let lexicalError =
      quoted
      ? "A quoted string or escape sequence is unterminated at the end of input."
      : nil
    guard
      appendStatement(
        current,
        line: lineNumber,
        lexicalError: lexicalError,
        to: &result
      )
    else {
      return statementLimitFailure()
    }
    return .success(result)
  }

  private func statementLimitFailure() -> StatementSplitResult {
    .failure(
      MermaidDiagnostic(
        code: .resourceLimit,
        message:
          "Diagram exceeds the private \(limits.maximumStatements)-statement safety limit."
      )
    )
  }

  private func statementByteLimitFailure() -> StatementSplitResult {
    .failure(
      MermaidDiagnostic(
        code: .resourceLimit,
        message:
          "A Mermaid statement exceeds the private "
          + "\(limits.maximumStatementBytes)-byte safety limit."
      )
    )
  }

  private func connectorWorkLimitFailure() -> StatementSplitResult {
    .failure(
      MermaidDiagnostic(
        code: .resourceLimit,
        message:
          "Diagram connector recognition exceeds the private "
          + "\(limits.maximumConnectorCandidates)-candidate work limit."
      )
    )
  }

  private func appendSourceCharacter(
    _ character: Character,
    to statement: inout String,
    utf8Bytes: inout Int
  ) -> Bool {
    let characterBytes = String(character).utf8.count
    let (nextBytes, overflow) = utf8Bytes.addingReportingOverflow(characterBytes)
    guard !overflow, nextBytes <= limits.maximumStatementBytes else { return false }
    statement.append(character)
    utf8Bytes = nextBytes
    return true
  }

  private func appendStatement(
    _ value: String,
    line: Int,
    lexicalError: String?,
    to statements: inout [SourceStatement]
  ) -> Bool {
    let value = trim(value)
    guard !value.isEmpty else { return true }
    guard statements.count < limits.maximumStatements else { return false }
    statements.append(
      SourceStatement(text: value, line: line, lexicalError: lexicalError)
    )
    return true
  }

  private func appendWarning(
    _ code: MermaidDiagnosticCode,
    _ message: String,
    _ statement: SourceStatement,
    to diagram: inout ParsedMermaidDiagram
  ) {
    appendDiagnostic(
      MermaidDiagnostic(
        code: code,
        message: message,
        line: statement.line,
        sourceExcerpt: truncated(statement.text)
      ),
      to: &diagram
    )
  }

  private func appendDiagnostic(
    _ diagnostic: MermaidDiagnostic,
    to diagram: inout ParsedMermaidDiagram
  ) {
    let maximum = max(1, limits.maximumDiagnostics)
    if diagram.diagnostics.count < maximum {
      diagram.diagnostics.append(diagnostic)
      return
    }
    guard diagram.diagnostics.last?.code != .diagnosticsTruncated else { return }
    diagram.diagnostics[maximum - 1] = MermaidDiagnostic(
      code: .diagnosticsTruncated,
      message: "Additional diagnostics were omitted by the configured limit."
    )
  }

  private func truncated(_ value: String) -> String {
    truncateUTF8(value, to: max(32, limits.maximumDiagnosticBytes))
  }

  private func unavailable(
    _ diagnostic: MermaidDiagnostic
  ) -> MermaidReport<ParsedMermaidDiagram> {
    MermaidReport(output: nil, diagnostics: [diagnostic], fidelity: .unavailable)
  }

  private func unavailable(
    _ code: MermaidDiagnosticCode,
    _ message: String,
    line: Int? = nil,
    excerpt: String? = nil
  ) -> MermaidReport<ParsedMermaidDiagram> {
    unavailable(
      MermaidDiagnostic(
        code: code,
        message: truncated(message),
        line: line,
        sourceExcerpt: excerpt.map(truncated)
      )
    )
  }

  private func coalesceContentElision(
    _ diagnostics: [MermaidDiagnostic]
  ) -> [MermaidDiagnostic] {
    var foundElision = false
    var result: [MermaidDiagnostic] = []
    result.reserveCapacity(diagnostics.count)
    for diagnostic in diagnostics {
      if diagnostic.code == .contentElided {
        if foundElision { continue }
        foundElision = true
        result.append(
          MermaidDiagnostic(
            code: .contentElided,
            message: "One or more authored statements could not be represented.",
            line: diagnostic.line,
            sourceExcerpt: diagnostic.sourceExcerpt
          )
        )
      } else {
        result.append(diagnostic)
      }
    }
    return result
  }
}

private enum FamilyParseResult {
  case success(ParsedMermaidDiagram)
  case failure(MermaidDiagnostic)
}

private enum StatementSplitResult {
  case success([SourceStatement])
  case failure(MermaidDiagnostic)
}

private enum BracketListResult {
  case values([String])
  case malformed
  case limitExceeded
}

private struct SourceStatement {
  var text: String
  var line: Int
  var lexicalError: String? = nil
}

private struct ParsedNodeToken {
  var id: String
  var label: String
  var shape: MermaidNodeShape? = nil
}

private struct ParsedEdgeToken {
  var from: ParsedNodeToken
  var to: ParsedNodeToken
  var label: String?
  var connector: String
  var line: MermaidEdgeLine
  var startEndpoint: MermaidEdgeEndpoint
  var endEndpoint: MermaidEdgeEndpoint
  var remainder: String?
}

private enum MermaidEdgeSyntax {
  case flowchart
  case state
  case sequence
  case classDiagram
  case er

  var connectors: [String] {
    switch self {
    case .flowchart:
      return [
        "<-.->", "<==>", "<-->", "o---o", "o---x", "x---o", "x---x",
        "o--o", "o--x", "x--o", "x--x", "---o", "---x", "o---", "x---",
        "-->>", "<<--", "-.->", "==>", "<==", "->>", "<<-", "-->", "<--",
        "--o", "--x", "--)", "o--", "x--", "-x", "-)", "->", "<-", "---",
        "-.-", "===",
      ]
    case .state:
      return ["-->>", "<<--", "-.->", "==>", "<==", "-->", "<--", "->", "<-", "---"]
    case .sequence:
      return [
        "-->>", "<<--", "-.->", "==>", "<==", "->>", "<<-", "-->", "<--",
        "--x", "--)", "-x", "-)", "->", "<-", "---", "-.-", "===",
      ]
    case .classDiagram:
      return [
        "<|..", "..|>", "<|--", "--|>", "*--", "--*", "o--", "--o",
        "<..", "..>", "-->", "<--", "--", "..",
      ]
    case .er:
      let leftMarkers = ["|o", "||", "}o", "}|"]
      let lines = ["--", ".."]
      let rightMarkers = ["o|", "||", "o{", "|{"]
      return leftMarkers.flatMap { left in
        lines.flatMap { line in
          rightMarkers.map { right in left + line + right }
        }
      }
    }
  }

  func endpoints(
    for connector: String
  ) -> (start: MermaidEdgeEndpoint, end: MermaidEdgeEndpoint) {
    switch self {
    case .er:
      let left = String(connector.prefix(2))
      let right = String(connector.suffix(2))
      return (erEndpoint(left), erEndpoint(right))
    case .classDiagram:
      return (
        classEndpoint(atStartOf: connector),
        classEndpoint(atEndOf: connector)
      )
    case .flowchart, .state, .sequence:
      return (
        flowEndpoint(atStartOf: connector),
        flowEndpoint(atEndOf: connector)
      )
    }
  }

  private func flowEndpoint(atStartOf connector: String) -> MermaidEdgeEndpoint {
    if connector.hasPrefix("<") { return .arrow }
    if connector.hasPrefix("o") { return .circle }
    if connector.hasPrefix("x") { return .cross }
    return .none
  }

  private func flowEndpoint(atEndOf connector: String) -> MermaidEdgeEndpoint {
    if connector.hasSuffix(">") { return .arrow }
    if connector.hasSuffix("o") || connector.hasSuffix(")") { return .circle }
    if connector.hasSuffix("x") { return .cross }
    return .none
  }

  private func classEndpoint(atStartOf connector: String) -> MermaidEdgeEndpoint {
    if connector.hasPrefix("<|") || connector.hasPrefix("<") { return .arrow }
    if connector.hasPrefix("*") { return .composition }
    if connector.hasPrefix("o") { return .aggregation }
    return .none
  }

  private func classEndpoint(atEndOf connector: String) -> MermaidEdgeEndpoint {
    if connector.hasSuffix("|>") || connector.hasSuffix(">") { return .arrow }
    if connector.hasSuffix("*") { return .composition }
    if connector.hasSuffix("o") { return .aggregation }
    return .none
  }

  private func erEndpoint(_ marker: String) -> MermaidEdgeEndpoint {
    switch marker {
    case "|o", "o|":
      return .zeroOrOne
    case "||":
      return .exactlyOne
    case "}o", "o{":
      return .zeroOrMore
    case "}|", "|{":
      return .oneOrMore
    default:
      preconditionFailure("unexpected ER endpoint marker")
    }
  }
}

private func trim(_ value: String) -> String {
  guard let first = value.firstIndex(where: { !$0.isWhitespace }) else { return "" }
  guard let last = value.lastIndex(where: { !$0.isWhitespace }) else { return "" }
  return String(value[first...last])
}

private func splitWords(_ value: String) -> [String] {
  value.split(whereSeparator: \.isWhitespace).map(String.init)
}

private func isQuoted(_ value: String) -> Bool {
  value.count >= 2 && value.first == "\"" && value.last == "\""
}

private func isSingleIdentifier(_ value: String) -> Bool {
  !value.isEmpty && splitWords(value).count == 1 && !isQuoted(value)
}

private func validHeader(_ words: [String], family: String) -> Bool {
  switch family {
  case "graph", "flowchart":
    return words.count == 1 || (words.count == 2 && isDirection(words[1]))
  case "statediagram", "statediagram-v2", "sequencediagram", "classdiagram",
    "erdiagram", "xychart", "xychart-beta":
    return words.count == 1
  default:
    return true
  }
}

private func isDirection(_ value: String) -> Bool {
  ["TD", "TB", "BT", "LR", "RL"].contains(asciiUpper(value))
}

private func asciiLower(_ value: String) -> String {
  String(
    value.unicodeScalars.map { scalar in
      if (65...90).contains(scalar.value) {
        return Character(Unicode.Scalar(scalar.value + 32)!)
      }
      return Character(scalar)
    }
  )
}

private func asciiUpper(_ value: String) -> String {
  String(
    value.unicodeScalars.map { scalar in
      if (97...122).contains(scalar.value) {
        return Character(Unicode.Scalar(scalar.value - 32)!)
      }
      return Character(scalar)
    }
  )
}

private func unquote(_ value: String) -> String {
  let value = trim(value)
  guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
  return unescapeQuoted(String(value.dropFirst().dropLast()))
}

private func unescapeQuoted(_ value: String) -> String {
  var result = ""
  var escaped = false
  for character in value {
    if escaped {
      if character == "\"" || character == "\\" {
        result.append(character)
      } else {
        result.append("\\")
        result.append(character)
      }
      escaped = false
    } else if character == "\\" {
      escaped = true
    } else {
      result.append(character)
    }
  }
  if escaped { result.append("\\") }
  return result
}

private func cleanLabel(_ value: String) -> String {
  let value = unquote(trim(value))
  let entities = [
    ("<br/>", " "), ("<br>", " "), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"),
    ("&quot;", "\""), ("&#39;", "'"),
  ]
  var result = ""
  result.reserveCapacity(value.count)
  var index = value.startIndex
  while index < value.endIndex {
    var matched = false
    for (entity, replacement) in entities where value[index...].hasPrefix(entity) {
      result += replacement
      index = value.index(index, offsetBy: entity.count)
      matched = true
      break
    }
    if !matched {
      result.append(value[index])
      index = value.index(after: index)
    }
  }
  return result
}

private func rangeOfASCIICaseInsensitive(
  _ needle: String,
  in haystack: String
) -> Range<String.Index>? {
  let lower = asciiLower(haystack)
  guard let range = firstRange(of: asciiLower(needle), in: lower) else { return nil }
  let lowerDistance = lower.distance(from: lower.startIndex, to: range.lowerBound)
  let upperDistance = lower.distance(from: lower.startIndex, to: range.upperBound)
  let start = haystack.index(haystack.startIndex, offsetBy: lowerDistance)
  let end = haystack.index(haystack.startIndex, offsetBy: upperDistance)
  return start..<end
}

private func parseFiniteAxisRange(_ value: String) -> (minimum: Double, maximum: Double)? {
  guard
    let connector = firstTopLevelConnector(in: value, connectors: ["-->"]),
    trim(String(value[..<connector.range.lowerBound])).split(whereSeparator: \.isWhitespace)
      .count == 1,
    trim(String(value[connector.range.upperBound...])).split(whereSeparator: \.isWhitespace)
      .count == 1,
    let minimum = Double(trim(String(value[..<connector.range.lowerBound]))),
    let maximum = Double(trim(String(value[connector.range.upperBound...]))),
    minimum.isFinite,
    maximum.isFinite,
    minimum < maximum
  else {
    return nil
  }
  return (minimum, maximum)
}

private func parseBracketList(_ value: String, maximumItems: Int) -> BracketListResult {
  let value = trim(value)
  guard maximumItems > 0, value.first == "[", value.last == "]" else {
    return maximumItems > 0 ? .malformed : .limitExceeded
  }
  let body = value.dropFirst().dropLast()
  if trim(String(body)).isEmpty {
    return .values([])
  }
  var result: [String] = []
  result.reserveCapacity(min(16, maximumItems))
  var current = ""
  var quoted = false
  var escaped = false
  var brackets: [Character] = []

  for character in body {
    if quoted {
      current.append(character)
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        quoted = false
      }
      continue
    }
    if character == "\"" {
      quoted = true
      current.append(character)
    } else if character == ",", brackets.isEmpty {
      guard result.count < maximumItems else { return .limitExceeded }
      result.append(trim(current))
      current = ""
    } else {
      updateBracketStack(character, stack: &brackets)
      current.append(character)
    }
  }
  guard !quoted, brackets.isEmpty else { return .malformed }
  guard result.count < maximumItems else { return .limitExceeded }
  result.append(trim(current))
  return .values(result)
}

private func firstTopLevelConnector(
  in text: String,
  connectors: [String]
) -> (connector: String, range: Range<String.Index>)? {
  var connectorsByLeadingCharacter: [Character: [String]]?
  var quoted = false
  var escaped = false
  var brackets: [Character] = []
  var index = text.startIndex

  while index < text.endIndex {
    let character = text[index]
    if quoted {
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        quoted = false
      }
      index = text.index(after: index)
      continue
    }
    if character == "\"" {
      quoted = true
      index = text.index(after: index)
      continue
    }
    if brackets.isEmpty, isConnectorLeadingCharacter(character) {
      if connectorsByLeadingCharacter == nil {
        var grouped: [Character: [String]] = [:]
        for connector in connectors.sorted(by: connectorPrecedes) {
          guard let first = connector.first else { continue }
          grouped[first, default: []].append(connector)
        }
        connectorsByLeadingCharacter = grouped
      }
      let candidates = connectorsByLeadingCharacter?[character] ?? []
      for connector in candidates
      where text[index...].hasPrefix(connector)
        && connectorHasValidLeadingContext(connector, at: index, in: text)
      {
        let end = text.index(index, offsetBy: connector.count)
        return (connector, index..<end)
      }
    }
    updateBracketStack(
      character,
      stack: &brackets,
      opensAsymmetricShape: asymmetricShapeOpens(at: index, in: text, stack: brackets)
    )
    index = text.index(after: index)
  }
  return nil
}

private func connectorPrecedes(_ left: String, _ right: String) -> Bool {
  if left.count == right.count { return left < right }
  return left.count > right.count
}

private func isConnectorLeadingCharacter(_ character: Character) -> Bool {
  switch character {
  case "-", ".", "=", "<", "o", "x", "*", "|", "}":
    true
  default:
    false
  }
}

private func connectorHasValidLeadingContext(
  _ connector: String,
  at index: String.Index,
  in text: String
) -> Bool {
  guard connector.first == "o" || connector.first == "x" else { return true }
  guard index > text.startIndex else { return false }
  let previous = text[text.index(before: index)]
  return previous.isWhitespace || ["]", ")", "}", "\""].contains(previous)
}

private func balancedNodeLabelBody(_ body: String) -> Bool {
  var quoted = false
  var escaped = false
  var brackets: [Character] = []

  for character in body {
    if quoted {
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        quoted = false
      }
      continue
    }
    if character == "\"" {
      quoted = true
      continue
    }
    if ["]", ")", "}"].contains(character), brackets.last != character {
      return false
    }
    updateBracketStack(character, stack: &brackets)
  }
  return !quoted && !escaped && brackets.isEmpty
}

private func firstTopLevelCharacter(
  _ target: Character,
  in text: String
) -> String.Index? {
  var quoted = false
  var escaped = false
  var brackets: [Character] = []
  var index = text.startIndex
  while index < text.endIndex {
    let character = text[index]
    if quoted {
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        quoted = false
      }
    } else if character == "\"" {
      quoted = true
    } else {
      if character == target, brackets.isEmpty { return index }
      updateBracketStack(
        character,
        stack: &brackets,
        opensAsymmetricShape: asymmetricShapeOpens(at: index, in: text, stack: brackets)
      )
    }
    index = text.index(after: index)
  }
  return nil
}

private func closingPipe(in value: String) -> String.Index? {
  guard value.first == "|" else { return nil }
  var escaped = false
  var index = value.index(after: value.startIndex)
  while index < value.endIndex {
    let character = value[index]
    if escaped {
      escaped = false
    } else if character == "\\" {
      escaped = true
    } else if character == "|" {
      return index
    }
    index = value.index(after: index)
  }
  return nil
}

private func updateBracketStack(
  _ character: Character,
  stack: inout [Character],
  opensAsymmetricShape: Bool = false
) {
  switch character {
  case "[":
    stack.append("]")
  case "(":
    stack.append(")")
  case "{":
    stack.append("}")
  case ">" where opensAsymmetricShape:
    stack.append("]")
  case "]", ")", "}":
    if stack.last == character { stack.removeLast() }
  default:
    break
  }
}

private func canOpenAsymmetricShape(after prefix: String) -> Bool {
  guard let last = prefix.last, !last.isWhitespace else { return false }
  switch last {
  case "-", "=", "<", ">", ".", "|", ")", "]", "}":
    return false
  default:
    return true
  }
}

private func asymmetricShapeOpens(
  at index: String.Index,
  in text: String,
  stack: [Character]
) -> Bool {
  guard stack.isEmpty, text[index] == ">", index > text.startIndex else { return false }
  let previous = text[text.index(before: index)]
  guard !previous.isWhitespace else { return false }
  switch previous {
  case "-", "=", "<", ">", ".", "|", ")", "]", "}":
    return false
  default:
    return true
  }
}

private func firstRange(of needle: String, in value: String) -> Range<String.Index>? {
  guard !needle.isEmpty else { return value.startIndex..<value.startIndex }
  var index = value.startIndex
  while index < value.endIndex {
    let suffix = value[index...]
    if suffix.starts(with: needle) {
      let end = value.index(index, offsetBy: needle.count)
      return index..<end
    }
    index = value.index(after: index)
  }
  return nil
}

private func truncateUTF8(_ value: String, to limit: Int) -> String {
  guard value.utf8.count > limit else { return value }
  var output = ""
  var byteCount = 0
  for character in value {
    let characterBytes = String(character).utf8.count
    if byteCount + characterBytes + 3 > limit { break }
    output.append(character)
    byteCount += characterBytes
  }
  return output + "..."
}
