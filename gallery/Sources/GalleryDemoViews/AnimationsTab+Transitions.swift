import SwiftTUIRuntime

// The Transitions page: insertion and removal transitions (section 2) and
// the numericText content transition's rolling counter (section 21).
extension AnimationsTab {
  var transitionsPage: some View {
    pageScroll {
      transitionSection
      Divider()
      rollingCounterSection
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

  // MARK: - 21. .contentTransition(.numericText()) rolling counter

  private var rollingCounterSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(21, ".contentTransition(.numericText()) rolls changed digit columns")
      expectLine(
        "each changed column counts through its intermediate digits over 1.2 s, dimming at "
          + "the midpoint; unchanged columns hold still"
      )
      HStack(spacing: 2) {
        Button("+1") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            rollCount += 1
          }
        }
        Button("+10") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            rollCount += 10
          }
        }
        // A two-column jump (41 -> 68 and back): both digits roll through
        // real intermediates, so even a text capture shows values that are
        // neither the old nor the new string mid-flight.
        Button(rollCount == 41 ? "roll to 68" : "back to 41") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            rollCount = rollCount == 41 ? 68 : 41
          }
        }
      }
      .focusSection()
      // The model value snaps at the click; the roll is entirely in the
      // drawn content, per digit column.
      Text("▶ \(rollCount)")
        .foregroundStyle(Color.cyan)
        .contentTransition(.numericText())
      stateLine("count=\(rollCount)")
    }
  }
}
