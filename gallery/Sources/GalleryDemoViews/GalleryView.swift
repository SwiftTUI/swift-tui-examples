import Foundation
import SwiftTUIRuntime

public struct GalleryView: View {
  public init() {}

  // The initial tab honors `GALLERY_INITIAL_TAB` (e.g. "images") so
  // verification scripts and screenshot harnesses can land on a
  // specific tab without driving the command palette.
  @State private var selection: GalleryTab = GalleryView.initialTabFromEnvironment()
  @State private var showPalette: Bool = false

  public var body: some View {
    TabView(selection: $selection) {
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
      Tab(Self.descriptor(for: .physics).title, value: GalleryTab.physics) {
        PhysicsTab()
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
    .galleryTabPaletteCommand(.physics, selection: $selection)
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
  enum GalleryTab: Hashable {
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
    case physics
    case taskProgress

    @MainActor
    init?(environmentName: String) {
      let normalized = environmentName.lowercased()
      guard let descriptor = GalleryView.tabDescriptors.first(where: {
        $0.aliases.contains(normalized)
      }) else {
        return nil
      }
      self = descriptor.value
    }
  }

  struct GalleryTabDescriptor: Identifiable, Sendable {
    let value: GalleryTab
    let title: String
    let aliases: [String]
    let coverageTags: [String]

    var id: GalleryTab { value }

    @MainActor @ViewBuilder
    var content: some View {
      switch value {
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
      case .physics:
        PhysicsTab()
      case .taskProgress:
        TaskProgressTab()
      }
    }
  }

  static let tabDescriptors: [GalleryTabDescriptor] = [
    .init(
      value: .counter,
      title: "Counter",
      aliases: ["counter"],
      coverageTags: ["state", "buttons"]
    ),
    .init(
      value: .life,
      title: "Life",
      aliases: ["life", "conway"],
      coverageTags: ["custom-rendering", "simulation"]
    ),
    .init(
      value: .todo,
      title: "Todo",
      aliases: ["todo"],
      coverageTags: ["lists", "editing", "selection"]
    ),
    .init(
      value: .formsAndContainers,
      title: "Forms & Containers",
      aliases: [
        "forms", "forms and containers", "forms-containers", "formsandcontainers", "containers",
      ],
      coverageTags: [
        "group-box", "control-group", "disclosure-group", "link", "picker-style",
        "button-style", "text-field-style", "disabled", "accessibility",
      ]
    ),
    .init(
      value: .textInput,
      title: "Text Input",
      aliases: ["text input", "text", "input", "inputs", "textinput", "text-input", "text-inputs"],
      coverageTags: ["text-field", "text-editor", "focus", "paste"]
    ),
    .init(
      value: .scrollControl,
      title: "Scroll Control",
      aliases: ["scroll control", "scroll", "scrollcontrol", "scroll-control", "scrolling"],
      coverageTags: ["scrolling", "scroll-position"]
    ),
    .init(
      value: .calculator,
      title: "Calculator",
      aliases: ["calculator", "calc"],
      coverageTags: ["click-targets", "compact-controls"]
    ),
    .init(
      value: .bordersAndShapes,
      title: "Borders & Shapes",
      aliases: ["borders & shapes", "borders", "bordersandshapes", "borders-and-shapes", "shapes"],
      coverageTags: ["borders", "shapes", "blend-modes", "canvas"]
    ),
    .init(
      value: .presentationLab,
      title: "Presentation Lab",
      aliases: ["presentation", "presentation lab", "presentation-lab", "presentations"],
      coverageTags: [
        "alert", "confirmation-dialog", "sheet", "toast", "popover", "popover-tip",
        "palette-sheet",
      ]
    ),
    .init(
      value: .navigationCollections,
      title: "Navigation & Collections",
      aliases: [
        "navigation", "collections", "navigation collections", "navigation-collections",
        "nav", "outline", "table",
      ],
      coverageTags: [
        "navigation-stack", "navigation-destination", "outline-group", "lazy-stack",
        "list-selection", "table-selection",
      ]
    ),
    .init(
      value: .images,
      title: "Images",
      aliases: ["images", "image", "animatedgif", "animated-gif", "gif", "animatedimage", "animated-image"],
      coverageTags: ["image-attachments", "animated-gif"]
    ),
    .init(
      value: .animations,
      title: "Animations",
      aliases: ["animations", "animation"],
      coverageTags: ["with-animation", "transitions", "phase-animator"]
    ),
    .init(
      value: .fileDrop,
      title: "File Drop",
      aliases: ["file drop", "filedrop", "file-drop", "files"],
      coverageTags: ["file-drop"]
    ),
    .init(
      value: .popovers,
      title: "Popovers",
      aliases: ["popover", "popovers", "tips"],
      coverageTags: ["popover", "popover-tip", "palette-sheet"]
    ),
    .init(
      value: .pointerLab,
      title: "Pointer Lab",
      aliases: ["pointer", "pointer lab", "pointer-lab", "gestures"],
      coverageTags: [
        "spatial-tap", "drag-gesture", "long-press", "content-shape",
        "coordinate-space",
      ]
    ),
    .init(
      value: .focusContext,
      title: "Focus Context",
      aliases: ["focus", "focus context", "focus-context", "focused-values"],
      coverageTags: ["focused-value", "focused-binding", "toolbar"]
    ),
    .init(
      value: .physics,
      title: "Physics",
      aliases: ["physics"],
      coverageTags: ["gestures", "fullscreen"]
    ),
    .init(
      value: .taskProgress,
      title: "Progress",
      aliases: ["progress", "taskprogress", "task-progress", "working", "todolist", "todo-list"],
      coverageTags: ["spinner", "timeline-view", "task-status"]
    ),
  ]

  static func descriptor(for tab: GalleryTab) -> GalleryTabDescriptor {
    tabDescriptors.first { $0.value == tab }!
  }

  fileprivate static func initialTabFromEnvironment() -> GalleryTab {
    guard let raw = ProcessInfo.processInfo.environment["GALLERY_INITIAL_TAB"],
      let tab = GalleryTab(environmentName: raw)
    else {
      return .counter
    }
    return tab
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
