import SwiftTUIRuntime

// The custom conformances the Styles tab renders under each family's
// built-ins. They are deliberately small: each one shows the family's
// configuration surface (captured slots, render state, route wrappers, or the
// modifier-owned baseline) without hiding it behind helpers. Several are the
// same shapes the DocC style guides use, so a reader can diff the gallery
// against the docs and the docs against a compiled, rendered copy.
//
// Two rules every conformance here obeys, because the framework enforces
// them: a style is a value type, and it never takes over what the primitive
// owns (focus, bindings, keyboard commands, dismissal, accessibility).

// MARK: - Body-producing families

/// A button whose leading badge tracks press, focus, and role.
struct BadgeButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    let badge = configuration.isPressed ? "◆" : (configuration.focusActive ? "▶" : "·")
    let badgeColor = theme.color(for: configuration.role == .destructive ? .danger : .tint)
    return HStack(spacing: 1) {
      Text(badge).foregroundStyle(badgeColor)
      configuration.label
    }
    .foregroundStyle(theme.color(for: configuration.isEnabled ? .foreground : .muted))
  }
}

/// A toggle drawn as a two-cell rail with the knob at the active end.
struct RailToggleStyle: ToggleStyle {
  func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    return HStack(spacing: 1) {
      Text(configuration.isOn ? "●━━" : "━━○")
        .foregroundStyle(theme.color(for: configuration.isOn ? .success : .muted))
      configuration.label
      if configuration.focusActive {
        Text("◂").foregroundStyle(theme.color(for: .tint))
      }
    }
  }
}

/// A text field with the editing content on one line and a rule beneath it
/// that brightens while the field is focused. The rule is chrome; the
/// protected `fieldContent` slot keeps editing, caret, and paste behaviour.
struct UnderlinedTextFieldStyle: TextFieldStyle {
  func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        if configuration.showsLabel {
          configuration.label
        }
        configuration.fieldContent
      }
      Text(String(repeating: configuration.focusActive ? "━" : "─", count: 24))
        .foregroundStyle(theme.color(for: configuration.focusActive ? .tint : .muted))
    }
  }
}

/// A picker that lists every option on its own row, bracketing the selected
/// one. Each row is wrapped in `option.route`, so a click selects by
/// occurrence; the arrow keys keep working because the picker owns them.
struct CompactPickerStyle: PickerStyle {
  func makeBody(configuration: PickerStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    return VStack(alignment: .leading, spacing: 0) {
      configuration.label
      ForEach(configuration.options, id: \.index) { option in
        option.route {
          Text(option.isSelected ? "[\(option.label)]" : " \(option.label) ")
            .foregroundStyle(
              theme.color(
                for: option.isSelected && configuration.isFocused ? .tint : .foreground))
        }
      }
    }
  }
}

/// A label that stacks the icon above a muted title.
struct CaptionLabelStyle: LabelStyle {
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.icon
      configuration.title.foregroundStyle(.muted)
    }
  }
}

/// A slider whose track is a block bar. The bar sits inside `track`, so the
/// primitive maps pointer presses and drags onto it.
struct BlockSliderStyle: SliderStyle {
  func makeBody(configuration: SliderStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    let cells = max(configuration.trackCellCount, 4)
    let filled = min(
      cells, max(0, Int((Double(cells) * configuration.fractionCompleted).rounded())))
    return HStack(spacing: 1) {
      configuration.label
      configuration.track {
        Text(String(repeating: "█", count: filled) + String(repeating: "░", count: cells - filled))
          .foregroundStyle(theme.color(for: configuration.focusActive ? .tint : .foreground))
      }
      configuration.valueLabel
    }
  }
}

/// A stepper with bracketed action targets. Each bracket is a route, so a
/// press at a bound still lands on its own disabled target instead of
/// falling through to the other action.
struct BracketStepperStyle: StepperStyle {
  func makeBody(configuration: StepperStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    return HStack(spacing: 1) {
      configuration.label
      configuration.decrement {
        Text("[-]").foregroundStyle(theme.color(for: configuration.canDecrement ? .tint : .muted))
      }
      configuration.valueLabel
      configuration.increment {
        Text("[+]").foregroundStyle(theme.color(for: configuration.canIncrement ? .tint : .muted))
      }
    }
  }
}

/// A progress bar drawn with block glyphs. Indeterminate progress sweeps one
/// lit cell along the bar on the phase the primitive advances.
struct BlockProgressViewStyle: ProgressViewStyle {
  func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    let width = max(configuration.barWidth, 4)
    let bar: String
    if let fraction = configuration.fractionCompleted {
      let filled = min(width, max(0, Int((Double(width) * fraction).rounded())))
      bar = String(repeating: "▰", count: filled) + String(repeating: "▱", count: width - filled)
    } else {
      let head = Int(configuration.indeterminatePhase % UInt64(width))
      bar = (0..<width).map { $0 == head ? "▰" : "▱" }.joined()
    }
    return HStack(spacing: 1) {
      if let label = configuration.label {
        label
      }
      Text(bar).foregroundStyle(theme.color(for: .tint))
      if let currentValueLabel = configuration.currentValueLabel {
        currentValueLabel
      }
    }
  }
}

