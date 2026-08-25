import SwiftTUIRuntime

// The Transactions page: animation carried by the write path rather than by
// an explicit withAnimation block (section 20). Numbers 10 to 19 are reserved
// for later stages.
extension AnimationsTab {
  var transactionsPage: some View {
    pageScroll {
      bindingAnimationSection
    }
  }

  // MARK: - 20. Binding.animation toggle

  private var bindingAnimationSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(20, "Binding.animation toggle")
      expectLine(
        "bar grows 12 to 40 cells (or back); toggle uses .snappy, button uses 1.5 s easeInOut")
      HStack(spacing: 2) {
        // The Toggle writes through a binding that carries .snappy, so the
        // control itself never mentions animation.
        Toggle("Wide", isOn: $transactionWide.animation(.snappy))
        // Same write path, different curve: the transaction travels with the
        // binding, not with the call site.
        Button("flip (easeInOut)") {
          $transactionWide
            .animation(.easeInOut(duration: .milliseconds(1500)))
            .wrappedValue
            .toggle()
        }
      }
      .focusSection()
      Rectangle()
        .fill(transactionWide ? Color.green : Color.magenta)
        .frame(maxWidth: .finite(transactionWide ? 40 : 12), alignment: .leading)
        .frame(height: 1)
      stateLine("wide=\(transactionWide)")
    }
  }
}
