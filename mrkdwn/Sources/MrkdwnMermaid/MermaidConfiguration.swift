public enum MermaidGlyphMode: String, CaseIterable, Hashable, Sendable {
  case unicode
  case ascii
}

public enum MermaidAmbiguousWidth: String, CaseIterable, Hashable, Sendable {
  case narrow
  case wide
}

public struct MermaidSafetyLimits: Equatable, Hashable, Sendable {
  public var maximumInputBytes: Int
  public var maximumOutputCells: Int
  public var maximumDiagnostics: Int
  public var maximumDiagnosticMessageBytes: Int

  public init(
    maximumInputBytes: Int = 262_144,
    maximumOutputCells: Int = 262_144,
    maximumDiagnostics: Int = 32,
    maximumDiagnosticMessageBytes: Int = 512
  ) {
    self.maximumInputBytes = max(1, maximumInputBytes)
    self.maximumOutputCells = max(1, maximumOutputCells)
    self.maximumDiagnostics = max(1, maximumDiagnostics)
    self.maximumDiagnosticMessageBytes = max(32, maximumDiagnosticMessageBytes)
  }
}

extension MermaidSafetyLimits {
  var validatedMaximumInputBytes: Int {
    max(1, maximumInputBytes)
  }

  var validatedMaximumOutputCells: Int {
    max(1, maximumOutputCells)
  }

  var validatedMaximumDiagnostics: Int {
    max(1, maximumDiagnostics)
  }

  var validatedMaximumDiagnosticMessageBytes: Int {
    max(32, maximumDiagnosticMessageBytes)
  }
}

public struct MermaidConfiguration: Equatable, Hashable, Sendable {
  public var glyphMode: MermaidGlyphMode
  public var ambiguousWidth: MermaidAmbiguousWidth
  public var safetyLimits: MermaidSafetyLimits

  public init(
    glyphMode: MermaidGlyphMode = .unicode,
    ambiguousWidth: MermaidAmbiguousWidth = .narrow,
    safetyLimits: MermaidSafetyLimits = .init()
  ) {
    self.glyphMode = glyphMode
    self.ambiguousWidth = ambiguousWidth
    self.safetyLimits = safetyLimits
  }
}
