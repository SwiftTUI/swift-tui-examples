import Sextant
import Testing

struct MillerLayoutTests {
  @Test("two columns reserve the preview minimum at the split breakpoint")
  func twoColumnWidthAllocation() {
    #expect(MillerLayout.columnWidths(totalWidth: 63, columnCount: 2) == [23, 40])
  }

  @Test("three columns honor both browser and preview minima at the wide breakpoint")
  func threeColumnWidthAllocation() {
    #expect(MillerLayout.columnWidths(totalWidth: 86, columnCount: 3) == [23, 23, 40])
    #expect(MillerLayout.columnWidths(totalWidth: 100, columnCount: 3) == [30, 30, 40])
  }

  @Test("narrow terminals split columns evenly before assigning the remainder")
  func narrowWidthAllocation() {
    #expect(MillerLayout.columnWidths(totalWidth: 61, columnCount: 3) == [20, 20, 21])
  }

  @Test("empty column sets allocate no widths")
  func emptyColumnAllocation() {
    #expect(MillerLayout.columnWidths(totalWidth: 100, columnCount: 0).isEmpty)
  }
}
