import SwiftTUIRuntime

public struct GalleryView: View {
  @State private var selection: GalleryTab
  @State private var showPalette: Bool = false

  public init(initialTab: GalleryTab? = nil) {
    _selection = State(initialValue: initialTab ?? .logo)
  }

  public var body: some View {
    TabView(selection: $selection) {
      Tab(Self.descriptor(for: .logo).title, value: GalleryTab.logo) {
        LogoTab()
      }
      Tab(Self.descriptor(for: .counter).title, value: GalleryTab.counter) {
        CounterTab()
      }
      Tab(Self.descriptor(for: .life).title, value: GalleryTab.life) {
        LifeTab()
      }
      Tab(Self.descriptor(for: .todo).title, value: GalleryTab.todo) {
        TodoTab()
      }
      Tab(Self.descriptor(for: .formsAndContainers).title, value: GalleryTab.formsAndContainers) {
        FormsAndContainersTab()
      }
      Tab(Self.descriptor(for: .textInput).title, value: GalleryTab.textInput) {
        TextInputTab()
      }
      Tab(Self.descriptor(for: .scrollControl).title, value: GalleryTab.scrollControl) {
        ScrollControlTab()
      }
      Tab(Self.descriptor(for: .calculator).title, value: GalleryTab.calculator) {
        CalculatorTab()
      }
      Tab(Self.descriptor(for: .bordersAndShapes).title, value: GalleryTab.bordersAndShapes) {
        BordersAndShapesTab()
      }
      Tab(Self.descriptor(for: .presentationLab).title, value: GalleryTab.presentationLab) {
        PresentationLabTab()
      }
      Tab(Self.descriptor(for: .navigationCollections).title, value: GalleryTab.navigationCollections) {
        NavigationCollectionsTab()
      }
      Tab(Self.descriptor(for: .images).title, value: GalleryTab.images) {
        ImagesTab()
      }
      Tab(Self.descriptor(for: .animations).title, value: GalleryTab.animations) {
        AnimationsTab()
      }
      Tab(Self.descriptor(for: .fileDrop).title, value: GalleryTab.fileDrop) {
        FileDropTab()
      }
      Tab(Self.descriptor(for: .popovers).title, value: GalleryTab.popovers) {
        PopoverTab()
      }
      Tab(Self.descriptor(for: .pointerLab).title, value: GalleryTab.pointerLab) {
        PointerLabTab()
      }
      Tab(Self.descriptor(for: .focusContext).title, value: GalleryTab.focusContext) {
        FocusContextTab()
      }
      Tab(Self.descriptor(for: .taskProgress).title, value: GalleryTab.taskProgress) {
        TaskProgressTab()
      }
    }
    .tabViewStyle(.literalTabs)
    .toolbarItem(
      .init(
        title: "⌃K Palette",
        action: { showPalette = true }
      )
    )
    .panel(id: "gallery")
    .keyCommand(
      "Command palette",
      key: .character("k"),
      modifiers: .ctrl,
      action: { showPalette = true }
    )
    .galleryTabPaletteCommand(.logo, selection: $selection)
    .galleryTabPaletteCommand(.counter, selection: $selection)
    .galleryTabPaletteCommand(.life, selection: $selection)
    .galleryTabPaletteCommand(.todo, selection: $selection)
    .galleryTabPaletteCommand(.formsAndContainers, selection: $selection)
    .galleryTabPaletteCommand(.textInput, selection: $selection)
    .galleryTabPaletteCommand(.scrollControl, selection: $selection)
    .galleryTabPaletteCommand(.calculator, selection: $selection)
    .galleryTabPaletteCommand(.bordersAndShapes, selection: $selection)
    .galleryTabPaletteCommand(.presentationLab, selection: $selection)
    .galleryTabPaletteCommand(.navigationCollections, selection: $selection)
    .galleryTabPaletteCommand(.images, selection: $selection)
    .galleryTabPaletteCommand(.animations, selection: $selection)
    .galleryTabPaletteCommand(.fileDrop, selection: $selection)
    .galleryTabPaletteCommand(.popovers, selection: $selection)
    .galleryTabPaletteCommand(.pointerLab, selection: $selection)
    .galleryTabPaletteCommand(.focusContext, selection: $selection)
    .galleryTabPaletteCommand(.taskProgress, selection: $selection)
    .toolbar(style: .defaultBottom)
    .paletteSheet("Command palette", isPresented: $showPalette) { commands in
      CommandPaletteList(
        commands: commands,
        dismiss: { showPalette = false }
      )
    }
  }
}

extension GalleryView {
  public enum GalleryTab: Hashable, CaseIterable, Sendable {
    case logo
    case life
    case counter
    case todo
    case formsAndContainers
    case textInput
    case scrollControl
    case calculator
    case bordersAndShapes
    case presentationLab
    case navigationCollections
    case images
    case animations
    case fileDrop
    case popovers
    case pointerLab
    case focusContext
    case taskProgress

    /// The stable command-line key for this tab. One key per case.
    public var key: String {
      GalleryView.descriptor(for: self).key
    }

    /// Resolves a tab from its command-line key, or `nil` when unknown.
    public init?(key: String) {
      guard let descriptor = GalleryView.tabDescriptors.first(where: { $0.key == key })
      else {
        return nil
      }
      self = descriptor.value
    }
  }

