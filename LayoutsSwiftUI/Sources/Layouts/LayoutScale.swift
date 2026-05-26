import SwiftUI

/// Native SwiftUI layout measurements use 10 points per SwiftTUI cell.
func cell(_ units: CGFloat) -> CGFloat {
  units * 10
}

func cell(_ units: Int) -> CGFloat {
  CGFloat(units * 10)
}

func cellCount(_ points: CGFloat) -> Int {
  Int((points / 10).rounded())
}

extension CGFloat {
  var cellWidth: CGFloat {
    self * 8
  }
}
extension Int {
  var cellWidth: Int {
    self * 8
  }
}

extension CGFloat {
  var cellHeight: CGFloat {
    self * 10
  }
}
extension Int {
  var cellHeight: Int {
    self * 10
  }
}
