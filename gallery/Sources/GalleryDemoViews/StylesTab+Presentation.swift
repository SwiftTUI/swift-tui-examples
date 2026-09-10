import SwiftTUIRuntime

// The Presentation page: the portal families (sections 23 to 28). Each
// button opens a real presentation under a style; the style chose the
// chrome, the declaration kept modality, focus, Escape, and dismissal.
//
// The style modifiers sit OUTSIDE the presentation modifiers they affect:
// a `.sheetStyle` after `.sheet(...)` is what the sheet reads, because the
// environment flows into the modifier node from above.
//
// The page and every section here are their own `View` structs holding
// bindings, not computed properties on the tab. A presentation section's
// value is large (it carries sheet, alert, and toast content closures), and a
// tuple of six such values is copied through the debug resolver's nested
// closures deeply enough to exhaust the 8 MB main-thread stack. A struct of
// bindings stays pointer-sized until its body resolves.
struct PresentationPage: View {
  @Binding var showSurfaceSheet: Bool
  @Binding var showDropdownSheet: Bool
  @Binding var showWideSheet: Bool
  @Binding var showAlert: Bool
  @Binding var showConfirmation: Bool
  @Binding var showCompactAlert: Bool
  @Binding var showPopover: Bool
  @Binding var showStyledPopover: Bool
  @Binding var showCover: Bool
  @Binding var showInsetCover: Bool
  @Binding var showInfoToast: Bool
  @Binding var showSuccessToast: Bool
  @Binding var showWarningToast: Bool
  @Binding var showDangerToast: Bool
  @Binding var showPinnedToast: Bool
  @Binding var showPalette: Bool
  @Binding var lastPresentationEvent: String

  var body: some View {
    stylePageScroll {
      SheetStyleSection(
        showSurface: $showSurfaceSheet,
        showDropdown: $showDropdownSheet,
        showWide: $showWideSheet,
        lastEvent: $lastPresentationEvent
      )
      Divider()
      PromptStyleSection(
        showAlert: $showAlert,
        showConfirmation: $showConfirmation,
        showCompactAlert: $showCompactAlert,
        lastEvent: $lastPresentationEvent
      )
      Divider()
      PopoverStyleSection(showPopover: $showPopover, showStyledPopover: $showStyledPopover)
      Divider()
      CoverStyleSection(
        showCover: $showCover,
        showInsetCover: $showInsetCover,
        lastEvent: $lastPresentationEvent
      )
      Divider()
      ToastStyleSection(
        showInfo: $showInfoToast,
        showSuccess: $showSuccessToast,
        showWarning: $showWarningToast,
        showDanger: $showDangerToast,
        showPinned: $showPinnedToast
      )
      Divider()
      PaletteStyleSection(showPalette: $showPalette)
      Divider()
      Text("state: last=\(lastPresentationEvent)").foregroundStyle(.separator)
    }
    .panel(id: "styles-presentation")
    .paletteCommand(
      name: "Reset the presentation readout",
      action: { lastPresentationEvent = "reset from the palette" }
    )
    .paletteCommand(
      name: "Mark the presentation readout",
      action: { lastPresentationEvent = "marked from the palette" }
    )
    .paletteSheet("Style commands", isPresented: $showPalette)
    .paletteStyle(ListPaletteStyle())
  }
}

// MARK: - 23. SheetStyle

private struct SheetStyleSection: View {
  @Binding var showSurface: Bool
  @Binding var showDropdown: Bool
  @Binding var showWide: Bool
  @Binding var lastEvent: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(23, "SheetStyle")
      styleBuiltinsLine([".automatic", ".surface", ".dropdown"])
      HStack(spacing: 2) {
        Button("Surface sheet") { showSurface = true }
          .sheet("Surface sheet", isPresented: $showSurface) { sheetBody("surface") }
          .sheetStyle(.surface)
        Button("Dropdown sheet") { showDropdown = true }
          .sheet("Dropdown sheet", isPresented: $showDropdown) { sheetBody("dropdown") }
          .sheetStyle(.dropdown)
      }
      .focusSection()
      styleCustomLine("WideSheetStyle")
      Button("Wide sheet") { showWide = true }
        .sheet("Wide sheet", isPresented: $showWide) { sheetBody("wide") }
        .sheetStyle(WideSheetStyle())
    }
  }

  private func sheetBody(_ name: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("The \(name) sheet style").bold()
      Text("The style chose the chrome. The sheet kept modality, focus, and Escape.")
      Button("Close") {
        showSurface = false
        showDropdown = false
        showWide = false
        lastEvent = "\(name) sheet closed"
      }
    }
    .padding(1)
  }
}

// MARK: - 24. PromptStyle

