import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct GalleryMetadataTests {
  @Test("Gallery descriptors define tab order and palette names")
  func descriptorsDefineTabOrderAndPaletteNames() {
    let descriptors = GalleryView.tabDescriptors

    #expect(
      descriptors.map(\.title) == [
        "Counter",
        "Life",
        "Todo",
        "Forms & Containers",
        "Text Input",
        "Scroll Control",
        "Calculator",
        "Borders & Shapes",
        "Presentation Lab",
        "Navigation & Collections",
        "Images",
        "Animations",
        "File Drop",
        "Popovers",
        "Pointer Lab",
        "Focus Context",
        "Physics",
        "Progress",
      ]
    )
    #expect(Set(descriptors.map(\.value)).count == descriptors.count)
    #expect(descriptors.allSatisfy { !$0.coverageTags.isEmpty })
  }

  @Test("Every gallery alias resolves through descriptor metadata")
  func aliasesResolveThroughDescriptorMetadata() {
    for descriptor in GalleryView.tabDescriptors {
      for alias in descriptor.aliases {
        #expect(GalleryView.GalleryTab(environmentName: alias) == descriptor.value)
      }
    }
  }
}
