import SwiftTUIRuntime

struct FormsAndContainersTab: View {
  private enum Priority: String, CaseIterable, Hashable, Sendable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
  }

  @State private var title = "Ship examples matrix"
  @State private var owner = "Documentation"
  @State private var priority: Priority = .normal
  @State private var includeTests = true
  @State private var isExpanded = true
  @State private var savedCount = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        header
        Divider()
        GroupBox("Issue form") {
          VStack(alignment: .leading, spacing: 1) {
            TextField("Title", text: $title)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .accessibilityLabel("Example title")
              .accessibilityHint("Edits the title used by the preview summary.")
            TextField("Owner", text: $owner)
              .textFieldStyle(PlainTextFieldStyle())
            Toggle("Include focused tests", isOn: $includeTests)
            Picker("Priority", selection: $priority) {
              ForEach(Priority.allCases, id: \.self) { priority in
                Text(priority.rawValue).tag(priority)
              }
            }
            .pickerStyle(SegmentedPickerStyle())
          }
        }

        GroupBox("Review summary") {
          VStack(alignment: .leading, spacing: 0) {
            LabeledContent("Title", value: title)
            LabeledContent("Owner", value: owner)
            LabeledContent("Priority", value: priority.rawValue)
            LabeledContent("Focused tests", value: includeTests ? "required" : "build-only")
          }
          .accessibilityLiveRegion(.polite)
        }

        DisclosureGroup("Validation details", isExpanded: $isExpanded) {
          VStack(alignment: .leading, spacing: 0) {
            Text(includeTests ? "Focused tests will be added to check:focused." : "Build gate only.")
            Link("SwiftTUI repository", destination: "https://github.com/SwiftTUI/swift-tui")
              .buttonStyle(LinkButtonStyle())
          }
          .padding(.leading, 2)
        }

        ControlGroup("Actions") {
          Button("Save draft") {
            savedCount += 1
          }
          .buttonStyle(BorderedProminentButtonStyle())
          Button("Reset") {
            title = "Ship examples matrix"
            owner = "Documentation"
            priority = .normal
            includeTests = true
          }
          .buttonStyle(BorderedButtonStyle())
          Button("Disabled") {}
            .buttonStyle(PlainButtonStyle())
            .disabled(true)
        }

        Text("Saved drafts: \(savedCount)")
          .foregroundStyle(.separator)
          .accessibilityLabel("Saved draft count")
        Spacer(minLength: 0)
      }
      .padding(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Forms & Containers").foregroundStyle(.foreground)
      Text("GroupBox, ControlGroup, DisclosureGroup, Link, picker styles, button styles, text-field styles, disabled state, and accessibility metadata.")
        .foregroundStyle(.separator)
    }
  }
}
