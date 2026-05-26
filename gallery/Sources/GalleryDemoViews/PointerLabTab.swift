import Foundation
import SwiftTUIRuntime

struct PointerLabTab: View {
  @State private var tapLocation = "none"
  @State private var dragSummary = "none"
  @State private var longPressCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      Divider()
      Text("Pointer target")
        .frame(width: 44, height: 6, alignment: .center)
        .border(set: .rounded)
        .contentShape(
          CellRect(
            origin: .init(x: 0, y: 0),
            size: .init(width: 44, height: 6)
          )
        )
        .coordinateSpace(name: "pointer-lab-target")
        .gesture(
          SpatialTapGesture(coordinateSpace: .named("pointer-lab-target"))
            .onEnded { value in
              tapLocation = Self.pointSummary(value.location)
            }
        )
        .gesture(
          DragGesture(minimumDistance: 0, coordinateSpace: .named("pointer-lab-target"))
            .onChanged { value in
              dragSummary =
                "\(Self.pointSummary(value.location)) / delta \(Self.vectorSummary(value.translation))"
            }
        )
        .onLongPressGesture(minimumDuration: .milliseconds(600)) {
          longPressCount += 1
        }

      GroupBox("Pointer state") {
        VStack(alignment: .leading, spacing: 0) {
          LabeledContent("Spatial tap", value: tapLocation)
          LabeledContent("Drag", value: dragSummary)
          LabeledContent("Long presses", value: "\(longPressCount)")
        }
      }
      Text("The target uses an explicit contentShape and a named coordinate space.")
        .foregroundStyle(.separator)
      Spacer(minLength: 0)
    }
    .padding(2)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Pointer Lab").foregroundStyle(.foreground)
      Text("SpatialTapGesture, DragGesture, long press, contentShape, and named coordinate spaces.")
        .foregroundStyle(.separator)
    }
  }

  private static func pointSummary(_ point: Point) -> String {
    String(format: "%.1f, %.1f", point.x, point.y)
  }

  private static func vectorSummary(_ vector: Vector) -> String {
    String(format: "%.1f, %.1f", vector.dx, vector.dy)
  }
}
