import SwiftTUIRuntime

/// The style kits the Scoping page switches between. The form is declared
/// once; only the modifier chain around it changes.
enum StyleKit: String, CaseIterable, Hashable, Sendable {
  case standard = "Standard"
  case boxed = "Boxed"
  case custom = "Custom"
}

/// The Scoping page: how styles reach controls (sections 29 and 30). Every
/// environment-scoped family follows the same rule, so the page shows it once
/// with buttons and then with a whole form.
struct ScopingPage: View {
  @Binding var kit: StyleKit
  @Binding var kitToggle: Bool
  @Binding var kitText: String
  @Binding var kitProgress: Double
  @Binding var kitSlider: Double
  @Binding var kitStepper: Int
  @Binding var kitSaves: Int

  var body: some View {
    stylePageScroll {
      nearestWinsSection
      Divider()
      kitSection
    }
  }

  // MARK: - 29. Nearest modifier wins

  private var nearestWinsSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(29, "Nearest modifier wins")
      styleBuiltinsLine([".bordered on the row", ".plain on the last button"])
      HStack(spacing: 1) {
        Button("Inherits bordered") { kitSaves += 1 }
        Button("Also bordered") { kitSaves += 1 }
        Button("Overrides to plain") { kitSaves += 1 }
          .buttonStyle(.plain)
      }
      .buttonStyle(.bordered)
      .focusSection()
      styleNoteLine(
        "a style set on a container reaches every descendant until a closer modifier replaces it")
    }
  }

  // MARK: - 30. One modifier chain restyles a subtree

  private var kitSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(30, "One modifier chain restyles a subtree")
      styleBuiltinsLine(StyleKit.allCases.map(\.rawValue))
      Picker("Kit", selection: $kit) {
        ForEach(StyleKit.allCases, id: \.self) { kit in
          Text(kit.rawValue).tag(kit)
        }
      }
      .pickerStyle(.segmented)
      .frame(height: 4)
      styled(kit) { kitForm }
      Text("state: kit=\(kit.rawValue) saves=\(kitSaves)").foregroundStyle(.separator)
    }
  }

  private var kitForm: some View {
    GroupBox("Deploy") {
      VStack(alignment: .leading, spacing: 0) {
        TextField("Name", text: $kitText)
        Toggle("Run tests", isOn: $kitToggle)
        Slider("Canary", value: $kitSlider, in: 0...1)
        Stepper("Replicas", value: $kitStepper, in: 1...9)
        ProgressView("Rollout", value: kitProgress)
        HStack(spacing: 1) {
          Button("Save") { kitSaves += 1 }
          Button("Discard", role: .destructive) { kitSaves = 0 }
        }
        .focusSection()
      }
    }
  }

  /// Wraps `content` in the modifier chain for `kit`. The form inside is the
  /// same value in every branch; the chain is the only thing that differs.
  @ViewBuilder
  private func styled<Content: View>(
    _ kit: StyleKit,
    @ViewBuilder content: () -> Content
  ) -> some View {
    switch kit {
    case .standard:
      content()
    case .boxed:
      content()
        .buttonStyle(.bordered)
        .toggleStyle(.checkbox)
        .textFieldStyle(.roundedBorder)
        .stepperStyle(.compact)
        .progressViewStyle(.circular)
        .groupBoxStyle(.bordered)
    case .custom:
      content()
        .buttonStyle(BadgeButtonStyle())
        .toggleStyle(RailToggleStyle())
        .textFieldStyle(UnderlinedTextFieldStyle())
        .sliderStyle(BlockSliderStyle())
        .stepperStyle(BracketStepperStyle())
        .progressViewStyle(BlockProgressViewStyle())
        .groupBoxStyle(TitledGroupBoxStyle())
    }
  }
}
