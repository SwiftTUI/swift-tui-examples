import SwiftTUIRuntime

public struct GalleryView: View {
  @State private var selection: GalleryTab
  @State private var showPalette: Bool = false
  // Owned here, above the TabView: the Life model is a class, which the
  // dormant-tab archive cannot carry, so the game would reset on every return
  // to its tab if the tab owned it. See `LifeTab`.
  @State private var lifeModel = LifeModel()

  // The pages the Animations and Styles tabs open on. Held as plain values:
  // each tab owns the live selection as its own @State.
  private let initialAnimationsPage: AnimationsPage
  private let initialStylesPage: StylesPage

  public init(
    initialTab: GalleryTab? = nil,
    initialAnimationsPage: AnimationsPage? = nil,
    initialStylesPage: StylesPage? = nil
  ) {
    _selection = State(initialValue: initialTab ?? .logo)
    self.initialAnimationsPage = initialAnimationsPage ?? .basics
    self.initialStylesPage = initialStylesPage ?? .controls
  }

  public var body: some View {
    // The shell's root chain below is ~25 modifier layers deep (one per
    // palette command), and the resolver copies the wrapped value once per
    // layer. Keeping the whole tab tuple inside `GalleryShellContent` (a
    // value a few words wide) instead of directly under the chain is what
    // keeps that resolve inside the 8 MB main-thread stack: the tuple alone
    // is ~14 KB, and the nineteenth tab tipped the Presentation Lab render
    // over the limit when the tuple sat under the chain.
    GalleryShellContent(
      selection: $selection,
      lifeModel: lifeModel,
      initialAnimationsPage: initialAnimationsPage,
      initialStylesPage: initialStylesPage
    )
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
    .galleryTabPaletteCommand(.styles, selection: $selection)
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
    .galleryTabPaletteCommand(.pointerLab, selection: $selection)
    .galleryTabPaletteCommand(.focusContext, selection: $selection)
    .galleryTabPaletteCommand(.taskProgress, selection: $selection)
    .toolbar().toolbarStyle(.defaultBottom)
    .paletteSheet("Command palette", isPresented: $showPalette)
  }
}

/// The tab strip and every tab's content, kept one struct below the shell's
/// root modifier chain so the chain copies this small value rather than the
/// tab tuple (see `GalleryView.body`).
private struct GalleryShellContent: View {
  @Binding var selection: GalleryView.GalleryTab
  let lifeModel: LifeModel
  let initialAnimationsPage: AnimationsPage
  let initialStylesPage: StylesPage

  var body: some View {
    TabView(selection: $selection) {
      Tab(GalleryView.descriptor(for: .logo).title, value: GalleryView.GalleryTab.logo) {
        LogoTab()
      }
      Tab(GalleryView.descriptor(for: .counter).title, value: GalleryView.GalleryTab.counter) {
        CounterTab()
      }
      Tab(GalleryView.descriptor(for: .styles).title, value: GalleryView.GalleryTab.styles) {
        StylesTabHost(initialPage: initialStylesPage)
      }
      Tab(GalleryView.descriptor(for: .life).title, value: GalleryView.GalleryTab.life) {
        LifeTab(model: lifeModel)
      }
      Tab(GalleryView.descriptor(for: .todo).title, value: GalleryView.GalleryTab.todo) {
        TodoTab()
      }
      Tab(GalleryView.descriptor(for: .formsAndContainers).title, value: GalleryView.GalleryTab.formsAndContainers) {
        FormsAndContainersTab()
      }
      Tab(GalleryView.descriptor(for: .textInput).title, value: GalleryView.GalleryTab.textInput) {
        TextInputTab()
      }
      Tab(GalleryView.descriptor(for: .scrollControl).title, value: GalleryView.GalleryTab.scrollControl) {
        ScrollControlTab()
      }
      Tab(GalleryView.descriptor(for: .calculator).title, value: GalleryView.GalleryTab.calculator) {
        CalculatorTab()
      }
      Tab(GalleryView.descriptor(for: .bordersAndShapes).title, value: GalleryView.GalleryTab.bordersAndShapes) {
        BordersAndShapesTab()
      }
      Tab(GalleryView.descriptor(for: .presentationLab).title, value: GalleryView.GalleryTab.presentationLab) {
        PresentationLabTab()
      }
      Tab(
        GalleryView.descriptor(for: .navigationCollections).title, value: GalleryView.GalleryTab.navigationCollections
      ) {
        NavigationCollectionsTab()
      }
      Tab(GalleryView.descriptor(for: .images).title, value: GalleryView.GalleryTab.images) {
        ImagesTab()
      }
      Tab(GalleryView.descriptor(for: .animations).title, value: GalleryView.GalleryTab.animations) {
        AnimationsTab(initialPage: initialAnimationsPage)
      }
      Tab(GalleryView.descriptor(for: .fileDrop).title, value: GalleryView.GalleryTab.fileDrop) {
        FileDropTab()
      }
      Tab(GalleryView.descriptor(for: .pointerLab).title, value: GalleryView.GalleryTab.pointerLab) {
        PointerLabTab()
      }
      Tab(GalleryView.descriptor(for: .focusContext).title, value: GalleryView.GalleryTab.focusContext) {
        FocusContextTab()
      }
      Tab(GalleryView.descriptor(for: .taskProgress).title, value: GalleryView.GalleryTab.taskProgress) {
        TaskProgressTab()
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

extension GalleryView {
  public enum GalleryTab: Hashable, CaseIterable, Sendable {
    case logo
    case life
    case counter
    case styles
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
    case pointerLab
    case focusContext
    case taskProgress

    /// The stable command-line key for this tab. One key per case.
    public var key: String {
      GalleryView.descriptor(for: self).key
    }

    /// Resolves a tab from its command-line key, or `nil` when unknown.
    public init?(key: String) {
      if key == "popovers" {
        self = .presentationLab
        return
      }
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
      case .styles:
        StylesTabHost()
      case .life:
        // Descriptor content is a standalone snapshot of the tab (no owning
        // gallery above it), so it brings its own model.
        LifeTab(model: LifeModel())
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
      value: .styles,
      title: "Styles",
      key: "styles",
      coverageTags: [
        "style-protocols", "button-style", "toggle-style", "text-field-style", "picker-style",
        "link-style", "label-style", "slider-style", "stepper-style", "progress-view-style",
        "spinner-style", "text-editor-style", "group-box-style", "labeled-content-style",
        "disclosure-group-style", "control-group-style", "menu-style", "list-style",
        "table-style", "outline-style", "scroll-view-style", "tab-view-style", "toolbar-style",
        "sheet-style", "prompt-style", "popover-style", "full-screen-cover-style",
        "toast-style", "palette-style", "style-scoping",
      ]
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
      coverageTags: [
        "borders", "shapes", "blend-modes", "canvas", "mesh-gradient", "clipboard",
      ]
    ),
    .init(
      value: .presentationLab,
      title: "Presentation Lab",
      key: "presentation-lab",
      coverageTags: [
        "alert", "confirmation-dialog", "sheet", "toast", "popover", "item-popover",
        "popover-tip", "palette-sheet",
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
      coverageTags: [
        "with-animation", "transitions", "phase-animator", "matched-geometry",
        "keyframe-animator", "transactions",
      ]
    ),
    .init(
      value: .fileDrop,
      title: "File Drop",
      key: "file-drop",
      coverageTags: ["file-drop"]
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

extension ActionScope where Self: View & Sendable {
  @MainActor
  fileprivate func galleryTabPaletteCommand(
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
