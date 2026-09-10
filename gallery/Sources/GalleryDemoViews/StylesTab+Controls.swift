import SwiftTUIRuntime

/// The Controls page: the six control families a form is made of (sections
/// 1 to 6). Each section renders the built-ins in the order the `built-ins:`
/// line names them, then the same control under one custom conformance from
/// `StylesTab+CustomStyles.swift`.
struct ControlsPage: View {
  @Binding var buttonPresses: Int
  @Binding var toggleOn: Bool
  @Binding var fieldText: String
  @Binding var pickerChoice: String

  var body: some View {
    stylePageScroll {
      buttonSection
      Divider()
      toggleSection
      Divider()
      textFieldSection
      Divider()
      pickerSection
      Divider()
      linkSection
      Divider()
      labelSection
    }
  }

  // MARK: - 1. ButtonStyle

  private var buttonSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(1, "ButtonStyle")
      styleBuiltinsLine([".automatic", ".plain", ".bordered", ".borderedProminent", ".link"])
      HStack(spacing: 1) {
        Button("Automatic") { buttonPresses += 1 }
        Button("Plain") { buttonPresses += 1 }
          .buttonStyle(.plain)
        Button("Bordered") { buttonPresses += 1 }
          .buttonStyle(.bordered)
        Button("Prominent") { buttonPresses += 1 }
          .buttonStyle(.borderedProminent)
        Button("Link") { buttonPresses += 1 }
          .buttonStyle(.link)
      }
      .focusSection()
      styleCustomLine("BadgeButtonStyle")
      HStack(spacing: 2) {
        Button("Badge") { buttonPresses += 1 }
        Button("Delete", role: .destructive) { buttonPresses += 1 }
        Button("Disabled") {}
          .disabled(true)
      }
      .buttonStyle(BadgeButtonStyle())
      .focusSection()
      Text("state: presses=\(buttonPresses)").foregroundStyle(.separator)
    }
  }

  // MARK: - 2. ToggleStyle

  private var toggleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(2, "ToggleStyle")
      styleBuiltinsLine([".automatic", ".checkbox", ".button"])
      HStack(spacing: 2) {
        Toggle("Automatic", isOn: $toggleOn)
        Toggle("Checkbox", isOn: $toggleOn)
          .toggleStyle(.checkbox)
        Toggle("Button", isOn: $toggleOn)
          .toggleStyle(.button)
      }
      .focusSection()
      styleCustomLine("RailToggleStyle")
      Toggle("Rail", isOn: $toggleOn)
        .toggleStyle(RailToggleStyle())
      Text("state: isOn=\(toggleOn)").foregroundStyle(.separator)
    }
  }

  // MARK: - 3. TextFieldStyle

  private var textFieldSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(3, "TextFieldStyle")
      styleBuiltinsLine([".automatic", ".plain", ".roundedBorder"])
      VStack(alignment: .leading, spacing: 0) {
        TextField("Automatic", text: $fieldText)
        TextField("Plain", text: $fieldText)
          .textFieldStyle(.plain)
        TextField("Rounded", text: $fieldText)
          .textFieldStyle(.roundedBorder)
      }
      .frame(width: 32, alignment: .leading)
      styleCustomLine("UnderlinedTextFieldStyle")
      TextField("Underlined", text: $fieldText)
        .textFieldStyle(UnderlinedTextFieldStyle())
        .frame(width: 32, alignment: .leading)
      Text("state: text=\(fieldText)").foregroundStyle(.separator)
    }
  }

  // MARK: - 4. PickerStyle

  private var pickerSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(4, "PickerStyle")
      styleBuiltinsLine([".automatic", ".inline", ".segmented", ".radioGroup", ".menu"])
      HStack(alignment: .top, spacing: 2) {
        Picker("Inline", selection: $pickerChoice) { pickerOptions }
          .pickerStyle(.inline)
        Picker("Segmented", selection: $pickerChoice) { pickerOptions }
          .pickerStyle(.segmented)
          .frame(height: 4)
        Picker("Radio", selection: $pickerChoice) { pickerOptions }
          .pickerStyle(.radioGroup)
        Picker("Menu", selection: $pickerChoice) { pickerOptions }
          .pickerStyle(.menu)
      }
      .focusSection()
      styleCustomLine("CompactPickerStyle")
      Picker("Compact", selection: $pickerChoice) { pickerOptions }
        .pickerStyle(CompactPickerStyle())
      Text("state: choice=\(pickerChoice)").foregroundStyle(.separator)
    }
  }

  private var pickerOptions: some View {
    ForEach(Self.pickerChoices, id: \.self) { choice in
      Text(choice).tag(choice)
    }
  }

  static let pickerChoices = ["Lists", "Tables", "Outlines"]

  // MARK: - 5. LinkStyle

  private var linkSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(5, "LinkStyle")
      styleBuiltinsLine([".automatic", ".underlined", ".plain"])
      HStack(spacing: 2) {
        Link("Automatic", destination: "https://swifttui.sh")
        Link("Underlined", destination: "https://swifttui.sh")
          .linkStyle(.underlined)
        Link("Plain", destination: "https://swifttui.sh")
          .linkStyle(.plain)
      }
      .focusSection()
      styleCustomLine("InfoLinkStyle")
      Link("Info tone, bold while focused, no underline", destination: "https://swifttui.sh/docs")
        .linkStyle(InfoLinkStyle())
      styleNoteLine("links interpolated into a Text read the same style from the containing Text")
    }
  }

  // MARK: - 6. LabelStyle

  private var labelSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(6, "LabelStyle")
      styleBuiltinsLine([".automatic", ".titleAndIcon", ".titleOnly", ".iconOnly"])
      HStack(spacing: 3) {
        Label("Automatic") { Text("★") }
        Label("Title and icon") { Text("★") }
          .labelStyle(.titleAndIcon)
        Label("Title only") { Text("★") }
          .labelStyle(.titleOnly)
        Label("Icon only") { Text("★") }
          .labelStyle(.iconOnly)
      }
      styleCustomLine("CaptionLabelStyle")
      Label("Caption under the icon") { Text("★") }
        .labelStyle(CaptionLabelStyle())
    }
  }
}
