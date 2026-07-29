// Concepts adapted from grok-mermaid graph.ts/types.ts at commit 6be6507;
// substantially modified for MrkdwnMermaid's value interface and six-family model.

enum MermaidDiagramKind: String, CaseIterable, Equatable {
  case flowchart
  case state
  case sequence
  case `class`
  case er
  case xy
}

enum MermaidNodeKind: Equatable {
  case normal
  case start
  case end
  case choice
  case participant
  case entity
}

enum MermaidNodeShape: Equatable {
  case rectangle
  case rounded
  case stadium
  case subroutine
  case cylinder
  case circle
  case diamond
  case hexagon
  case asymmetric
}

struct MermaidNode: Equatable {
  var id: String
  var label: String
  var details: [String] = []
  var kind: MermaidNodeKind = .normal
  var shape: MermaidNodeShape = .rectangle
}

enum MermaidEdgeLine: Equatable {
  case solid
  case dotted
  case thick
}

enum MermaidEdgeEndpoint: Equatable {
  case none
  case arrow
  case circle
  case cross
  case aggregation
  case composition
  case zeroOrOne
  case exactlyOne
  case zeroOrMore
  case oneOrMore
}

struct MermaidEdge: Equatable {
  var from: String
  var to: String
  var label: String?
  var connector: String
  var line: MermaidEdgeLine = .solid
  var startEndpoint: MermaidEdgeEndpoint = .none
  var endEndpoint: MermaidEdgeEndpoint = .arrow
}

struct MermaidChartSeries: Equatable {
  var name: String
  var values: [Double]
  var isLine: Bool
}

struct MermaidChart: Equatable {
  var xLabels: [String] = []
  var yMinimum: Double?
  var yMaximum: Double?
  var series: [MermaidChartSeries] = []
}

struct ParsedMermaidDiagram: Equatable {
  var kind: MermaidDiagramKind
  var title: String?
  var direction: String?
  var nodes: [MermaidNode] = []
  var edges: [MermaidEdge] = []
  var annotations: [String] = []
  var chart: MermaidChart?
  var diagnostics: [MermaidDiagnostic] = []
  private var nodeIndices: [String: Int] = [:]

  init(
    kind: MermaidDiagramKind,
    title: String? = nil,
    direction: String? = nil
  ) {
    self.kind = kind
    self.title = title
    self.direction = direction
  }

  @discardableResult
  mutating func upsertNode(
    id: String,
    label: String? = nil,
    kind: MermaidNodeKind = .normal,
    shape: MermaidNodeShape? = nil,
    maximumNodes: Int
  ) -> Bool {
    guard !id.isEmpty else { return true }
    if let index = nodeIndices[id] {
      if let label, !label.isEmpty, label != id || nodes[index].label == id {
        nodes[index].label = label
      }
      if kind != .normal {
        nodes[index].kind = kind
      }
      if let shape {
        nodes[index].shape = shape
      }
    } else {
      guard nodes.count < maximumNodes else { return false }
      nodeIndices[id] = nodes.count
      nodes.append(
        MermaidNode(
          id: id,
          label: label ?? id,
          kind: kind,
          shape: shape ?? .rectangle
        )
      )
    }
    return true
  }

  @discardableResult
  mutating func appendDetail(
    _ detail: String,
    toNode id: String,
    maximumDetails: Int
  ) -> Bool {
    guard let index = nodeIndices[id] else { return false }
    guard nodes[index].details.count < maximumDetails else { return false }
    nodes[index].details.append(detail)
    return true
  }

  @discardableResult
  mutating func appendEdge(_ edge: MermaidEdge, maximumEdges: Int) -> Bool {
    guard edges.count < maximumEdges else { return false }
    edges.append(edge)
    return true
  }

  func node(forID id: String) -> MermaidNode? {
    guard let index = nodeIndices[id] else { return nil }
    return nodes[index]
  }
}
