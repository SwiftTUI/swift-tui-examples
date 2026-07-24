import SwiftTUIRuntime

/// Three release examples plus an interactive source-definition editor.
///
/// The cards intentionally share one 3×3 topology. That lets the point and
/// color variants exercise `MeshGradient`'s same-topology animation path
/// instead of snapping between unrelated values.
struct BordersAndShapesMeshGradientSection: View {
  @State private var pointMotion: Double = 0
  @State private var alternateColors: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("8. MeshGradient — static, animated, and editable")
        .foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 2) {
        meshCard("static", mesh: Self.staticMesh)
        meshCard("point animated", mesh: Self.pointAnimatedMesh(phase: pointMotion))
        meshCard("color animated", mesh: Self.colorAnimatedMesh(alternate: alternateColors))
      }
      MeshGradientCrafter()
    }
    .onAppear {
      withAnimation(
        .easeInOut(duration: .milliseconds(1800))
          .repeatForever(autoreverses: true)
      ) {
        pointMotion = 1
        alternateColors = true
      }
    }
  }

  private func meshCard(_ title: String, mesh: MeshGradient) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).foregroundStyle(.separator)
      Rectangle()
        .fill(mesh)
        .frame(width: 18, height: 6)
        .border(set: .rounded)
    }
  }

  static let identityPoints: [SIMD2<Float>] = [
    .init(0, 0), .init(0.5, 0), .init(1, 0),
    .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
    .init(0, 1), .init(0.5, 1), .init(1, 1),
  ]

  static let staticMesh = MeshGradient(
    width: 3,
    height: 3,
    points: identityPoints,
    colors: [
      .blue, .cyan, .green,
      .magenta, .white, .yellow,
      .red, .magenta, .blue,
    ],
    background: .black,
    colorSpace: .perceptual
  )

  static func pointAnimatedMesh(phase: Double) -> MeshGradient {
    var points = identityPoints
    points[1] = .init(0.5 + Float(phase) * 0.12, Float(phase) * 0.08)
    points[3] = .init(Float(phase) * 0.08, 0.5 - Float(phase) * 0.12)
    points[4] = .init(0.5 - Float(phase) * 0.18, 0.5 + Float(phase) * 0.14)
    points[5] = .init(1 - Float(phase) * 0.08, 0.5 + Float(phase) * 0.10)
    points[7] = .init(0.5 + Float(phase) * 0.10, 1 - Float(phase) * 0.08)
    return MeshGradient(
      width: 3,
      height: 3,
      points: points,
      colors: [
        .blue, .cyan, .green,
        .magenta, .white, .yellow,
        .red, .magenta, .blue,
      ],
      background: .black,
      colorSpace: .perceptual
    )
  }

  static func colorAnimatedMesh(alternate: Bool) -> MeshGradient {
    MeshGradient(
      width: 3,
      height: 3,
      points: identityPoints,
      colors: alternate
        ? [
          .red, .yellow, .magenta,
          .cyan, .blue, .white,
          .green, .cyan, .red,
        ]
        : [
          .blue, .cyan, .green,
          .magenta, .white, .yellow,
          .red, .magenta, .blue,
        ],
      background: .black,
      colorSpace: .perceptual
    )
  }
}

struct MeshGradientCrafter: View {
  @Environment(\.clipboardWriteAction) private var clipboardWriteAction
  @State private var points = BordersAndShapesMeshGradientSection.identityPoints
  @State private var controlColors = MeshGradientPalette.aurora.colors
  @State private var selectedPoint = 4
  @State private var smoothsColors = true
  @State private var usesPerceptualColor = true
  @State private var copyStatus = "Adjust a point, choose colors, then copy the Swift definition."

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Mesh crafter").foregroundStyle(.foreground)
      HStack(alignment: .top, spacing: 2) {
        Rectangle()
          .fill(mesh)
          .frame(width: 30, height: 9)
          .border(set: .rounded)
        VStack(alignment: .leading, spacing: 0) {
          Picker("Point", selection: $selectedPoint) {
            ForEach(0..<Self.pointNames.count, id: \.self) { index in
              Text(Self.pointNames[index]).tag(index)
            }
          }
          .pickerStyle(.menu)
          Slider("x", value: selectedX, in: -0.25...1.25, step: 0.05)
          Slider("y", value: selectedY, in: -0.25...1.25, step: 0.05)
          Text(
            "\(Self.pointNames[selectedPoint])  "
              + "(\(Self.coordinate(points[selectedPoint].x)), "
              + "\(Self.coordinate(points[selectedPoint].y)))"
          )
          .foregroundStyle(.separator)
        }
      }

      HStack(spacing: 1) {
        Text("Preset").foregroundStyle(.separator)
        ForEach(MeshGradientPalette.allCases, id: \.self) { palette in
          Button(palette.title) {
            controlColors = palette.colors
          }
        }
      }
      .focusSection()

