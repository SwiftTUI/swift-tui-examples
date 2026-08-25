import SwiftTUIRuntime

// The Matched page: matchedGeometryEffect (section 6).
extension AnimationsTab {
  var matchedPage: some View {
    pageScroll {
      matchedGeometrySection
    }
  }

  // MARK: - 6. matchedGeometryEffect

  private var matchedGeometrySection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(6, "matchedGeometryEffect: hero slides between two slots")
      expectLine("the ★ hero travels to the other slot over 1.5 s instead of jumping")
      HStack(spacing: 2) {
        Button(heroOnRight ? "move left" : "move right") {
          withAnimation(.easeInOut(duration: .milliseconds(1500))) {
            heroOnRight.toggle()
          }
        }
      }
      .focusSection()
      // Two HStack orderings swapped based on state. The Text("★ hero") is
      // tagged with matchedGeometryEffect(id:in:) scoped to heroNamespace, so
      // the controller recognizes it as the same view across the swap and
      // animates the translation between the two slots.
      HStack(spacing: 3) {
        if !heroOnRight {
          Text("★ hero")
            .foregroundStyle(Color.yellow)
            .matchedGeometryEffect(id: "hero", in: heroNamespace)
          Text("(empty)")
            .foregroundStyle(.muted)
        } else {
          Text("(empty)")
            .foregroundStyle(.muted)
          Text("★ hero")
            .foregroundStyle(Color.yellow)
            .matchedGeometryEffect(id: "hero", in: heroNamespace)
        }
      }
      stateLine("heroOnRight=\(heroOnRight)")
    }
  }
}
