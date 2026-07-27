import SwiftTUI

/// What the editor shows instead of itself when the terminal is too narrow to
/// hold it.
///
/// Every line is short on purpose. This view is only ever on screen *below*
/// ``EditorLayoutFloor/minimumWidth``, which is the one place a long line
/// would be broken mid-word by the wrapper — so the longest string here is
/// twenty cells including its padding, and the message still reads at half
/// the width it is complaining about.
///
/// The colors are semantic (`.warning`, `.foreground`, `.muted`) rather than
/// literal, so this screen follows the terminal's own light or dark palette
/// without needing an ``EditorTheme`` of its own.
struct TerminalTooSmallView: View {
  /// What the terminal actually is, so the author can see the gap closing as
  /// they drag the window.
  let available: CellSize
  let requiredWidth: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Terminal too small")
        .foregroundStyle(.warning)
      Text("needs \(requiredWidth) columns")
        .foregroundStyle(.foreground)
      Text("this one is \(available.width)×\(available.height)")
        .foregroundStyle(.muted)
      Text("widen it to continue")
        .foregroundStyle(.muted)
    }
    .padding(.horizontal, 1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
  @ViewBuilder let content: () -> Content

  var body: some View {
    if fits {
      content()
    } else {
      TerminalTooSmallView(
        available: available,
        requiredWidth: EditorLayoutFloor.minimumWidth
      )
    }
  }
}
