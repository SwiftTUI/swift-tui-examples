import SwiftTUI

extension CSVThemeColor {
  var swiftTUIColor: Color { try! Color(hex: hex) }
}