/// A text editor ruled above and below; the rules brighten with focus while
/// the protected `editorContent` slot keeps editing and caret movement.
struct RuledTextEditorStyle: TextEditorStyle {
  func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    let rule = theme.color(for: configuration.focusActive ? .tint : .muted)
    return VStack(alignment: .leading, spacing: 0) {
      Text(String(repeating: "┄", count: 24)).foregroundStyle(rule)
      configuration.editorContent
      Text(String(repeating: "┄", count: 24)).foregroundStyle(rule)
    }
  }
}

/// A group box with a tinted title rule instead of a border.
struct TitledGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    return VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label {
        HStack(spacing: 1) {
          Text("┃").foregroundStyle(theme.color(for: .tint))
          label
        }
      }
      configuration.content.padding(.leading, 2)
    }
  }
}

/// Labeled content joined by a dotted leader.
struct LeaderLabeledContentStyle: LabeledContentStyle {
  func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      configuration.label
      Text("┈┈┈┈").foregroundStyle(.muted)
      configuration.content
    }
  }
}

/// A disclosure group with a triangle marker and indented content.
///
/// The trigger wraps only the label row, so pointer and keyboard activation
/// toggle the group while interactions with expanded content stay independent.
struct ArrowDisclosureGroupStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    return VStack(alignment: .leading, spacing: 0) {
      configuration.trigger {
        HStack(spacing: 1) {
          Text(configuration.isExpanded ? "▾" : "▸")
            .foregroundStyle(theme.color(for: configuration.focusActive ? .tint : .muted))
          configuration.label
        }
      }
      if configuration.isExpanded {
        configuration.content.padding(.leading, 2)
      }
    }
  }
}

/// A control group whose label sits as a bold banner above a double-bordered
/// row of the captured controls.
struct BannerControlGroupStyle: ControlGroupStyle {
  func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = configuration.label {
        HStack(spacing: 1) {
          Text("▸").foregroundStyle(.tint)
          label
        }
      }
      HStack(spacing: 2) {
        configuration.content
      }
    }
    .padding(.horizontal, 1)
    .border(set: .double)
  }
}

/// A menu with a bracketed trigger whose floating content wears a heavy
/// border. The trigger is wrapped in `trigger`, the inline anchor in
/// `portal`; Menu keeps activation, Escape, and the captured content.
struct BracketMenuStyle: MenuStyle {
  func makeBody(configuration: MenuStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    let bracket = theme.color(for: configuration.focusActive ? .tint : .muted)
    return configuration.portal(presentation: .init(borderStroke: .heavy)) {
      configuration.trigger {
        HStack(spacing: 0) {
          Text("[").foregroundStyle(bracket)
          configuration.label
          Text(configuration.isPresented ? " ▴]" : " ▾]").foregroundStyle(bracket)
        }
      }
    }
  }
}

/// A tab strip that parenthesizes the selected title. Every item is wrapped
/// in `item.route`, so a click selects it; the arrow keys stay with TabView.
struct PillTabViewStyle: TabViewStyle {
  func presentation(for configuration: TabViewStyleConfiguration) -> TabViewStylePresentation {
    TabViewStylePresentation(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  func makeBody(configuration: TabViewStyleBodyConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        ForEach(configuration.visibleItems, id: \.index) { item in
          item.route {
            Text(item.isSelected ? "(\(item.label.title))" : " \(item.label.title) ")
              .foregroundStyle(theme.color(for: item.isSelected ? .tint : .foreground))
          }
        }
      }
      configuration.content
    }
  }
}

