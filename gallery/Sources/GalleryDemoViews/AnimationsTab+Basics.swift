import SwiftTUIRuntime

// The Basics page: withAnimation driving color, frame, offset, position, and
// the completion callback (sections 1, 3, 4, 5, 9).
//
// `AnimationRegressionTests` clicks section 4's "right" button and watches the
// "slide me" marker travel 30 cells, so keep that section's button labels,
// offsets, and durations as they are.
extension AnimationsTab {
  var basicsPage: some View {
    pageScroll {
      colorSection
      Divider()
      frameSection
      Divider()
      offsetSection
      Divider()
      positionSection
      Divider()
      completionSection
    }
  }

  // MARK: - 1. Color animation with spring / bezier / bouncy curves

  private var colorSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(1, "withAnimation foreground color")
      expectLine("the bar cross-fades red to blue (or back) over 1.5 s with the chosen curve")
      HStack(spacing: 1) {
        Button("linear") {
          withAnimation(.linear(duration: .milliseconds(1500))) {
            colorBlue.toggle()
            curveLabel = "linear"
          }
        }
        Button("easeInOut") {
          withAnimation(.easeInOut(duration: .milliseconds(1500))) {
            colorBlue.toggle()
            curveLabel = "easeInOut"
          }
        }
        Button("spring") {
          withAnimation(.spring(duration: .milliseconds(1500), bounce: 0.3)) {
            colorBlue.toggle()
            curveLabel = "spring"
          }
        }
        Button("bouncy") {
          withAnimation(.bouncy) {
            colorBlue.toggle()
            curveLabel = "bouncy"
          }
        }
      }
      .focusSection()
      Text("████████████████████████████")
        .foregroundStyle(colorBlue ? Color.blue : Color.red)
        .padding(1)
        .border(set: .single)
      stateLine("colorBlue=\(colorBlue) curve=\(curveLabel)")
    }
  }

  // MARK: - 3. Frame size animation

  private var frameSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(3, "frame animation via .frame(maxWidth:) under .smooth")
      expectLine("the centered label's slot widens from 12 to 40 cells (or back) over 1.5 s")
      HStack(spacing: 2) {
        Button("narrow") {
          withAnimation(.smooth(duration: .milliseconds(1500))) {
            wide = false
          }
        }
        Button("wide") {
          withAnimation(.smooth(duration: .milliseconds(1500))) {
            wide = true
          }
        }
      }
      .focusSection()
      Text(wide ? "◆ wide ◆" : "narrow")
        .foregroundStyle(.foreground)
        .frame(
          maxWidth: .finite(wide ? 40 : 12),
          alignment: .center
        )
      stateLine("wide=\(wide)")
    }
  }

  // MARK: - 4. .offset animation via direct state mutation

  private var offsetSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(4, ".offset(x:y:) animation via withAnimation state change")
      expectLine("the magenta marker glides to column 0, 15, or 30 over 1.2 s; spring overshoots")
      HStack(spacing: 2) {
        Button("left") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            offsetX = 0
          }
        }
        Button("center") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            offsetX = 15
          }
        }
        Button("right") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            offsetX = 30
          }
        }
        Button("spring") {
          withAnimation(.spring(duration: .milliseconds(1500), bounce: 0.4)) {
            offsetX = offsetX == 0 ? 30 : 0
          }
        }
      }
      .focusSection()
      Text("▶ slide me")
        .foregroundStyle(Color.magenta)
        .offset(x: offsetX, y: 0)
      stateLine("offsetX=\(offsetX)")
    }
  }

  // MARK: - 5. .position animation via absolute placement

  private var positionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(5, ".position(x:y:) absolute placement animated via withAnimation")
      expectLine("the ◎ marker glides between the four corners of its slot over 1.2 s")
      HStack(spacing: 2) {
        Button("NW") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            positionX = 10
            positionY = 1
          }
        }
        Button("NE") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            positionX = 50
            positionY = 1
          }
        }
        Button("SW") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            positionX = 10
            positionY = 5
          }
        }
        Button("SE") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            positionX = 50
            positionY = 5
          }
        }
      }
      .focusSection()
      // The marker is absolutely positioned inside a fixed six-row slot
      // (y in 1...5). Without the explicit height, .position would expand
      // to fill the full proposed space of the page, shoving later sections
      // off the screen.
      Text("◎")
        .foregroundStyle(Color.cyan)
        .position(x: positionX, y: positionY)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 6)
      stateLine("positionX=\(positionX) positionY=\(positionY)")
    }
  }

  // MARK: - 9. withAnimation completion callback

  private var completionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(9, "withAnimation completion callback")
      expectLine("the bar swaps green/magenta over 1.2 s, then completions goes up by one")
      HStack(spacing: 2) {
        Button("run") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            completionAccent.toggle()
          } completion: {
            completionRuns += 1
          }
        }
      }
      .focusSection()
      Text("██████████████████████")
        .foregroundStyle(completionAccent ? Color.magenta : Color.green)
      stateLine("completionAccent=\(completionAccent) completions=\(completionRuns)")
    }
  }
}
