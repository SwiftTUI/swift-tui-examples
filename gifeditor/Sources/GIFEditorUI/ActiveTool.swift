import GIFEditorCore

/// The two shape tools, and the `ToolOps` call each one stands for.
///
/// A shape is an anchor-then-commit interaction, exactly like the
/// gradient: fix one corner (press `Space`, or put the pointer down),
/// move, then commit (press `Space` again, or release). Both corners are
/// order-independent, so a drag in any direction paints the same cells.
public enum ShapeTool: String, Hashable, Sendable, CaseIterable, Codable {
  case rectangle
  case ellipse

  public var label: String {
    switch self {
    case .rectangle: "Rectangle"
    case .ellipse: "Ellipse"
    }
  }

  /// 1-letter glyph mirroring the key that selects the tool, matching
  /// ``EditorTool/glyph``.
  public var glyph: String {
    switch self {
    case .rectangle: "R"
    case .ellipse: "C"
    }
  }

  /// Single-cell unicode icon for the tool dock, taken from the same
  /// Geometric Shapes block the other tool icons come from so the dock's
  /// 4-cell column keeps its alignment.
  public var iconGlyph: String {
    switch self {
    case .rectangle: "□"  // U+25A1 white square
    case .ellipse: "○"  // U+25CB white circle
    }
  }

  /// Lays this shape between two corner points.
  ///
  /// The single place the two `ToolOps` shape entry points are chosen
  /// between, so the keyboard path and the drag controller cannot
  /// disagree about which arguments a shape is given.
  func applied(
    to buffer: PixelBuffer,
    from a: PixelPoint,
    to b: PixelPoint,
    color: PaletteIndex?,
    filled: Bool,
    thickness: Int,
    selection: Selection?
  ) -> PixelBuffer {
    switch self {
    case .rectangle:
      ToolOps.rectangle(
        on: buffer, from: a, to: b, color: color,
        filled: filled, thickness: thickness, selection: selection
      )
    case .ellipse:
      ToolOps.ellipse(
        on: buffer, from: a, to: b, color: color,
        filled: filled, thickness: thickness, selection: selection
      )
    }
  }
}

/// Every tool the dock offers: `GIFEditorCore`'s ``EditorTool`` set, plus
/// the shape tools.
///
/// `EditorTool` is the *core's* vocabulary — the tools whose ops the core
/// itself names. `ToolOps.rectangle` and `ToolOps.ellipse` are just as
/// core, but nothing inside `GIFEditorCore` dispatches on a tool at all:
/// the editor does, from its drag state machine and its keyboard path. So
/// the dock's vocabulary lives in the layer that owns the dock, and
/// wrapping rather than widening keeps the core enum exactly as wide as
/// the code that has to switch over it.
public enum ActiveTool: Hashable, Sendable, CaseIterable {
  case core(EditorTool)
  case shape(ShapeTool)

  /// Dock order: the core tools in their own declaration order, then the
  /// shapes. Derived from the two `allCases` rather than listed, so a tool
  /// added to either enum reaches the dock without an edit here.
  public static let allCases: [ActiveTool] =
    EditorTool.allCases.map(Self.core) + ShapeTool.allCases.map(Self.shape)

  // Spellings that let a call site name a core tool as though it were a
  // case here — `selectTool(.pen)` rather than `selectTool(.core(.pen))`.
  // Pattern matching is unaffected: a `switch` still has to spell
  // `case .core(.pen)`, so these cannot be mistaken for exhaustive
  // coverage of anything.
  public static let pen = Self.core(.pen)
  public static let eraser = Self.core(.eraser)
  public static let fill = Self.core(.fill)
  public static let gradient = Self.core(.gradient)
  public static let marquee = Self.core(.marquee)
  public static let select = Self.core(.select)
  public static let eyedropper = Self.core(.eyedropper)
  public static let rectangle = Self.shape(.rectangle)
  public static let ellipse = Self.shape(.ellipse)

  public var label: String {
    switch self {
    case .core(let tool): tool.label
    case .shape(let shape): shape.label
    }
  }

  public var glyph: String {
    switch self {
    case .core(let tool): tool.glyph
    case .shape(let shape): shape.glyph
    }
  }

  public var iconGlyph: String {
    switch self {
    case .core(let tool): tool.iconGlyph
    case .shape(let shape): shape.iconGlyph
    }
  }

  /// The shape this tool draws, or `nil` for a core tool. Lets a caller
  /// ask the one question a shape tool answers differently without
  /// re-deriving it from a `switch`.
  public var shapeTool: ShapeTool? {
    guard case .shape(let shape) = self else { return nil }
    return shape
  }
}
