import Layouts
import Splash
import SwiftUI
import SwiftUIHost
import SwiftUILayouts

private typealias NativeLayoutCatalog = SwiftUILayouts.LayoutCatalog
private typealias NativeLayoutEntry = SwiftUILayouts.LayoutEntry

@main
struct LayoutsApp: SwiftUI::App {
  var body: some SwiftUI::Scene {
    SwiftUI.WindowGroup {
      LayoutsRoot()
    }
  }
}

struct LayoutsRoot: SwiftUI::View {
  @SwiftUI::State private var selectedID = NativeLayoutCatalog.all.first?.id
  @SwiftUI.FocusState private var receivesLayoutNavigation: Bool

  var body: some SwiftUI::View {
    SwiftUI.HStack(alignment: .top, spacing: 0) {
      LayoutSidebar(selectedID: $selectedID)
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 360)

      SwiftUI.Divider()

      if let selectedEntry {
        LayoutComparisonDetail(entry: selectedEntry)
      } else {
        SwiftUI.ContentUnavailableView("No Layout", systemImage: "rectangle.split.2x1")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .focusable(true)
    .focused($receivesLayoutNavigation)
    .defaultFocus($receivesLayoutNavigation, true)
    .onAppear {
      receivesLayoutNavigation = true
    }
    .onKeyPress(.upArrow) {
      moveSelection(by: -1)
      return .handled
    }
    .onKeyPress(.downArrow) {
      moveSelection(by: 1)
      return .handled
    }
  }

  private var selectedEntry: NativeLayoutEntry? {
    guard let selectedID else {
      return nil
    }

    return NativeLayoutCatalog.entry(id: selectedID)
  }

  private func moveSelection(by offset: Int) {
    guard !NativeLayoutCatalog.all.isEmpty else {
      selectedID = nil
      return
    }

    guard
      let selectedID,
      let currentIndex = NativeLayoutCatalog.all.firstIndex(where: { $0.id == selectedID })
    else {
      selectedID = NativeLayoutCatalog.all.first?.id
      return
    }

    let nextIndex = min(
      max(currentIndex + offset, NativeLayoutCatalog.all.startIndex),
      NativeLayoutCatalog.all.index(before: NativeLayoutCatalog.all.endIndex)
    )
    self.selectedID = NativeLayoutCatalog.all[nextIndex].id
  }
}

private struct LayoutSidebar: SwiftUI::View {
  @SwiftUI::Binding var selectedID: NativeLayoutEntry.ID?

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 0) {
      SwiftUI.VStack(alignment: .leading, spacing: 4) {
        SwiftUI.Text("Layouts")
          .font(.title2.weight(.semibold))
        SwiftUI.Text("\(NativeLayoutCatalog.all.count) examples")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding()

      SwiftUI.Divider()

      SwiftUI.ScrollViewReader { proxy in
        SwiftUI.ScrollView {
          SwiftUI.LazyVStack(alignment: .leading, spacing: 14) {
            SwiftUI.ForEach(NativeLayoutEntry.Category.allCases, id: \.rawValue) { category in
              let entries = NativeLayoutCatalog.all.filter { $0.category == category }
              if !entries.isEmpty {
                LayoutSidebarSection(
                  category: category,
                  entries: entries,
                  selectedID: $selectedID
                )
              }
            }
          }
          .padding(12)
        }
        .onChange(of: selectedID) { _, newValue in
          guard let newValue else {
            return
          }

          withAnimation {
            proxy.scrollTo(newValue, anchor: .center)
          }
        }
      }
    }
    .background(.background)
  }
}

private struct LayoutSidebarSection: SwiftUI::View {
  let category: NativeLayoutEntry.Category
  let entries: [NativeLayoutEntry]
  @SwiftUI::Binding var selectedID: NativeLayoutEntry.ID?

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 4) {
      SwiftUI.Text(category.rawValue)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 6)

      SwiftUI.VStack(alignment: .leading, spacing: 2) {
        SwiftUI.ForEach(entries) { entry in
          SwiftUI.Button {
            selectedID = entry.id
          } label: {
            LayoutSidebarRow(
              entry: entry,
              isSelected: selectedID == entry.id
            )
          }
          .id(entry.id)
          .buttonStyle(.plain)
        }
      }
    }
  }
}

