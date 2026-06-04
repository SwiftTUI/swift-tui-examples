import SwiftTUIRuntime


enum LogoArt {
  static let width = 32
  static let height = 32
  private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUV")
  private static let palette: [Color] = [
    Color(hexRGB: 0x00FFFF),  // 0
    Color(hexRGB: 0x00EAEA),  // 1
    Color(hexRGB: 0x00FFEA),  // 2
    Color(hexRGB: 0x15FFFF),  // 3
    Color(hexRGB: 0x00EAD5),  // 4
    Color(hexRGB: 0x00D5D5),  // 5
    Color(hexRGB: 0x00D5BF),  // 6
    Color(hexRGB: 0x00BFAA),  // 7
    Color(hexRGB: 0x00EABF),  // 8
    Color(hexRGB: 0x00D5AA),  // 9
    Color(hexRGB: 0x006A6A),  // A
    Color(hexRGB: 0x00556A),  // B
    Color(hexRGB: 0x2B2B2B),  // C
    Color(hexRGB: 0x004055),  // D
    Color(hexRGB: 0x00BF95),  // E
    Color(hexRGB: 0x008080),  // F
    Color(hexRGB: 0x009580),  // G
    Color(hexRGB: 0x005555),  // H
    Color(hexRGB: 0x002B40),  // I
    Color(hexRGB: 0x00D595),  // J
    Color(hexRGB: 0x00956A),  // K
    Color(hexRGB: 0x006A55),  // L
    Color(hexRGB: 0x004040),  // M
    Color(hexRGB: 0x00806A),  // N
    Color(hexRGB: 0x00BF80),  // O
    Color(hexRGB: 0x00AA80),  // P
    Color(hexRGB: 0x005540),  // Q
    Color(hexRGB: 0x002B2B),  // R
    Color(hexRGB: 0x00AA6A),  // S
    Color(hexRGB: 0x00152B),  // T
    Color(hexRGB: 0x00D580),  // U
    Color(hexRGB: 0x00AA95),  // V
  ]
  private static let bitmap: [String] = [
    "     0111111112022220020003     ",
    "   01444455555422222222220003   ",
    "  0145555555555411111111111200  ",
    " 316555555555556412111111111103 ",
    " 466666666666666667244444444420 ",
    "089666666666666666AB444444444423",
    "4699999979999999999CD64844444842",
    "69777799EF997777779FCD6888888841",
    "6EEEEEFE9GHEEEEEEEEEICH866666684",
    "9EEEEJKHEJLMEEEEEEEJHCCN99999984",
    "9OOOOOJLIPJMIPEOOOOENCCCE9999998",
    "JOOOOOOOQCKORCKOOOOOKCCCLJJJJJJ6",
    "EOOOOOOOOMCLSCCNOOPOSCCCTOJJJJJ9",
    "EPPPPPPPPPICMLCCHPOPKCCCCNUOOOU9",
    "EPPPPPPPPPKTCCRCCIKOKCCCCHUOOOOJ",
    "EPPPPPPPPPPKCCCCCCCLHCCCCMOOOOOJ",
    "EPPPPPPPPPPPNCCCCCCCCCCCCIPOOOOE",
    "EPPPPGGGGGGGPNCCCCCCCCCCCIPPPPPE",
    "EPPNGPGGGGGGGPNTCCCCCCCCCMPPPPPE",
    "EPPGMAGGGGGGGGGGICCCCCCCCHPPPPPO",
    "VPGPNCILNGGGGGGNMCCCCCCCCTGPGPPP",
    "VGGGPNCCCIMDDIICCCCCCCCCCCDPGGGP",
    "VGGGGGNCCCCCCCCCCCCCCCCCCCCFGGGP",
    "VGGGGGGFMCCCCCCCCCCCCCCCCCCBGGGP",
    "PGGGGGGGGAICCCCCCCCCCIHAADCDGGGP",
    "PGFFFFFFFGFAMCCCCCCIAFGGGGDDGFGP",
    "PGFFFFFFFFFFGFABBAFFFFFFFFFNFFGJ",
    " GFFFFFFFFFFFFFFFFFFFFFFFFFFFFV ",
    " GGFFFFFFFFFFFFFFFFFFFFFFFFFFG9 ",
    "  GGFFFFFFFFFFFFFFFFFFFFFFFFGE  ",
    "   GFFFFFFFFFFFFFFFFFFFFFFFGJ   ",
    "     GGFFFFFFFFFFFFFFFFGGGO     ",
  ]
  static let pixels: [Color?] = {
    let indexByGlyph = Dictionary(
      uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) }
    )
    return bitmap.flatMap { row in
      row.map { glyph in indexByGlyph[glyph].map { palette[$0] } }
    }
  }()
}