private struct PromptStyleSection: View {
  @Binding var showAlert: Bool
  @Binding var showConfirmation: Bool
  @Binding var showCompactAlert: Bool
  @Binding var lastEvent: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(24, "PromptStyle")
      styleBuiltinsLine([".automatic"])
      HStack(spacing: 2) {
        Button("Alert") { showAlert = true }
          .alert(
            "Automatic prompt",
            isPresented: $showAlert,
            actions: {
              Button("OK") {
                showAlert = false
                lastEvent = "alert accepted"
              }
            },
            message: {
              Text("The automatic style returns the declaration's own baseline.")
            }
          )
        Button("Confirm") { showConfirmation = true }
          .confirmationDialog(
            "Automatic confirmation",
            isPresented: $showConfirmation,
            actions: {
              Button("Proceed", role: .destructive) {
                showConfirmation = false
                lastEvent = "confirmation proceeded"
              }
              Button("Cancel") {
                showConfirmation = false
                lastEvent = "confirmation cancelled"
              }
            },
            message: {
              Text("One PromptStyle serves alerts and confirmation dialogs.")
            }
          )
      }
      .focusSection()
      styleCustomLine("CompactPromptStyle")
      Button("Compact alert") { showCompactAlert = true }
        .alert(
          "Compact prompt",
          isPresented: $showCompactAlert,
          actions: {
            Button("OK") {
              showCompactAlert = false
              lastEvent = "compact alert accepted"
            }
          },
          message: {
            Text("At most 36 cells wide, warning header, double border.")
          }
        )
        .promptStyle(CompactPromptStyle())
    }
  }
}

// MARK: - 25. PopoverStyle

private struct PopoverStyleSection: View {
  @Binding var showPopover: Bool
  @Binding var showStyledPopover: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(25, "PopoverStyle")
      styleBuiltinsLine([".automatic"])
      Button("Popover") { showPopover = true }
        .popover(isPresented: $showPopover, arrowEdge: .top) { popoverBody("automatic") }
      styleCustomLine("DoubleBorderPopoverStyle")
      Button("Double-border popover") { showStyledPopover = true }
        .popover(isPresented: $showStyledPopover, arrowEdge: .top) { popoverBody("double-border") }
        .popoverStyle(DoubleBorderPopoverStyle())
    }
  }

  private func popoverBody(_ name: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("The \(name) popover").bold()
      Text("Anchored to its button; Escape closes it.")
    }
    .padding(1)
  }
}

// MARK: - 26. FullScreenCoverStyle

private struct CoverStyleSection: View {
  @Binding var showCover: Bool
  @Binding var showInsetCover: Bool
  @Binding var lastEvent: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(26, "FullScreenCoverStyle")
      styleBuiltinsLine([".automatic"])
      Button("Cover") { showCover = true }
        .fullScreenCover(isPresented: $showCover) { coverBody("automatic") }
      styleCustomLine("InsetCoverStyle")
      Button("Inset cover") { showInsetCover = true }
        .fullScreenCover(isPresented: $showInsetCover) { coverBody("inset") }
        .fullScreenCoverStyle(InsetCoverStyle())
    }
  }

  private func coverBody(_ name: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("The \(name) cover").bold()
      Text("A cover always fills the terminal; the style controls insets and background.")
      Button("Close") {
        showCover = false
        showInsetCover = false
        lastEvent = "\(name) cover closed"
      }
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .border(set: .rounded)
  }
}

// MARK: - 27. ToastStyle

private struct ToastStyleSection: View {
  @Binding var showInfo: Bool
  @Binding var showSuccess: Bool
  @Binding var showWarning: Bool
  @Binding var showDanger: Bool
  @Binding var showPinned: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(27, "ToastStyle")
      styleBuiltinsLine([".info", ".success", ".warning", ".danger"])
      HStack(spacing: 2) {
        Button("Info") { showInfo = true }
          .toast("An info toast", isPresented: $showInfo, style: .info, duration: 2)
        Button("Success") { showSuccess = true }
          .toast("A success toast", isPresented: $showSuccess, style: .success, duration: 2)
        Button("Warning") { showWarning = true }
          .toast("A warning toast", isPresented: $showWarning, style: .warning, duration: 2)
        Button("Danger") { showDanger = true }
          .toast("A danger toast", isPresented: $showDanger, style: .danger, duration: 2)
      }
      .focusSection()
      styleCustomLine("PinnedToastStyle")
      Button("Pinned") { showPinned = true }
        .toast(
          "A custom toast presentation", isPresented: $showPinned, style: PinnedToastStyle(),
          duration: 2)
      styleNoteLine("toast style is per declaration: passed to .toast(style:), never inherited")
    }
  }
}

// MARK: - 28. PaletteStyle

private struct PaletteStyleSection: View {
  @Binding var showPalette: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(28, "PaletteStyle")
      styleBuiltinsLine([".automatic"])
      styleCustomLine("ListPaletteStyle")
      Button("Open the styled palette") { showPalette = true }
      styleNoteLine(
        "the shell's ⌃K palette stays .automatic; this page's palette lists each command as a row")
    }
  }
}
