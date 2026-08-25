import SwiftTUIRuntime

// The Transitions page: insertion and removal transitions (section 2).
extension AnimationsTab {
  var transitionsPage: some View {
    pageScroll {
      transitionSection
    }
  }

  // MARK: - 2. Opacity + move transitions

  private var transitionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(2, ".transition(...) insertion and removal")
      expectLine(
        "FADE dissolves in place; SLIDE moves in from the left and out to the right; 1.2 s each")
      HStack(spacing: 2) {
        Button(showOpacityFigure ? "fade out" : "fade in") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            showOpacityFigure.toggle()
          }
        }
        Button(showSlideFigure ? "slide out" : "slide in") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            showSlideFigure.toggle()
          }
        }
      }
      .focusSection()
      HStack(spacing: 2) {
        // Opacity transition: a large TextFigure fades in/out via the
        // pre-composited cell-background blend.
        TextFigure("FADE", font: .smBlock)
          .opacity(0)
          .overlay {
            if showOpacityFigure {
              TextFigure("FADE", font: .smBlock)
                .foregroundStyle(Color.cyan)
                .transition(.opacity)
            }
          }
          .padding(1)
          .clipped()
          .border(set: .double)
        // Slide transition: .transition(.slide) is an asymmetric
        // move(edge: .leading) in, move(edge: .trailing) out, which
        // exercises the placed-level overlay injection path.
        TextFigure("SLIDE", font: .smBlock)
          .opacity(0)
          .overlay {
            if showSlideFigure {
              TextFigure("SLIDE", font: .smBlock)
                .foregroundStyle(Color.yellow)
                .transition(.slide)
            }
          }
          .padding(1)
          .clipped()
          .border(set: .double)
      }
      stateLine("showFade=\(showOpacityFigure) showSlide=\(showSlideFigure)")
    }
  }
}
