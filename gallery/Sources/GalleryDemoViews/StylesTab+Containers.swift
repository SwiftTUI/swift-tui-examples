import SwiftTUIRuntime

/// A node for the outline section. The identity is the title, which is
/// unique within the small fixture tree.
struct StyleOutlineNode: Identifiable, Sendable {
  let id: String
  let title: String
  var children: [StyleOutlineNode]?

  init(_ title: String, children: [StyleOutlineNode]? = nil) {
    id = title
    self.title = title
    self.children = children
  }
}

/// The Containers page: the families that arrange other views (sections 12
/// to 22). Collections show the presentation-value contract (a style returns
/// data, the primitive keeps virtualization and selection); the menu, group,
/// and tab sections show the body-producing contract with retained content.
struct ContainersPage: View {
  @Binding var disclosureOpen: Bool
  @Binding var listSelection: String
  @Binding var tableSelection: String
  @Binding var nestedTab: Int
  @Binding var menuPicks: Int

  var body: some View {
    stylePageScroll {
      groupingSections
      Divider()
      menuAndCollectionSections
      Divider()
      scrollTabAndToolbarSections
    }
  }

  @ViewBuilder
  private var groupingSections: some View {
    groupBoxSection
    Divider()
    labeledContentSection
    Divider()
    disclosureSection
    Divider()
    controlGroupSection
  }

  @ViewBuilder
  private var menuAndCollectionSections: some View {
    menuSection
    Divider()
    listSection
    Divider()
    tableSection
    Divider()
    outlineSection
  }

  @ViewBuilder
  private var scrollTabAndToolbarSections: some View {
    scrollViewSection
    Divider()
    tabViewSection
    Divider()
    toolbarSection
  }

  // MARK: - 12. GroupBoxStyle

