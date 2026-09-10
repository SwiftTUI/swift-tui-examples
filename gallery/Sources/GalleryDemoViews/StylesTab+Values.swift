import SwiftTUIRuntime

/// The Values page: the families that render a number, a cadence, or editing
/// content (sections 7 to 11). Sliders and steppers show their route wrappers
/// at work; the spinner section samples a few of the preset catalogue.
struct ValuesPage: View {
  @Binding var sliderValue: Double
  @Binding var stepperValue: Int
  @Binding var progress: Double
  @Binding var editorText: String

  var body: some View {
    stylePageScroll {
      sliderSection
      Divider()
      stepperSection
      Divider()
      progressSection
      Divider()
      spinnerSection
      Divider()
      textEditorSection
    }
  }

  // MARK: - 7. SliderStyle

  private var sliderSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(7, "SliderStyle")
      styleBuiltinsLine([".automatic", ".linear"])
      Slider("Linear", value: $sliderValue, in: 0...1)
      styleCustomLine("BlockSliderStyle")
      Slider("Block", value: $sliderValue, in: 0...1)
        .sliderStyle(BlockSliderStyle())
      Text("state: value=\(StylesTab.readout(sliderValue))").foregroundStyle(.separator)
    }
  }

  // MARK: - 8. StepperStyle

  private var stepperSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(8, "StepperStyle")
      styleBuiltinsLine([".automatic", ".compact"])
      HStack(spacing: 3) {
        Stepper("Automatic", value: $stepperValue, in: 0...9)
        Stepper("Compact", value: $stepperValue, in: 0...9)
          .stepperStyle(.compact)
      }
      .focusSection()
      styleCustomLine("BracketStepperStyle")
      Stepper("Bracket", value: $stepperValue, in: 0...9)
        .stepperStyle(BracketStepperStyle())
      Text("state: value=\(stepperValue)").foregroundStyle(.separator)
    }
  }

  // MARK: - 9. ProgressViewStyle

  private var progressSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(9, "ProgressViewStyle")
      styleBuiltinsLine([".automatic", ".linear", ".circular"])
      HStack(alignment: .top, spacing: 3) {
        ProgressView("Linear", value: progress)
        ProgressView("Circular", value: progress)
          .progressViewStyle(.circular)
        ProgressView("Indexing")
          .progressViewStyle(.circular)
      }
      styleCustomLine("BlockProgressViewStyle")
      HStack(alignment: .top, spacing: 3) {
        ProgressView("Block", value: progress)
          .progressViewStyle(BlockProgressViewStyle())
        ProgressView("Busy")
          .progressViewStyle(BlockProgressViewStyle())
      }
      HStack(spacing: 1) {
        Button("-10%") { progress = max(0, progress - 0.1) }
        Button("+10%") { progress = min(1, progress + 0.1) }
      }
      .focusSection()
      Text("state: fraction=\(StylesTab.readout(progress))").foregroundStyle(.separator)
    }
  }

  // MARK: - 10. SpinnerStyle

  private var spinnerSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(10, "SpinnerStyle")
      styleBuiltinsLine([
        ".automatic", ".dotChase", ".brailleSweep", ".moonPhase", ".clockFace", ".globe",
        "and 32 more presets on AnySpinnerStyle",
      ])
      HStack(spacing: 3) {
        Spinner()
        Spinner().spinnerStyle(.dotChase)
        Spinner().spinnerStyle(.brailleSweep)
        Spinner().spinnerStyle(.moonPhase)
        Spinner().spinnerStyle(.clockFace)
        Spinner().spinnerStyle(.globe)
      }
      styleCustomLine("DotsSpinnerStyle")
      HStack(spacing: 3) {
        Spinner()
        Spinner(stage: .finished)
        Text("stage: .active then .finished").foregroundStyle(.separator)
      }
      .spinnerStyle(DotsSpinnerStyle())
      styleNoteLine("--reduce-motion collapses the custom spinner to one static dot")
    }
  }

  // MARK: - 11. TextEditorStyle

  private var textEditorSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(11, "TextEditorStyle")
      styleBuiltinsLine([".automatic", ".roundedBorder", ".plain"])
      HStack(alignment: .top, spacing: 3) {
        TextEditor(text: $editorText)
          .frame(width: 26, height: 4)
        TextEditor(text: $editorText)
          .textEditorStyle(.plain)
          .frame(width: 26, height: 4)
      }
      styleCustomLine("RuledTextEditorStyle")
      TextEditor(text: $editorText)
        .textEditorStyle(RuledTextEditorStyle())
        .frame(width: 26, height: 5)
    }
  }
}
