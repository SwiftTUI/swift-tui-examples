import GIFEditorCore
import SwiftTUI

extension OnionSkinSettings {
  /// ``ghostLayers(around:composites:)``, tinted for the terminal the editor
  /// is actually running in.
  ///
  /// The untinted overload keeps the cool/warm pair
  /// ``OnionSkinAppearance`` declares, which was chosen against a dark
  /// checkerboard. Those two tints are still right there — ``EditorTheme``
  /// hands them straight back for `.dark` — but on a light terminal a pale
  /// blue ghost faded to 45% over a near-white checker is a ghost you cannot
  /// see, so `.light` deepens both.
  ///
  /// A separate entry point rather than a mutated one because the direction a
  /// ghost came from is what selects its tint, and only
  /// ``ghosts(around:frameCount:)`` still knows it — by the time a
  /// ``CanvasGhostLayer`` exists the direction has been spent.
  func ghostLayers(
    around currentIndex: Int,
    composites: [[EditorColor?]],
    theme: EditorTheme
  ) -> [CanvasGhostLayer] {
    ghosts(around: currentIndex, frameCount: composites.count).map { ghost in
      CanvasGhostLayer(
        cells: composites[ghost.frameIndex],
        tint: theme.onionTint(for: ghost.direction),
        opacity: OnionSkinAppearance.opacity(atDistance: ghost.distance)
      )
    }
  }
}
