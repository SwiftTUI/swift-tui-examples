#if canImport(AppKit)
import AppKit
import Foundation
import Testing

import SwiftUI
import SwiftUILayouts

/// Phase-0 de-risk spike (see docs/plans/2026-06-21-001-...).
///
/// Question this answers: can we attribute PER-ELEMENT layout geometry on the
/// SwiftUI side WITHOUT editing the 56 concrete view structs? Pure
/// `AnchorPreference`/`onGeometryChange` composition can only observe the root
/// (un-instrumented descendants publish no anchors), so the only
/// composition-free per-element route is the AppKit accessibility tree exposed
/// by `NSHostingView`. This spike tests that route on 5 deliberately-hard
/// entries and, regardless of its outcome, exercises the two low-risk Tier-1
/// signals: the `ImageRenderer` PNG and a pixel-bbox content-extent fallback.
///
/// Outputs (written OUTSIDE the submodule tree, never committed):
///   /tmp/layout-probe/geometry/<id>.json   — a11y elements + pixel bbox
///   /tmp/layout-probe/png/<id>.swiftui.png — the SwiftUI render
@MainActor
@Suite struct MeasuringOverlaySpike {
  /// 5 entries spanning the hard cases: repeated/positioned Text, sizing,
  /// shape-only (no Text marker), overlay regions, and gap arithmetic.
  static let spikeIDs = [
    "stacks.hstack-alignment-triad",
    "frames.min-ideal-max-frame-clamp",
    "shapes.circle-in-non-square-frame",
    "borders.nested-border-ordering",
    "spacers.three-sharing",
  ]

  // Canvas: 10 pt per SwiftTUI cell (LayoutScale.cell). 60x30 cells.
  static let cols = 60
  static let rows = 30
  static let scale: CGFloat = 2
  static let outDir = "/tmp/layout-probe"

