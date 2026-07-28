import SwiftTUI

/// What the editor shows instead of itself when the terminal is too small to
/// hold it.
///
/// Every line is short on purpose. This view is only ever on screen *below*
/// the editor's own floor, which is the one place a long line would be broken
/// mid-word by the wrapper — so the longest string here is twenty-odd cells
/// including its padding, and the message still reads at half the width it is
/// complaining about.
///
/// It names both dimensions rather than only the one that is short. A terminal
/// that is 60×30 and one that is 80×12 fail for opposite reasons, and an
/// author dragging a window corner needs to know which way to drag.
///
/// The colors are semantic (`.warning`, `.foreground`, `.muted`) rather than
/// literal, so this screen follows the terminal's own light or dark palette
/// without needing an ``EditorTheme`` of its own.
struct TerminalTooSmallView: View {
  /// What the terminal actually is, so the author can see the gap closing as
  /// they drag the window.
  let available: CellSize
  let requiredWidth: Int
  let requiredHeight: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Terminal too small")
        .foregroundStyle(.warning)
      Text("needs \(requiredWidth) columns")
        .foregroundStyle(shortOfWidth ? .warning : .foreground)
      Text("needs \(requiredHeight) rows")
        .foregroundStyle(shortOfHeight ? .warning : .foreground)
      Text("this one is \(available.width)×\(available.height)")
        .foregroundStyle(.muted)
      Text(hint)
        .foregroundStyle(.muted)
    }
    .padding(.horizontal, 1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var shortOfWidth: Bool { available.width < requiredWidth }
  private var shortOfHeight: Bool { available.height < requiredHeight }

  /// Which way to drag. Named for the axis that is actually short, because
  /// "resize it" is advice the author already has.
  private var hint: String {
    switch (shortOfWidth, shortOfHeight) {
    case (true, true): "grow it to continue"
    case (true, false): "widen it to continue"
    case (false, true): "make it taller"
    case (false, false): "resize it to continue"
    }
  }
}

/// Shows `content` when the terminal can hold it, and
/// ``TerminalTooSmallView`` when it cannot.
///
/// A view rather than an `if` written inline for one structural reason: the
/// editor's stack is ninety lines long and lives inside a `body` whose root
/// modifier chain is already at its resolve-stack budget. Wrapping the stack
/// in a conditional here keeps the branch one line at the call site and the
/// *chain* — the expensive part — untouched, and it puts the "what does too
/// small look like" answer in one place instead of two.
struct TerminalFitGate<Content: View>: View {
  let fits: Bool
  let available: CellSize
  let content: Content

  init(
    fits: Bool,
    available: CellSize,
    @ViewBuilder content: () -> Content
  ) {
    self.fits = fits
    self.available = available
    self.content = content()
  }

  var body: some View {
    if fits {
      content
    } else {
      TerminalTooSmallView(
        available: available,
        requiredWidth: EditorLayoutFloor.minimumWidth,
        requiredHeight: EditorLayoutFloor.minimumHeight
      )
    }
  }
}
