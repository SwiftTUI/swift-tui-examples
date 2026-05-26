import SwiftTUIRuntime

struct PresentationLabTab: View {
  @State private var showAlert = false
  @State private var showConfirmation = false
  @State private var showSheet = false
  @State private var showToast = false
  @State private var showPopover = false
  @State private var showTip = false
  @State private var showPalette = false
  @State private var lastEvent = "No presentation opened yet"

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      Divider()
      ControlGroup("Modals") {
        Button("Alert") { showAlert = true }
        Button("Confirm") { showConfirmation = true }
        Button("Sheet") { showSheet = true }
      }
      ControlGroup("Anchored") {
        Button("Toast") { showToast = true }
        Button("Popover") { showPopover = true }
          .popover(isPresented: $showPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
              Text("Popover content").bold()
              Text("Attached to the Popover button.")
            }
            .padding(1)
          }
        Button("Tip") { showTip = true }
          .popoverTip(
            PresentationLabTip(),
            isPresented: $showTip,
            arrowEdge: .top
          ) { action in
            lastEvent = "Tip action: \(action.title)"
            showTip = false
          }
      }
      ControlGroup("Command surface") {
        Button("Palette") { showPalette = true }
      }
      Text("Last event: \(lastEvent)")
        .foregroundStyle(.separator)
      Spacer(minLength: 0)
    }
    .padding(2)
    .panel(id: "presentation-lab")
    .paletteCommand(
      name: "Presentation Lab Sample Action",
      action: {
        lastEvent = "Palette command fired"
      }
    )
    .paletteSheet("Presentation commands", isPresented: $showPalette) { commands in
      CommandPaletteList(
        commands: commands,
        dismiss: { showPalette = false }
      )
    }
    .alert(
      "Build gate updated",
      isPresented: $showAlert,
      actions: {
        Button("OK") {
          lastEvent = "Alert accepted"
          showAlert = false
        }
      },
      message: {
        Text("The example build lane now covers this surface.")
      }
    )
    .confirmationDialog(
      "Reset presentation state?",
      isPresented: $showConfirmation,
      actions: {
        Button("Reset", role: .destructive) {
          lastEvent = "Confirmation reset"
          showConfirmation = false
        }
        Button("Cancel") {
          showConfirmation = false
        }
      },
      message: {
        Text("Confirmation dialogs sit near the invoking surface.")
      }
    )
    .sheet("Presentation Sheet", isPresented: $showSheet) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Sheet content").bold()
        Text("Sheets can host arbitrary SwiftTUI views.")
        Button("Close") {
          lastEvent = "Sheet closed"
          showSheet = false
        }
      }
      .padding(1)
    }
    .toast("Presentation toast", isPresented: $showToast, duration: 2.0)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Presentation Lab").foregroundStyle(.foreground)
      Text("alert, confirmationDialog, sheet, toast, popover, popoverTip, and paletteSheet.")
        .foregroundStyle(.separator)
    }
  }
}

private struct PresentationLabTip: PopoverTip {
  let id = "presentation-lab-tip"

  var title: Text {
    Text("Popover tip")
  }

  var message: Text? {
    Text("Tips use the same source attachment model as popovers.")
  }

  var icon: Text? {
    Text("?")
  }

  var actions: [PopoverTipAction] {
    [
      .init(id: "got-it", title: "Got it")
    ]
  }
}