private struct LayoutSidebarRow: SwiftUI::View {
  let entry: NativeLayoutEntry
  let isSelected: Bool

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 2) {
      SwiftUI.Text(entry.title)
        .font(.callout.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(.primary)
        .lineLimit(1)
      SwiftUI.Text(entry.blurb)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background {
      SwiftUI.RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? SwiftUI.Color.accentColor.opacity(0.14) : SwiftUI.Color.clear)
    }
    .contentShape(SwiftUI.Rectangle())
  }
}

private struct LayoutComparisonDetail: SwiftUI::View {
  let entry: NativeLayoutEntry

  @SwiftUI::State private var codeSectionHeight: CGFloat = Self.defaultCodeSectionHeight

  private static let defaultCodeSectionHeight: CGFloat = 260
  private static let minimumCodeSectionHeight: CGFloat = 160
  private static let minimumPreviewHeight: CGFloat = 220

  init(entry: NativeLayoutEntry) {
    self.entry = entry
  }

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 0) {
      SwiftUI.VStack(alignment: .leading, spacing: 4) {
        SwiftUI.Text(entry.title)
          .font(.title2.weight(.semibold))
        SwiftUI.Text(entry.blurb)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding()

      SwiftUI.Divider()

      SwiftUI.GeometryReader { proxy in
        let maximumCodeSectionHeight = Self.maximumCodeSectionHeight(in: proxy.size)

        SwiftUI.HStack(alignment: .top, spacing: 2) {
          Rectangle().fill(.clear).overlay(alignment: .topLeading) {
            LayoutComparisonPane(
              title: "SwiftUI",
              source: SwiftUILayouts.LayoutSourceSnippets.byID[entry.id],
              codeSectionHeight: codeSectionHeightBinding(maximum: maximumCodeSectionHeight),
              minimumCodeSectionHeight: Self.minimumCodeSectionHeight,
              maximumCodeSectionHeight: maximumCodeSectionHeight
            ) {
              entry.makeView()
                .border(.red, width: 4)
            }
          }
          Rectangle().fill(.clear).overlay(alignment: .topLeading) {
            LayoutComparisonPane(
              title: "SwiftTUI",
              source: Layouts.LayoutSourceSnippets.byID[entry.id],
              codeSectionHeight: codeSectionHeightBinding(maximum: maximumCodeSectionHeight),
              minimumCodeSectionHeight: Self.minimumCodeSectionHeight,
              maximumCodeSectionHeight: maximumCodeSectionHeight
            ) {
              EmbeddedTUILayoutSurface(entryID: entry.id)
                .border(.red, width: 4)
            }
          }
        }
      }
    }
    .id(entry.id)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private static func maximumCodeSectionHeight(in size: CGSize) -> CGFloat {
    max(
      minimumCodeSectionHeight,
      size.height - minimumPreviewHeight
    )
  }

  private func codeSectionHeightBinding(maximum: CGFloat) -> SwiftUI.Binding<CGFloat> {
    SwiftUI.Binding(
      get: {
        clampedCodeSectionHeight(codeSectionHeight, maximum: maximum)
      },
      set: { newValue in
        codeSectionHeight = clampedCodeSectionHeight(newValue, maximum: maximum)
      }
    )
  }

  private func clampedCodeSectionHeight(_ value: CGFloat, maximum: CGFloat) -> CGFloat {
    min(
      max(value, Self.minimumCodeSectionHeight),
      maximum
    )
  }
}

private struct LayoutComparisonPane<Content: SwiftUI::View>: SwiftUI::View {
  let title: String
  let source: String?
  @SwiftUI::Binding var codeSectionHeight: CGFloat
  let minimumCodeSectionHeight: CGFloat
  let maximumCodeSectionHeight: CGFloat
  @SwiftUI::ViewBuilder var content: () -> Content

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 0) {
      SwiftUI.Text(title)
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)

      SwiftUI.Divider()

      SwiftUI.VStack(alignment: .leading, spacing: 0) {
        content()
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .layoutPriority(1)
          .clipped()

        CodeSectionResizeHandle(
          codeSectionHeight: $codeSectionHeight,
          minimumHeight: minimumCodeSectionHeight,
          maximumHeight: maximumCodeSectionHeight
        )

        LayoutSourceCodeView(source: source)
          .frame(height: codeSectionHeight)
      }
    }
  }
}

