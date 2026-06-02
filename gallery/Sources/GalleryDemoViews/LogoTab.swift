import SwiftTUIRuntime

/// Landing page for the gallery: the SwiftTUI mark rendered as a truecolor
/// pixel grid through ``Canvas``.
///
/// ``LogoArt`` supplies a 32×32 `[Color?]` bitmap. The `.verticalHalfBlock`
/// mode packs two vertical pixels into each terminal cell with `▀`/`▄` glyphs,
/// so the 32-tall image occupies `cellHeight(for:)` rows and the roughly 2:1
/// terminal cell aspect reads as square. Transparent pixels (`nil`, the rounded
/// corners) leave the terminal background showing through.
struct LogoTab: View {
  private static let cellWidth = LogoArt.width
  private static let cellHeight = CanvasPixelGridMode.verticalHalfBlock
    .cellHeight(for: LogoArt.height)

  var body: some View {
    VStack(spacing: 1) {
      logo
      Text("SwiftTUI").bold()
      Text("A SwiftUI-shaped terminal UI · press ⌃K for the command palette")
        .foregroundStyle(.separator)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(1)
  }

  private var logo: some View {
    Canvas(
      pixelGridWidth: LogoArt.width,
      height: LogoArt.height,
      pixels: LogoArt.pixels,
      mode: .verticalHalfBlock
    )
    .frame(width: Self.cellWidth, height: Self.cellHeight)
  }
}
