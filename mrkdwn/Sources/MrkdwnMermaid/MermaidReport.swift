public enum MermaidFidelity: String, CaseIterable, Hashable, Sendable {
  case complete
  case partial
  case unavailable
}

public struct MermaidDiagnosticCode: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let malformedDiagram = Self(rawValue: "malformedDiagram")
  public static let unsupportedDiagram = Self(rawValue: "unsupportedDiagram")
  public static let unsupportedConstruct = Self(rawValue: "unsupportedConstruct")
  public static let contentElided = Self(rawValue: "contentElided")
  public static let resourceLimit = Self(rawValue: "resourceLimit")
  public static let layoutFailure = Self(rawValue: "layoutFailure")
  public static let widthClamped = Self(rawValue: "widthClamped")
  public static let diagnosticsTruncated = Self(rawValue: "diagnosticsTruncated")
  public static let controlCharacterUnsupported = Self(rawValue: "controlCharacterUnsupported")
  public static let controlCharacterEscaped = Self(rawValue: "controlCharacterEscaped")
  public static let bidiControlUnsupported = Self(rawValue: "bidiControlUnsupported")
  public static let rtlVisualOrderUnsupported = Self(rawValue: "rtlVisualOrderUnsupported")
}

public struct MermaidDiagnostic: Equatable, Hashable, Sendable {
  public let code: MermaidDiagnosticCode
  public let message: String
  public let line: Int?
  public let sourceExcerpt: String?

  public init(
    code: MermaidDiagnosticCode,
    message: String,
    line: Int? = nil,
    sourceExcerpt: String? = nil
  ) {
    self.code = code
    self.message = message
    self.line = line
    self.sourceExcerpt = sourceExcerpt
  }
}

public struct MermaidReport<Output: Equatable & Sendable>: Equatable, Sendable {
  public let output: Output?
  public let diagnostics: [MermaidDiagnostic]
  public let fidelity: MermaidFidelity

  init(
    output: Output?,
    diagnostics: [MermaidDiagnostic],
    fidelity: MermaidFidelity
  ) {
    precondition((output == nil) == (fidelity == .unavailable))
    precondition(fidelity != .partial || !diagnostics.isEmpty)
    self.output = output
    self.diagnostics = diagnostics
    self.fidelity = fidelity
  }
}