private struct LayoutSourceCodeView: SwiftUI::View {
  private let sourceText: String

  @SwiftUI::State private var highlightedSource: AttributedString

  init(source: String?) {
    let sourceText = source ?? "Source unavailable"
    self.sourceText = sourceText
    _highlightedSource = SwiftUI.State(initialValue: CodeHighlighter.highlight(sourceText))
  }

  var body: some SwiftUI::View {
    SwiftUI.ScrollView([.vertical, .horizontal]) {
      SwiftUI.Text(highlightedSource)
        .textSelection(.enabled)
        .padding(12)
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(CodeHighlighter.backgroundColor)
    .onChange(of: sourceText) { _, newValue in
      highlightedSource = CodeHighlighter.highlight(newValue)
    }
  }
}

private struct CodeSectionResizeHandle: SwiftUI::View {
  @SwiftUI::Binding var codeSectionHeight: CGFloat
  let minimumHeight: CGFloat
  let maximumHeight: CGFloat

  @SwiftUI::State private var dragStartHeight: CGFloat?
  @SwiftUI::State private var isHovering = false

  init(
    codeSectionHeight: SwiftUI.Binding<CGFloat>,
    minimumHeight: CGFloat,
    maximumHeight: CGFloat
  ) {
    _codeSectionHeight = codeSectionHeight
    self.minimumHeight = minimumHeight
    self.maximumHeight = maximumHeight
  }

  var body: some SwiftUI::View {
    SwiftUI.ZStack {
      SwiftUI.Divider()
      SwiftUI.Rectangle()
        .fill(isHovering ? SwiftUI.Color.accentColor.opacity(0.45) : SwiftUI.Color.clear)
        .frame(height: 6)
    }
    .frame(height: 8)
    .contentShape(SwiftUI.Rectangle())
    .onHover { hovering in
      isHovering = hovering
    }
    .gesture(
      SwiftUI.DragGesture(minimumDistance: 0)
        .onChanged { value in
          let startHeight = dragStartHeight ?? codeSectionHeight
          dragStartHeight = startHeight
          codeSectionHeight = clamped(startHeight - value.translation.height)
        }
        .onEnded { _ in
          dragStartHeight = nil
        }
    )
  }

  private func clamped(_ value: CGFloat) -> CGFloat {
    min(
      max(value, minimumHeight),
      maximumHeight
    )
  }
}

private enum CodeHighlighter {
  static var backgroundColor: SwiftUI.Color {
    SwiftUI.Color(red: 0.163, green: 0.163, blue: 0.182)
  }

  static func highlight(_ source: String) -> AttributedString {
    let theme = Splash.Theme.wwdc18(withFont: Splash.Font(size: 12))
    let highlighter = Splash.SyntaxHighlighter(
      format: Splash.AttributedStringOutputFormat(theme: theme)
    )
    return AttributedString(highlighter.highlight(source))
  }
}

@MainActor
private struct EmbeddedTUILayoutSurface: SwiftUI::View {
  let entryID: String

  @SwiftUI::State private var state: SwiftUIHostAppState<TUILayoutComparisonApp>?
  @SwiftUI::State private var launchError: String?

  init(entryID: String) {
    self.entryID = entryID
  }

  var body: some SwiftUI::View {
    SwiftUI.Group {
      if let state {
        SwiftUIHostAppView(state: state)
      } else if let launchError {
        SwiftUI.ContentUnavailableView {
          SwiftUI.Label("SwiftTUI Launch Failed", systemImage: "exclamationmark.triangle")
        } description: {
          SwiftUI.Text(launchError)
        }
      } else {
        SwiftUI.ProgressView()
      }
    }
    .task(id: entryID) {
      rebuildState()
    }
    .onDisappear {
      state?.stop()
    }
  }

  private func rebuildState() {
    state?.stop()

    do {
      state = try SwiftUIHostAppState(
        app: TUILayoutComparisonApp(entryID: entryID),
        style: SwiftUIHostTerminalStyle(
          fontSize: 12,
          cursorBlink: false
        )
      )
      launchError = nil
    } catch {
      state = nil
      launchError = String(describing: error)
    }
  }
}