  private var groupBoxSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(12, "GroupBoxStyle")
      styleBuiltinsLine([".automatic", ".bordered", ".plain"])
      HStack(alignment: .top, spacing: 3) {
        GroupBox("Bordered") { Text("rounded chrome") }
        GroupBox("Plain") { Text("no chrome") }
          .groupBoxStyle(.plain)
      }
      styleCustomLine("TitledGroupBoxStyle")
      GroupBox("Titled") { Text("a rule instead of a border") }
        .groupBoxStyle(TitledGroupBoxStyle())
    }
  }

  // MARK: - 13. LabeledContentStyle

  private var labeledContentSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(13, "LabeledContentStyle")
      styleBuiltinsLine([".automatic", ".stacked"])
      LabeledContent("Automatic", value: "one line")
        .frame(width: 30, alignment: .leading)
      LabeledContent("Stacked", value: "content below")
        .labeledContentStyle(.stacked)
      styleCustomLine("LeaderLabeledContentStyle")
      LabeledContent("Leader", value: "dotted")
        .labeledContentStyle(LeaderLabeledContentStyle())
    }
  }

  // MARK: - 14. DisclosureGroupStyle

  private var disclosureSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(14, "DisclosureGroupStyle")
      styleBuiltinsLine([".automatic", ".compact"])
      HStack(alignment: .top, spacing: 3) {
        DisclosureGroup("Automatic", isExpanded: $disclosureOpen) { Text("details") }
        DisclosureGroup("Compact", isExpanded: $disclosureOpen) { Text("details") }
          .disclosureGroupStyle(.compact)
      }
      .focusSection()
      styleCustomLine("ArrowDisclosureGroupStyle")
      DisclosureGroup("Arrow", isExpanded: $disclosureOpen) { Text("details") }
        .disclosureGroupStyle(ArrowDisclosureGroupStyle())
      Text("state: isExpanded=\(disclosureOpen)").foregroundStyle(.separator)
    }
  }

  // MARK: - 15. ControlGroupStyle

  private var controlGroupSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(15, "ControlGroupStyle")
      styleBuiltinsLine([".automatic", ".horizontal", ".vertical", ".compactMenu"])
      HStack(alignment: .top, spacing: 3) {
        ControlGroup("Horizontal") { groupButtons }
        ControlGroup("Vertical") { groupButtons }
          .controlGroupStyle(.vertical)
        ControlGroup("Compact") { groupButtons }
          .controlGroupStyle(.compactMenu)
      }
      .focusSection()
      styleCustomLine("BannerControlGroupStyle")
      ControlGroup("Banner") { groupButtons }
        .controlGroupStyle(BannerControlGroupStyle())
      styleNoteLine("switching a group's style keeps its buttons' identity and state")
    }
  }

  @ViewBuilder
  private var groupButtons: some View {
    Button("Cut") { menuPicks += 1 }
    Button("Copy") { menuPicks += 1 }
  }

  // MARK: - 16. MenuStyle

  private var menuSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(16, "MenuStyle")
      styleBuiltinsLine([".automatic", ".button", ".borderlessButton", ".inline"])
      HStack(alignment: .top, spacing: 3) {
        Menu("Button") { menuItems }
          .menuStyle(.button)
        Menu("Borderless") { menuItems }
          .menuStyle(.borderlessButton)
        Menu("Inline") { menuItems }
          .menuStyle(.inline)
      }
      .focusSection()
      styleCustomLine("BracketMenuStyle")
      Menu("Bracket") { menuItems }
        .menuStyle(BracketMenuStyle())
      Text("state: picks=\(menuPicks)").foregroundStyle(.separator)
    }
  }

  @ViewBuilder
  private var menuItems: some View {
    Button("Duplicate") { menuPicks += 1 }
    Button("Archive") { menuPicks += 1 }
  }

  // MARK: - 17. ListStyle

  private var listSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(17, "ListStyle")
      styleBuiltinsLine([".automatic", ".plain", ".insetGrouped"])
      HStack(alignment: .top, spacing: 3) {
        listSample
          .listStyle(.automatic)
        listSample
          .listStyle(.plain)
        listSample
          .listStyle(.insetGrouped)
      }
      styleCustomLine("RuledListStyle")
      listSample
        .listStyle(RuledListStyle())
      Text("state: selection=\(listSelection)").foregroundStyle(.separator)
    }
  }

  private var listSample: some View {
    List(selection: $listSelection) {
      Text("Alpha").tag("alpha")
      Text("Beta").tag("beta")
      Text("Gamma").tag("gamma")
    }
    .frame(width: 18, height: 5)
  }

  // MARK: - 18. TableStyle

  private var tableSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(18, "TableStyle")
      styleBuiltinsLine([".automatic", ".inset", ".bordered"])
      HStack(alignment: .top, spacing: 3) {
        tableSample
          .tableStyle(.inset)
        tableSample
          .tableStyle(.bordered)
      }
      styleCustomLine("HeavyTableStyle")
      tableSample
        .tableStyle(HeavyTableStyle())
      Text("state: row=\(tableSelection)").foregroundStyle(.separator)
    }
  }

  private var tableSample: some View {
    Table(
      selection: $tableSelection,
      columns: [
        TableColumn("State", width: 10),
        TableColumn("Count", width: 6, alignment: .trailing),
      ]
    ) {
      TableRow {
        Text("Queued")
        Text("3")
      }
      .tag("queued")
      TableRow {
        Text("Done")
        Text("8")
      }
      .tag("done")
    }
    .frame(width: 22, height: 6)
  }

  // MARK: - 19. OutlineStyle

  private var outlineSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(19, "OutlineStyle")
      styleBuiltinsLine([".automatic", ".rounded", ".plain"])
      HStack(alignment: .top, spacing: 3) {
        outlineSample
          .outlineStyle(.rounded)
        outlineSample
          .outlineStyle(.plain)
      }
      styleCustomLine("DottedOutlineStyle")
      outlineSample
        .outlineStyle(DottedOutlineStyle())
    }
  }

  private var outlineSample: some View {
    OutlineGroup(Self.outlineNodes, children: \.children) { node in
      Text(node.title)
    }
    .frame(width: 24, height: 6, alignment: .topLeading)
  }

  static let outlineNodes: [StyleOutlineNode] = [
    .init(
      "Style families",
      children: [
        .init("Built-ins"),
        .init(
          "Custom",
          children: [
            .init("Body-producing"),
            .init("Presentation-value"),
          ]
        ),
      ]
    )
  ]

  // MARK: - 20. ScrollViewStyle

  private var scrollViewSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(20, "ScrollViewStyle")
      styleBuiltinsLine([".automatic", ".minimal"])
      HStack(alignment: .top, spacing: 3) {
        scrollSample("automatic")
        scrollSample("minimal")
          .scrollViewStyle(.minimal)
      }
      styleCustomLine("HeavyScrollViewStyle")
      scrollSample("heavy")
        .scrollViewStyle(HeavyScrollViewStyle())
      styleNoteLine("indicator visibility still follows .scrollIndicators(...); the style paints them")
    }
  }

  private func scrollSample(_ name: String) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<12, id: \.self) { line in
          Text("\(name) line \(line + 1)")
        }
      }
    }
    .frame(width: 24, height: 4)
    .border(set: .single)
  }

  // MARK: - 21. TabViewStyle

  private var tabViewSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(21, "TabViewStyle")
      styleBuiltinsLine([".automatic", ".underline", ".literalTabs", ".powerline"])
      HStack(alignment: .top, spacing: 3) {
        nestedTabs
          .tabViewStyle(.underline)
        nestedTabs
          .tabViewStyle(.literalTabs)
        nestedTabs
          .tabViewStyle(.powerline)
      }
      styleCustomLine("PillTabViewStyle")
      nestedTabs
        .tabViewStyle(PillTabViewStyle())
      Text("state: nested tab=\(nestedTab)").foregroundStyle(.separator)
    }
  }

  private var nestedTabs: some View {
    TabView(selection: $nestedTab) {
      Tab("Alpha", value: 0) { Text("alpha content") }
      Tab("Beta", value: 1) { Text("beta content") }
      Tab("Gamma", value: 2) { Text("gamma content") }
    }
    .frame(width: 30, height: 5, alignment: .topLeading)
  }

  // MARK: - 22. ToolbarStyle

  private var toolbarSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      styleSectionTitle(22, "ToolbarStyle")
      styleBuiltinsLine([".defaultTop", ".defaultBottom"])
      styleCustomLine("none here; a ToolbarStyle supplies the Layout that arranges items and a placement")
      styleNoteLine("the gallery shell declares one .toolbar().toolbarStyle(.defaultBottom): the strip at the bottom of every tab")
    }
  }
}