/// A palette that lists every command as a plain button row under a bold
/// title. `command.perform()` is the keyboard affordance; the declaration
/// still owns placement, Escape, and dismissal.
struct ListPaletteStyle: PaletteStyle {
  func makeBody(configuration: PaletteStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    return VStack(alignment: .leading, spacing: 0) {
      Text(configuration.title).bold()
      Text("\(configuration.commands.count) commands · Enter runs · Esc closes")
        .foregroundStyle(theme.color(for: .muted))
      ForEach(configuration.commands, id: \.id) { command in
        Button(action: { command.perform() }) {
          HStack(spacing: 1) {
            Text("›").foregroundStyle(theme.color(for: .tint))
            Text(command.name)
            if let description = command.description {
              Text(description).foregroundStyle(theme.color(for: .muted))
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(!command.isEnabled)
      }
      Button("Cancel") { configuration.dismiss() }
        .buttonStyle(.plain)
    }
    .padding(1)
  }
}

// MARK: - Presentation-value families

/// Links in the info tone, bold while focused, with no underline.
struct InfoLinkStyle: LinkStyle {
  func resolvePresentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation {
    LinkStylePresentation(
      foregroundStyle: .semantic(.info),
      emphasis: configuration.focusActive ? [.bold] : [],
      underline: .hidden
    )
  }
}

/// A three-frame dot spinner; one static dot under reduced motion.
struct DotsSpinnerStyle: SpinnerStyle {
  func resolvePresentation(
    for configuration: SpinnerStyleConfiguration
  ) -> SpinnerStylePresentation {
    SpinnerStylePresentation(
      activeFrames: configuration.accessibilityReduceMotion
        ? ["•  "]
        : ["•  ", " • ", "  •"],
      interval: .milliseconds(120)
    )
  }
}

/// A scroll view whose indicators use heavy line glyphs in the warning tone.
struct HeavyScrollViewStyle: ScrollViewStyle {
  func resolvePresentation(
    for configuration: ScrollViewStyleConfiguration
  ) -> ScrollViewStylePresentation {
    ScrollViewStylePresentation(
      snapshotLabel: "HeavyScrollViewStyle",
      verticalIndicatorGlyph: "┃",
      horizontalIndicatorGlyph: "━",
      indicatorStyle: .semantic(.warning),
      focusedIndicatorStyle: .semantic(.tint),
      reservesIndicatorSpace: true
    )
  }
}

/// A sheet three quarters of the terminal wide, with a success-toned header.
/// It transforms the declaration's baseline instead of restating it.
struct WideSheetStyle: SheetStyle {
  func resolvePresentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation {
    var presentation = configuration.defaultPresentation
    presentation.minimumWidth = max(
      presentation.minimumWidth,
      configuration.terminalSize.width * 3 / 4
    )
    presentation.headerTone = .success
    return presentation
  }
}

/// A narrow prompt with a warning-toned header and a double border. Serves
/// alerts and confirmation dialogs alike.
struct CompactPromptStyle: PromptStyle {
  func resolvePresentation(
    for configuration: PromptStyleConfiguration
  ) -> PromptSurfaceStylePresentation {
    var presentation = configuration.defaultPresentation
    presentation.maximumWidth = 36
    presentation.headerTone = .warning
    presentation.borderStroke = .double
    return presentation
  }
}

/// A popover with a double border painted in the info tone and wider insets.
struct DoubleBorderPopoverStyle: PopoverStyle {
  func resolvePresentation(
    for configuration: PopoverStyleConfiguration
  ) -> AnchoredSurfaceStylePresentation {
    var presentation = configuration.defaultPresentation
    presentation.borderStroke = .double
    presentation.borderStyle = .semantic(.info)
    presentation.contentInsets = EdgeInsets(horizontal: 2, vertical: 1)
    return presentation
  }
}

/// A full-screen cover inset by two cells on every side.
struct InsetCoverStyle: FullScreenCoverStyle {
  func resolvePresentation(
    for configuration: FullScreenCoverStyleConfiguration
  ) -> FullScreenSurfaceStylePresentation {
    var presentation = configuration.defaultPresentation
    presentation.contentInsets = EdgeInsets(all: 2)
    return presentation
  }
}

/// A toast with a diamond icon in the tint tone and a wider maximum width.
struct PinnedToastStyle: ToastStyle {
  func resolvePresentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    ToastStylePresentation(icon: "◆", iconStyle: .semantic(.tint), maxWidth: 40)
  }
}

// MARK: - Collection presentations

/// A plain list that keeps its row separators and adds one cell of inset.
struct RuledListStyle: ListStyle {
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    var presentation = ListStylePresentation.plain
    presentation.snapshotLabel = "RuledListStyle"
    presentation.contentInsets = EdgeInsets(horizontal: 1, vertical: 0)
    presentation.showsRowSeparators = true
    return presentation
  }
}

/// A table with a heavy frame in the warning tone and a tinted header row.
struct HeavyTableStyle: TableStyle {
  func resolvePresentation(for configuration: TableStyleConfiguration) -> TableStylePresentation {
    var presentation = TableStylePresentation.bordered
    presentation.snapshotLabel = "HeavyTableStyle"
    presentation.borderGlyphs = TableBorderGlyphs(
      topLeft: "┏", top: "━", topJoin: "┳", topRight: "┓",
      left: "┃", columnJoin: "┃", right: "┃",
      middleLeft: "┣", middle: "━", middleJoin: "╋", middleRight: "┫",
      bottomLeft: "┗", bottom: "━", bottomJoin: "┻", bottomRight: "┛"
    )
    presentation.borderStyle = .semantic(.warning)
    presentation.headerForegroundStyle = .semantic(.tint)
    return presentation
  }
}

/// An outline whose guides are dotted and whose leaves end in a bullet.
struct DottedOutlineStyle: OutlineStyle {
  func resolvePresentation(
    for configuration: OutlineStyleConfiguration
  ) -> OutlineStylePresentation {
    OutlineStylePresentation(
      snapshotLabel: "DottedOutlineStyle",
      continuingIndenter: "┆ ",
      emptyIndenter: "  ",
      branchConnector: "┆╴ ",
      leafConnector: "•╴ "
    )
  }
}
