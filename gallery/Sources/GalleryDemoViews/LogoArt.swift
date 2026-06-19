import SwiftTUIRuntime

struct LogoBrickCell: Equatable, Sendable {
  let id: Int
  let x: Int
  let y: Int
  let top: Color?
  let bottom: Color?
}

struct LogoBrick: Equatable, Sendable {
  let id: Int
  let x: Int
  let y: Int
  let width: Int
  let height: Int
  let cells: [LogoBrickCell]
}

/// The SwiftTUI mark as a 32×32 truecolor bitmap for ``LogoTab``.
///
/// Generated from the org-root `logo.svg` (a 16×16 pixel-art mark)
/// rasterized at its native grid and nearest-neighbor upscaled 2×, so
/// every source pixel maps to one palette entry with no interpolation.
/// `palette` holds the distinct opaque colors; `indices` is row-major
/// (`-1` = transparent, leaving the terminal background showing through).
enum LogoArt {
  static let width = 32
  static let height = 32
  static let sourceWidth = width / 2
  static let sourceHeight = height / 2
  static let cellWidth = width
  static let cellHeight = CanvasPixelGridMode.verticalHalfBlock.cellHeight(for: height)
  static let brickCells: [LogoBrickCell] = {
    var cells: [LogoBrickCell] = []
    for y in 0..<cellHeight {
      let topY = y * 2
      let bottomY = topY + 1
      for x in 0..<width {
        let top = pixel(x: x, y: topY)
        let bottom = pixel(x: x, y: bottomY)
        guard top != nil || bottom != nil else {
          continue
        }
        cells.append(
          LogoBrickCell(
            id: y * width + x,
            x: x,
            y: y,
            top: top,
            bottom: bottom
          )
        )
      }
    }
    return cells
  }()
  static let bricks: [LogoBrick] = {
    let cellsByID = Dictionary(uniqueKeysWithValues: brickCells.map { ($0.id, $0) })
    var bricks: [LogoBrick] = []
    for y in 0..<sourceHeight {
      for sourceX in 0..<sourceWidth {
        let x = sourceX * 2
        let cells = [
          cellsByID[y * width + x],
          cellsByID[y * width + x + 1],
        ].compactMap { $0 }
        guard !cells.isEmpty else {
          continue
        }
        bricks.append(
          LogoBrick(
            id: y * sourceWidth + sourceX,
            x: x,
            y: y,
            width: 2,
            height: 1,
            cells: cells
          )
        )
      }
    }
    return bricks
  }()
  private static let palette: [Color] = [
    Color(hexRGB: 0x04EDDE),  // 0
    Color(hexRGB: 0x02E9D5),  // 1
    Color(hexRGB: 0x01EAD4),  // 2
    Color(hexRGB: 0x01F8E7),  // 3
    Color(hexRGB: 0x01FFEC),  // 4
    Color(hexRGB: 0x02FFED),  // 5
    Color(hexRGB: 0x04FFEC),  // 6
    Color(hexRGB: 0x04FFF0),  // 7
    Color(hexRGB: 0x01E8D2),  // 8
    Color(hexRGB: 0x00E4C8),  // 9
    Color(hexRGB: 0x00E3C6),  // 10
    Color(hexRGB: 0x00F7DD),  // 11
    Color(hexRGB: 0x00FFE3),  // 12
    Color(hexRGB: 0x04DDD2),  // 13
    Color(hexRGB: 0x00CEBE),  // 14
    Color(hexRGB: 0x00CDBE),  // 15
    Color(hexRGB: 0x00CDBD),  // 16
    Color(hexRGB: 0x00CEBD),  // 17
    Color(hexRGB: 0x00D0BE),  // 18
    Color(hexRGB: 0x0095A2),  // 19
    Color(hexRGB: 0x00E3DA),  // 20
    Color(hexRGB: 0x00E4DD),  // 21
    Color(hexRGB: 0x00E4DB),  // 22
    Color(hexRGB: 0x04F4ED),  // 23
    Color(hexRGB: 0x01D1B9),  // 24
    Color(hexRGB: 0x00C6AA),  // 25
    Color(hexRGB: 0x05A092),  // 26
    Color(hexRGB: 0x008C88),  // 27
    Color(hexRGB: 0x004363),  // 28
    Color(hexRGB: 0x02CEA1),  // 29
    Color(hexRGB: 0x00C68F),  // 30
    Color(hexRGB: 0x02796E),  // 31
    Color(hexRGB: 0x00C58F),  // 32
    Color(hexRGB: 0x024959),  // 33
    Color(hexRGB: 0x001542),  // 34
    Color(hexRGB: 0x016B70),  // 35
    Color(hexRGB: 0x00E3AC),  // 36
    Color(hexRGB: 0x00E3AB),  // 37
    Color(hexRGB: 0x01E4B9),  // 38
    Color(hexRGB: 0x00CD9B),  // 39
    Color(hexRGB: 0x00C58C),  // 40
    Color(hexRGB: 0x00C68E),  // 41
    Color(hexRGB: 0x00BD8B),  // 42
    Color(hexRGB: 0x012247),  // 43
    Color(hexRGB: 0x00A57E),  // 44
    Color(hexRGB: 0x012B4B),  // 45
    Color(hexRGB: 0x00BC87),  // 46
    Color(hexRGB: 0x00324E),  // 47
    Color(hexRGB: 0x000039),  // 48
    Color(hexRGB: 0x00C497),  // 49
    Color(hexRGB: 0x00C9A4),  // 50
    Color(hexRGB: 0x00C8A5),  // 51
    Color(hexRGB: 0x00D5B4),  // 52
    Color(hexRGB: 0x00B884),  // 53
    Color(hexRGB: 0x00AA71),  // 54
    Color(hexRGB: 0x019E6D),  // 55
    Color(hexRGB: 0x00073B),  // 56
    Color(hexRGB: 0x006259),  // 57
    Color(hexRGB: 0x001540),  // 58
    Color(hexRGB: 0x00996B),  // 59
    Color(hexRGB: 0x00414E),  // 60
    Color(hexRGB: 0x024656),  // 61
    Color(hexRGB: 0x00CDA2),  // 62
    Color(hexRGB: 0x00B581),  // 63
    Color(hexRGB: 0x00AA72),  // 64
    Color(hexRGB: 0x018464),  // 65
    Color(hexRGB: 0x000139),  // 66
    Color(hexRGB: 0x00043A),  // 67
    Color(hexRGB: 0x00033A),  // 68
    Color(hexRGB: 0x006D5D),  // 69
    Color(hexRGB: 0x002746),  // 70
    Color(hexRGB: 0x00023A),  // 71
    Color(hexRGB: 0x00C378),  // 72
    Color(hexRGB: 0x00C67B),  // 73
    Color(hexRGB: 0x00CD8D),  // 74
    Color(hexRGB: 0x00B47F),  // 75
    Color(hexRGB: 0x00A771),  // 76
    Color(hexRGB: 0x017361),  // 77
    Color(hexRGB: 0x00AC71),  // 78
    Color(hexRGB: 0x00BA82),  // 79
    Color(hexRGB: 0x00B37E),  // 80
    Color(hexRGB: 0x00A071),  // 81
    Color(hexRGB: 0x007264),  // 82
    Color(hexRGB: 0x009371),  // 83
    Color(hexRGB: 0x009271),  // 84
    Color(hexRGB: 0x006C63),  // 85
    Color(hexRGB: 0x00063B),  // 86
    Color(hexRGB: 0x00AA73),  // 87
    Color(hexRGB: 0x00AA83),  // 88
    Color(hexRGB: 0x00A279),  // 89
    Color(hexRGB: 0x016764),  // 90
    Color(hexRGB: 0x001A43),  // 91
    Color(hexRGB: 0x004855),  // 92
    Color(hexRGB: 0x006962),  // 93
    Color(hexRGB: 0x006661),  // 94
    Color(hexRGB: 0x003E51),  // 95
    Color(hexRGB: 0x000A3D),  // 96
    Color(hexRGB: 0x008E71),  // 97
    Color(hexRGB: 0x00AB7D),  // 98
    Color(hexRGB: 0x019C7D),  // 99
    Color(hexRGB: 0x009071),  // 100
    Color(hexRGB: 0x007266),  // 101
    Color(hexRGB: 0x002648),  // 102
    Color(hexRGB: 0x009676),  // 103
    Color(hexRGB: 0x009A79),  // 104
    Color(hexRGB: 0x008D71),  // 105
    Color(hexRGB: 0x004755),  // 106
    Color(hexRGB: 0x008B70),  // 107
    Color(hexRGB: 0x001240),  // 108
    Color(hexRGB: 0x009674),  // 109
    Color(hexRGB: 0x008C71),  // 110
    Color(hexRGB: 0x008B71),  // 111
    Color(hexRGB: 0x008A71),  // 112
    Color(hexRGB: 0x00A581),  // 113
    Color(hexRGB: 0x007A71),  // 114
    Color(hexRGB: 0x007772),  // 115
    Color(hexRGB: 0x007672),  // 116
    Color(hexRGB: 0x007E75),  // 117
    Color(hexRGB: 0x008277),  // 118
    Color(hexRGB: 0x008478),  // 119
    Color(hexRGB: 0x007271),  // 120
    Color(hexRGB: 0x007171),  // 121
    Color(hexRGB: 0x007371),  // 122
  ]
  private static let indices: [Int] = [
    -1, -1, -1, -1, 0, 0, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 6, 6, 7, 7, -1, -1, -1, -1,
    -1, -1, -1, -1, 0, 0, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 6, 6, 7, 7, -1, -1, -1, -1,
    -1, -1, 8, 8, 9, 9, 10, 10, 9, 9, 10, 10, 9, 9, 9, 9, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 5, 5, -1, -1,
    -1, -1, 8, 8, 9, 9, 10, 10, 9, 9, 10, 10, 9, 9, 9, 9, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 5, 5, -1, -1,
    13, 13, 14, 14, 14, 14, 14, 14, 15, 15, 14, 14, 16, 16, 17, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 22, 21, 21, 21, 21, 23, 23,
    13, 13, 14, 14, 14, 14, 14, 14, 15, 15, 14, 14, 16, 16, 17, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 22, 21, 21, 21, 21, 23, 23,
    24, 24, 25, 25, 25, 25, 25, 25, 26, 26, 25, 25, 25, 25, 25, 25, 25, 25, 27, 27, 28, 28, 10, 10, 9, 9, 10, 10, 9, 9, 8, 8,
    24, 24, 25, 25, 25, 25, 25, 25, 26, 26, 25, 25, 25, 25, 25, 25, 25, 25, 27, 27, 28, 28, 10, 10, 9, 9, 10, 10, 9, 9, 8, 8,
    29, 29, 30, 30, 30, 30, 31, 31, 32, 32, 33, 33, 30, 30, 30, 30, 30, 30, 30, 30, 34, 34, 35, 35, 36, 36, 36, 36, 37, 37, 38, 38,
    29, 29, 30, 30, 30, 30, 31, 31, 32, 32, 33, 33, 30, 30, 30, 30, 30, 30, 30, 30, 34, 34, 35, 35, 36, 36, 36, 36, 37, 37, 38, 38,
    39, 39, 40, 40, 41, 41, 42, 42, 43, 43, 44, 44, 45, 45, 46, 46, 41, 41, 40, 40, 47, 47, 48, 48, 49, 49, 50, 50, 51, 51, 52, 52,
    39, 39, 40, 40, 41, 41, 42, 42, 43, 43, 44, 44, 45, 45, 46, 46, 41, 41, 40, 40, 47, 47, 48, 48, 49, 49, 50, 50, 51, 51, 52, 52,
    53, 53, 54, 54, 54, 54, 54, 54, 55, 55, 56, 56, 57, 57, 58, 58, 59, 59, 54, 54, 60, 60, 48, 48, 61, 61, 30, 30, 41, 41, 62, 62,
    53, 53, 54, 54, 54, 54, 54, 54, 55, 55, 56, 56, 57, 57, 58, 58, 59, 59, 54, 54, 60, 60, 48, 48, 61, 61, 30, 30, 41, 41, 62, 62,
    63, 63, 54, 54, 64, 64, 54, 54, 64, 64, 65, 65, 66, 66, 67, 67, 68, 68, 69, 69, 70, 70, 48, 48, 71, 71, 72, 72, 73, 73, 74, 74,
    63, 63, 54, 54, 64, 64, 54, 54, 64, 64, 65, 65, 66, 66, 67, 67, 68, 68, 69, 69, 70, 70, 48, 48, 71, 71, 72, 72, 73, 73, 74, 74,
    75, 75, 76, 76, 54, 54, 54, 54, 54, 54, 54, 54, 77, 77, 66, 66, 48, 48, 48, 48, 48, 48, 48, 48, 66, 66, 54, 54, 78, 78, 79, 79,
    75, 75, 76, 76, 54, 54, 54, 54, 54, 54, 54, 54, 77, 77, 66, 66, 48, 48, 48, 48, 48, 48, 48, 48, 66, 66, 54, 54, 78, 78, 79, 79,
    80, 80, 81, 81, 82, 82, 83, 83, 83, 83, 84, 84, 84, 84, 85, 85, 86, 86, 48, 48, 48, 48, 48, 48, 71, 71, 87, 87, 87, 87, 80, 80,
    80, 80, 81, 81, 82, 82, 83, 83, 83, 83, 84, 84, 84, 84, 85, 85, 86, 86, 48, 48, 48, 48, 48, 48, 71, 71, 87, 87, 87, 87, 80, 80,
    88, 88, 89, 89, 90, 90, 91, 91, 92, 92, 93, 93, 94, 94, 95, 95, 96, 96, 48, 48, 48, 48, 48, 48, 48, 48, 97, 97, 89, 89, 98, 98,
    88, 88, 89, 89, 90, 90, 91, 91, 92, 92, 93, 93, 94, 94, 95, 95, 96, 96, 48, 48, 48, 48, 48, 48, 48, 48, 97, 97, 89, 89, 98, 98,
    99, 99, 97, 97, 100, 100, 101, 101, 66, 66, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 102, 102, 100, 100, 103, 103,
    99, 99, 97, 97, 100, 100, 101, 101, 66, 66, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 102, 102, 100, 100, 103, 103,
    104, 104, 97, 97, 97, 97, 97, 97, 105, 105, 92, 92, 48, 48, 48, 48, 48, 48, 48, 48, 106, 106, 105, 105, 107, 107, 108, 108, 97, 97, 109, 109,
    104, 104, 97, 97, 97, 97, 97, 97, 105, 105, 92, 92, 48, 48, 48, 48, 48, 48, 48, 48, 106, 106, 105, 105, 107, 107, 108, 108, 97, 97, 109, 109,
    103, 103, 105, 105, 97, 97, 110, 110, 105, 105, 110, 110, 97, 97, 111, 111, 110, 110, 111, 111, 111, 111, 112, 112, 111, 111, 112, 112, 97, 97, 113, 113,
    103, 103, 105, 105, 97, 97, 110, 110, 105, 105, 110, 110, 97, 97, 111, 111, 110, 110, 111, 111, 111, 111, 112, 112, 111, 111, 112, 112, 97, 97, 113, 113,
    -1, -1, 114, 114, 114, 114, 114, 114, 115, 115, 115, 115, 116, 116, 115, 115, 114, 114, 114, 114, 114, 114, 117, 117, 118, 118, 119, 119, 119, 119, -1, -1,
    -1, -1, 114, 114, 114, 114, 114, 114, 115, 115, 115, 115, 116, 116, 115, 115, 114, 114, 114, 114, 114, 114, 117, 117, 118, 118, 119, 119, 119, 119, -1, -1,
    -1, -1, -1, -1, 115, 115, 116, 116, 120, 120, 121, 121, 120, 120, 121, 121, 122, 122, 120, 120, 120, 120, 121, 121, 120, 120, 121, 121, -1, -1, -1, -1,
    -1, -1, -1, -1, 115, 115, 116, 116, 120, 120, 121, 121, 120, 120, 121, 121, 122, 122, 120, 120, 120, 120, 121, 121, 120, 120, 121, 121, -1, -1, -1, -1,
  ]
  static let pixels: [Color?] = indices.map { $0 < 0 ? nil : palette[$0] }

  private static func pixel(x: Int, y: Int) -> Color? {
    guard x >= 0, x < width, y >= 0, y < height else {
      return nil
    }
    return pixels[y * width + x]
  }
}
