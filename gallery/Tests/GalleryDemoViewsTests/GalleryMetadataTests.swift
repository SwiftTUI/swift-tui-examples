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
        "Logo",
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

  @Test("Each tab has one non-empty, unique command-line key")
  func eachTabHasOneUniqueKey() {
    let descriptors = GalleryView.tabDescriptors

    #expect(descriptors.allSatisfy { !$0.key.isEmpty })
    #expect(Set(descriptors.map(\.key)).count == descriptors.count)
  }

  @Test("Tab keys round-trip through GalleryTab")
  func tabKeysRoundTrip() {
    for descriptor in GalleryView.tabDescriptors {
      #expect(descriptor.value.key == descriptor.key)
      #expect(GalleryView.GalleryTab(key: descriptor.key) == descriptor.value)
    }
    #expect(GalleryView.GalleryTab(key: "not-a-tab") == nil)
  }
}
