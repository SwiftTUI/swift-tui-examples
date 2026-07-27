import GIFEditorCore
import SwiftTUI

/// Bridges between `GIFEditorCore`'s platform-neutral `EditorColor` and
/// the SwiftTUI `Color` type. Kept in one place so the view code
/// doesn't sprinkle hex conversions everywhere.
extension EditorColor {
  func toTerminalColor() -> Color {
    Color(
      red: Double(red) / 255.0,
      green: Double(green) / 255.0,
      blue: Double(blue) / 255.0,
      alpha: Double(alpha) / 255.0
    )
  }
}

extension Color {
  /// Source-over alpha composite: `self` painted on top of `background`.
  ///
  /// Straight (non-premultiplied) math in `background`'s color space, which
  /// is the space both sides are already in — every color the canvas blends
  /// came out of ``EditorColor/toTerminalColor()`` or a tint declared beside
  /// it. A terminal cell has no alpha channel to hand back, so the result of
  /// compositing onto an opaque background is opaque, which is what the
  /// renderer needs.
  func composited(over background: Color) -> Color {
    let sourceAlpha = Self.clamped(alpha)
    guard sourceAlpha > 0 else {
      return background
    }
    guard sourceAlpha < 1 else {
      return self
    }
    let backgroundAlpha = Self.clamped(background.alpha)
    let outAlpha = sourceAlpha + backgroundAlpha * (1 - sourceAlpha)
    guard outAlpha > 0 else {
      return background
    }
    func channel(_ source: Double, _ destination: Double) -> Double {
      (source * sourceAlpha + destination * backgroundAlpha * (1 - sourceAlpha)) / outAlpha
    }
    return Color(
      red: channel(red, background.red),
      green: channel(green, background.green),
      blue: channel(blue, background.blue),
      alpha: outAlpha,
      profile: background.profile
    )
  }

  /// Pulls this color's hue toward `tint` by `amount` — `0` leaves it alone,
  /// `1` replaces it outright.
  ///
  /// Only the color channels move. An already-translucent pixel keeps its own
  /// alpha, so tinting cannot quietly make it solid; that separation is what
  /// lets the onion-skin path tint first and fade second without the two
  /// steps fighting.
  func tinted(toward tint: Color, amount: Double) -> Color {
    let t = Self.clamped(amount)
    guard t > 0 else {
      return self
    }
    func mix(_ from: Double, _ to: Double) -> Double {
      from + (to - from) * t
    }
    return Color(
      red: mix(red, tint.red),
      green: mix(green, tint.green),
      blue: mix(blue, tint.blue),
      alpha: alpha,
      profile: profile
    )
  }

  /// The same color at `factor` of its current opacity.
  func faded(by factor: Double) -> Color {
    Color(
      red: red,
      green: green,
      blue: blue,
      alpha: Self.clamped(alpha * Self.clamped(factor)),
      profile: profile
    )
  }

  private static func clamped(_ value: Double) -> Double {
    max(0.0, min(1.0, value))
  }

  /// Converts to the editor's 8-bit-per-channel sRGB representation.
  /// Out-of-gamut components are clamped.
  func toEditorColor() -> EditorColor {
    let r = max(0.0, min(1.0, red))
    let g = max(0.0, min(1.0, green))
    let b = max(0.0, min(1.0, blue))
    let a = max(0.0, min(1.0, alpha))
    return EditorColor(
      red: UInt8((r * 255.0).rounded()),
      green: UInt8((g * 255.0).rounded()),
      blue: UInt8((b * 255.0).rounded()),
      alpha: UInt8((a * 255.0).rounded())
    )
  }
}