  struct GalleryTabDescriptor: Identifiable, Sendable {
    let value: GalleryTab
    let title: String
    let key: String
    let coverageTags: [String]

    var id: GalleryTab { value }

    @MainActor @ViewBuilder
    var content: some View {
      switch value {
      case .logo:
        LogoTab()
      case .counter:
        CounterTab()
      case .life:
        LifeTab()
      case .todo:
        TodoTab()
      case .formsAndContainers:
        FormsAndContainersTab()
      case .textInput:
        TextInputTab()
      case .scrollControl:
        ScrollControlTab()
      case .calculator:
        CalculatorTab()
      case .bordersAndShapes:
        BordersAndShapesTab()
      case .presentationLab:
        PresentationLabTab()
      case .navigationCollections:
        NavigationCollectionsTab()
      case .images:
        ImagesTab()
      case .animations:
        AnimationsTab()
      case .fileDrop:
        FileDropTab()
      case .popovers:
        PopoverTab()
      case .pointerLab:
        PointerLabTab()
      case .focusContext:
        FocusContextTab()
      case .taskProgress:
        TaskProgressTab()
      }
    }
  }

  nonisolated static let tabDescriptors: [GalleryTabDescriptor] = [
    .init(
      value: .logo,
      title: "Logo Breaker",
      key: "logo",
      coverageTags: ["canvas", "pixel-grid", "truecolor", "gestures", "physics"]
    ),
    .init(
      value: .counter,
      title: "Counter",
      key: "counter",
      coverageTags: ["state", "buttons"]
    ),
    .init(
      value: .life,
      title: "Life",
      key: "life",
      coverageTags: ["custom-rendering", "simulation"]
    ),
    .init(
      value: .todo,
      title: "Todo",
      key: "todo",
      coverageTags: ["lists", "editing", "selection"]
    ),
    .init(
      value: .formsAndContainers,
      title: "Forms & Containers",
      key: "forms-and-containers",
      coverageTags: [
        "group-box", "control-group", "disclosure-group", "link", "picker-style",
        "button-style", "text-field-style", "disabled", "accessibility",
      ]
    ),
    .init(
      value: .textInput,
      title: "Text Input",
      key: "text-input",
      coverageTags: ["text-field", "text-editor", "focus", "paste"]
    ),
    .init(
      value: .scrollControl,
      title: "Scroll Control",
      key: "scroll-control",
      coverageTags: ["scrolling", "scroll-position"]
    ),
    .init(
      value: .calculator,
      title: "Calculator",
      key: "calculator",
      coverageTags: ["click-targets", "compact-controls"]
    ),
    .init(
      value: .bordersAndShapes,
      title: "Borders & Shapes",
      key: "borders-and-shapes",
      coverageTags: ["borders", "shapes", "blend-modes", "canvas"]
    ),
    .init(
      value: .presentationLab,
      title: "Presentation Lab",
      key: "presentation-lab",
      coverageTags: [
        "alert", "confirmation-dialog", "sheet", "toast", "popover", "popover-tip",
        "palette-sheet",
      ]
    ),
    .init(
      value: .navigationCollections,
      title: "Navigation & Collections",
      key: "navigation-collections",
      coverageTags: [
        "navigation-stack", "navigation-destination", "outline-group", "lazy-stack",
        "list-selection", "table-selection",
      ]
    ),
    .init(
      value: .images,
      title: "Images",
      key: "images",
      coverageTags: ["image-attachments", "animated-gif"]
    ),
    .init(
      value: .animations,
      title: "Animations",
      key: "animations",
      coverageTags: ["with-animation", "transitions", "phase-animator"]
    ),
    .init(
      value: .fileDrop,
      title: "File Drop",
      key: "file-drop",
      coverageTags: ["file-drop"]
    ),
    .init(
      value: .popovers,
      title: "Popovers",
      key: "popovers",
      coverageTags: ["popover", "popover-tip", "palette-sheet"]
    ),
    .init(
      value: .pointerLab,
      title: "Pointer Lab",
      key: "pointer-lab",
      coverageTags: [
        "spatial-tap", "drag-gesture", "long-press", "content-shape",
        "coordinate-space",
      ]
    ),
    .init(
      value: .focusContext,
      title: "Focus Context",
      key: "focus-context",
      coverageTags: ["focused-value", "focused-binding", "toolbar"]
    ),
    .init(
      value: .taskProgress,
      title: "Progress",
      key: "task-progress",
      coverageTags: ["spinner", "timeline-view", "task-status"]
    ),
  ]

  nonisolated static func descriptor(for tab: GalleryTab) -> GalleryTabDescriptor {
    guard let descriptor = tabDescriptors.first(where: { $0.value == tab }) else {
      preconditionFailure("missing descriptor for \(tab)")
    }
    return descriptor
  }
}

private extension ActionScope where Self: View & Sendable {
  @MainActor
  func galleryTabPaletteCommand(
    _ tab: GalleryView.GalleryTab,
    selection: Binding<GalleryView.GalleryTab>
  ) -> some View & ActionScope & Sendable {
    let descriptor = GalleryView.descriptor(for: tab)
    return paletteCommand(
      name: descriptor.title,
      action: { selection.wrappedValue = tab }
    )
  }
}