  @Test("Spike: PNG + pixel bbox + accessibility geometry (5 hard entries; all 56 with LAYOUT_EXPORT_ALL)")
  func captureSpikeEntries() throws {
    let env = ProcessInfo.processInfo.environment
    // Opt-in only: this drives ImageRenderer / NSWindow and writes artifacts, so
    // it must be a no-op in the normal example gates (which may run on a
    // window-server-less CI runner). `run.sh` sets LAYOUT_EXPORT_ALL.
    guard env["LAYOUT_EXPORT_ALL"] != nil || env["LAYOUT_SPIKE"] != nil else { return }

    let fm = FileManager.default
    try? fm.createDirectory(atPath: "\(Self.outDir)/png", withIntermediateDirectories: true)
    try? fm.createDirectory(atPath: "\(Self.outDir)/geometry", withIntermediateDirectories: true)

    let exportAll = env["LAYOUT_EXPORT_ALL"] != nil
    let ids = exportAll ? SwiftUILayouts.LayoutCatalog.all.map(\.id) : Self.spikeIDs
    let a11yIDs = Set(Self.spikeIDs)  // the a11y experiment runs only on the 5 hard cases

    var summary: [String] = []

    for id in ids {
      guard let entry = SwiftUILayouts.LayoutCatalog.entry(id: id) else {
        Issue.record("missing spike entry \(id)")
        continue
      }

      let pointSize = CGSize(width: CGFloat(Self.cols) * 10, height: CGFloat(Self.rows) * 10)

      // --- (1) ImageRenderer PNG (Tier-1, low risk) -----------------------
      let framed = entry.makeView()
        .frame(width: pointSize.width, height: pointSize.height, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

      let renderer = ImageRenderer(content: framed)
      renderer.scale = Self.scale
      renderer.isOpaque = true

      guard let cg = renderer.cgImage else {
        Issue.record("\(id): ImageRenderer produced no cgImage")
        continue
      }

      try writePNG(cg, to: "\(Self.outDir)/png/\(id).swiftui.png")

      // --- (2) pixel-bbox content extent (Tier-1 fallback geometry) -------
      let bbox = contentBBox(cg, backgroundIsBlack: true)
      // Convert pixel bbox back to cells (scale -> points -> /10).
      let bboxCells = bbox.map { CellRectJSON(from: $0, scale: Self.scale) }

      // --- (3) accessibility-tree per-element walk (the real experiment) --
      let a11y = a11yIDs.contains(id) ? accessibilityElements(of: framed, size: pointSize) : []

      // --- write geometry JSON --------------------------------------------
      let json = GeometryProbeJSON(
        id: id,
        marker: entry.marker,
        canvasCells: .init(width: Self.cols, height: Self.rows),
        pixelSize: .init(width: Int(pointSize.width * Self.scale), height: Int(pointSize.height * Self.scale)),
        contentBBoxCells: bboxCells,
        accessibilityElementCount: a11y.count,
        accessibilityElements: a11y
      )
      try writeJSON(json, to: "\(Self.outDir)/geometry/\(id).json")

      // Markers found among a11y labels/values (the per-element pairing test).
      let labels = a11y.compactMap { $0.label ?? $0.value }
      let markerHit = labels.contains { $0.contains(entry.marker) }
      summary.append(
        "\(id): a11y=\(a11y.count) elem, markerLabelHit=\(markerHit), bboxCells=\(bboxCells.map(\.description) ?? "nil")"
      )

      // The PNG must always succeed (Tier-1 floor).
      #expect(cg.width > 0 && cg.height > 0)
    }

    // Print the go/no-go summary into the test log.
    print("=== MEASURING-OVERLAY SPIKE SUMMARY ===")
    summary.forEach { print($0) }
    print("=== outputs under \(Self.outDir) ===")
  }

  // MARK: - accessibility walk

  private func accessibilityElements(of view: some View, size: CGSize) -> [A11yElementJSON] {
    let app = NSApplication.shared  // ensure AppKit is initialized in the test process
    app.setActivationPolicy(.accessory)
    let host = NSHostingView(rootView: AnyView(view))
    host.frame = CGRect(origin: .zero, size: size)

    // A real (but off-screen) key window makes SwiftUI lazily build its
    // accessibility tree; a borderless/un-keyed window does not.
    let window = NSWindow(
      contentRect: host.frame,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))  // off every screen
    window.makeKeyAndOrderFront(nil)
    host.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    // Spin the main run loop briefly so the a11y tree materializes.
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))

    var out: [A11yElementJSON] = []
    let root = NSAccessibility.unignoredDescendant(of: host) ?? host
    walk(root, depth: 0, into: &out)
    window.orderOut(nil)
    return out
  }

  private func walk(_ element: Any, depth: Int, into out: inout [A11yElementJSON]) {
    guard depth < 24, let obj = element as? any NSAccessibilityProtocol else { return }

    let role = obj.accessibilityRole()?.rawValue
    let label = obj.accessibilityLabel()
    let value = obj.accessibilityValue() as? String
    let frame = obj.accessibilityFrame()

    // Record any element that carries a role/label/value (cuts pure container noise).
    if role != nil || label != nil || value != nil {
      out.append(
        A11yElementJSON(
          depth: depth,
          role: role,
          label: label,
          value: value,
          frameScreen: RectJSON(from: frame)
        )
      )
    }

    let rawChildren = obj.accessibilityChildren() ?? []
    for child in NSAccessibility.unignoredChildren(from: rawChildren) {
      walk(child, depth: depth + 1, into: &out)
    }
  }

  // MARK: - pixel bbox

  /// Bounding box (in pixels) of content that differs from the background.
  private func contentBBox(_ cg: CGImage, backgroundIsBlack: Bool) -> CGRect? {
    let w = cg.width, h = cg.height
    let bytesPerRow = w * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * h)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

    var minX = w, minY = h, maxX = -1, maxY = -1
    let threshold: Int = 18  // tolerance over pure black
    for y in 0..<h {
      let row = y * bytesPerRow
      for x in 0..<w {
        let i = row + x * 4
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        let isContent = backgroundIsBlack ? (r + g + b > threshold) : true
        if isContent {
          if x < minX { minX = x }
          if x > maxX { maxX = x }
          if y < minY { minY = y }
          if y > maxY { maxY = y }
        }
      }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  }

  // MARK: - IO

  private func writePNG(_ cg: CGImage, to path: String) throws {
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else {
      throw SpikeError.pngEncodeFailed
    }
    try data.write(to: URL(fileURLWithPath: path))
  }

  private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try enc.encode(value)
    try data.write(to: URL(fileURLWithPath: path))
  }
}

private enum SpikeError: Error { case pngEncodeFailed }

// MARK: - JSON DTOs

private struct GeometryProbeJSON: Encodable {
  let id: String
  let marker: String
  let canvasCells: SizeJSON
  let pixelSize: SizeJSON
  let contentBBoxCells: CellRectJSON?
  let accessibilityElementCount: Int
  let accessibilityElements: [A11yElementJSON]
}

private struct SizeJSON: Encodable { let width: Int; let height: Int }

private struct RectJSON: Encodable {
  let x: Double, y: Double, width: Double, height: Double
  init(from r: CGRect) {
    x = Double(r.origin.x); y = Double(r.origin.y)
    width = Double(r.size.width); height = Double(r.size.height)
  }
}

private struct CellRectJSON: Encodable, CustomStringConvertible {
  let x: Int, y: Int, width: Int, height: Int
  init(from pixelRect: CGRect, scale: CGFloat) {
    // pixels -> points (/scale) -> cells (/10), rounded.
    func cell(_ v: CGFloat) -> Int { Int((v / scale / 10).rounded()) }
    x = cell(pixelRect.origin.x); y = cell(pixelRect.origin.y)
    width = cell(pixelRect.size.width); height = cell(pixelRect.size.height)
  }
  var description: String { "(\(x),\(y),\(width)x\(height))" }
}

private struct A11yElementJSON: Encodable {
  let depth: Int
  let role: String?
  let label: String?
  let value: String?
  let frameScreen: RectJSON?
}
#endif
