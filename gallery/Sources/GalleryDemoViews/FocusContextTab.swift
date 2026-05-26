import SwiftTUIRuntime

private struct GalleryFocusedTitleKey: FocusedValueKey {
  typealias Value = Binding<String>
}

extension FocusedValues {
  var galleryFocusedTitle: Binding<String>? {
    get { self[GalleryFocusedTitleKey.self] }
    set { self[GalleryFocusedTitleKey.self] = newValue }
  }
}

struct FocusContextTab: View {
  @State private var firstTitle = "Coverage matrix"
  @State private var secondTitle = "Focused test lane"
  @FocusedBinding(\.galleryFocusedTitle) private var focusedTitle

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      Divider()
      GroupBox("Focused children publish editable title bindings") {
        VStack(alignment: .leading, spacing: 1) {
          TextField("First title", text: $firstTitle)
            .focusedValue(\.galleryFocusedTitle, $firstTitle)
          TextField("Second title", text: $secondTitle)
            .focusedValue(\.galleryFocusedTitle, $secondTitle)
        }
      }
      GroupBox("Toolbar/status consumer") {
        VStack(alignment: .leading, spacing: 1) {
          LabeledContent("Focused title", value: focusedTitle ?? "none")
          Button("Mark focused reviewed") {
            guard let binding = $focusedTitle else { return }
            binding.wrappedValue = "\(binding.wrappedValue) reviewed"
          }
          .disabled($focusedTitle == nil)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(2)
    .toolbarItem(
      .init(
        title: "Mark Focused",
        action: {
          guard let binding = $focusedTitle else { return }
          binding.wrappedValue = "\(binding.wrappedValue) *"
        }
      )
    )
    .panel(id: "focus-context")
    .toolbar(style: .defaultBottom)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Focus Context").foregroundStyle(.foreground)
      Text("FocusedValue, FocusedBinding, and a toolbar/status consumer of focused child state.")
        .foregroundStyle(.separator)
    }
  }
}
