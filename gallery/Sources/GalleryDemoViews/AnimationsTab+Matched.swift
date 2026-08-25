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
      expectLine("the box travels and resizes to the other slot over 1.5 s instead of jumping")
      HStack(spacing: 2) {
        Button(heroOnRight ? "move left" : "move right") {
          withAnimation(.easeInOut(duration: .milliseconds(1500))) {
            heroOnRight.toggle()
          }
        }
      }
      .focusSection()
      // Two HStack orderings swapped based on state. The "ONE ONE ONE" is
      // tagged with matchedGeometryEffect(id:in:) scoped to heroNamespace, so
      // the controller recognizes it as the same view across the swap and
      // animates the translation between the two slots.
      HStack(spacing: 3) {
        if !heroOnRight {
          Text("ONE ONE ONE")
            .foregroundStyle(Color.yellow)
            .padding(3)
            .background(Color.red)
            .matchedGeometryEffect(id: "hero", in: heroNamespace)
          Spacer()
        } else {
          Spacer()
          Text("TWO")
            .foregroundStyle(Color.yellow)
            .background(Color.blue)
            .matchedGeometryEffect(id: "hero", in: heroNamespace)
        }
      }
      stateLine("heroOnRight=\(heroOnRight)")
    }
  }
}