      HStack(spacing: 1) {
        Text("Selected color").foregroundStyle(.separator)
        ForEach(MeshGradientControlColor.allCases, id: \.self) { controlColor in
          Button(controlColor.shortTitle) {
            controlColors[selectedPoint] = controlColor
          }
        }
      }
      .focusSection()

      HStack(spacing: 2) {
        Toggle("Smooth colors", isOn: $smoothsColors)
        Button(usesPerceptualColor ? "Color: perceptual" : "Color: device") {
          usesPerceptualColor.toggle()
        }
        Button("Reset points") {
          points = BordersAndShapesMeshGradientSection.identityPoints
        }
        Button("Copy Definition") {
          let copied = clipboardWriteAction(definition)
          copyStatus = copied ? "Copied MeshGradient definition." : "Clipboard unavailable."
        }
        .buttonStyle(.borderedProminent)
      }
      .focusSection()

      Text(copyStatus).foregroundStyle(.separator)
    }
    .padding(1)
    .border(.separator)
  }

  static let pointNames = [
    "top leading", "top", "top trailing",
    "leading", "center", "trailing",
    "bottom leading", "bottom", "bottom trailing",
  ]

  var definition: String {
    Self.definition(
      points: points,
      controlColors: controlColors,
      smoothsColors: smoothsColors,
      colorSpace: usesPerceptualColor ? .perceptual : .device
    )
  }

  static func definition(
    points: [SIMD2<Float>],
    controlColors: [MeshGradientControlColor],
    smoothsColors: Bool,
    colorSpace: Gradient.ColorSpace
  ) -> String {
    precondition(points.count == 9)
    precondition(controlColors.count == 9)

    let pointLines = points.map {
      "    .init(\(coordinate($0.x)), \(coordinate($0.y))),"
    }
    let colorLines = controlColors.map {
      "    \($0.swiftExpression),"
    }
    let colorSpaceExpression = colorSpace == .perceptual ? ".perceptual" : ".device"

    return """
      MeshGradient(
        width: 3,
        height: 3,
        points: [
      \(pointLines.joined(separator: "\n"))
        ],
        colors: [
      \(colorLines.joined(separator: "\n"))
        ],
        background: .black,
        smoothsColors: \(smoothsColors),
        colorSpace: \(colorSpaceExpression)
      )
      """
  }

  private var mesh: MeshGradient {
    MeshGradient(
      width: 3,
      height: 3,
      points: points,
      colors: controlColors.map(\.color),
      background: .black,
      smoothsColors: smoothsColors,
      colorSpace: usesPerceptualColor ? .perceptual : .device
    )
  }

  private var selectedX: Binding<Double> {
    Binding(
      get: { Double(points[selectedPoint].x) },
      set: { points[selectedPoint].x = Float($0) }
    )
  }

  private var selectedY: Binding<Double> {
    Binding(
      get: { Double(points[selectedPoint].y) },
      set: { points[selectedPoint].y = Float($0) }
    )
  }

  static func coordinate(_ value: Float) -> String {
    let hundredths = Int((Double(value) * 100).rounded())
    let sign = hundredths < 0 ? "-" : ""
    let magnitude = abs(hundredths)
    let fractional = String(magnitude % 100)
    let paddedFractional = fractional.count == 1 ? "0\(fractional)" : fractional
    return "\(sign)\(magnitude / 100).\(paddedFractional)"
  }
}

enum MeshGradientControlColor: String, CaseIterable, Hashable, Sendable {
  case red
  case yellow
  case green
  case cyan
  case blue
  case magenta
  case white

  var shortTitle: String {
    switch self {
    case .red: return "R"
    case .yellow: return "Y"
    case .green: return "G"
    case .cyan: return "C"
    case .blue: return "B"
    case .magenta: return "M"
    case .white: return "W"
    }
  }

  var color: Color {
    switch self {
    case .red: return .red
    case .yellow: return .yellow
    case .green: return .green
    case .cyan: return .cyan
    case .blue: return .blue
    case .magenta: return .magenta
    case .white: return .white
    }
  }

  var swiftExpression: String {
    ".\(rawValue)"
  }
}

enum MeshGradientPalette: String, CaseIterable, Hashable, Sendable {
  case aurora
  case sunset
  case ocean
  case prism

  var title: String {
    switch self {
    case .aurora:
      "Aurora"
    case .sunset:
      "Sunset"
    case .ocean:
      "Ocean"
    case .prism:
      "Prism"
    }
  }

  var colors: [MeshGradientControlColor] {
    switch self {
    case .aurora:
      return [
        .blue, .cyan, .green,
        .magenta, .white, .yellow,
        .red, .magenta, .blue,
      ]
    case .sunset:
      return [
        .magenta, .red, .yellow,
        .blue, .magenta, .red,
        .blue, .cyan, .yellow,
      ]
    case .ocean:
      return [
        .blue, .cyan, .blue,
        .cyan, .white, .green,
        .blue, .green, .cyan,
      ]
    case .prism:
      return [
        .red, .yellow, .green,
        .magenta, .white, .cyan,
        .blue, .magenta, .red,
      ]
    }
  }
}
