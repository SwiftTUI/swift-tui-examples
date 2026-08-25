import SwiftTUIRuntime

// The Matched page: matchedGeometryEffect with its properties and anchor
// (section 6). Section 13 (co-present adoption, isSource: false) is skipped:
// that framework stage was deferred.
extension AnimationsTab {
  var matchedPage: some View {
    pageScroll {
      matchedGeometrySection
    }
  }

  // MARK: - 6. matchedGeometryEffect

  /// Inner size of the badge in each slot, before its one-cell border.
  static let heroLeftSlot = CellSize(width: 9, height: 1)
  static let heroRightSlot = CellSize(width: 18, height: 3)

  private var matchedGeometrySection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(6, "matchedGeometryEffect: badge slides and resizes between two slots")
      expectLine(
        "badge slides right AND its box grows over 1.5 s, cross-fading between the two slots; "
          + "position only slides (box snaps), size grows in place"
      )
      HStack(spacing: 2) {
        Button(heroOnRight ? "move left" : "move right") {
          withAnimation(.easeInOut(duration: .milliseconds(1500))) {
            heroOnRight.toggle()
            heroMoves += 1
          } completion: {
            heroSettled += 1
          }
        }
      }
      .focusSection()
      HStack(alignment: .top, spacing: 2) {
        Picker("properties", selection: $heroProperties) {
          ForEach(MatchedPropertiesChoice.allCases, id: \.self) { choice in
            Text(choice.rawValue).tag(choice)
          }
        }
        .pickerStyle(.segmented)
        .frame(height: 4)
        Picker("anchor", selection: $heroAnchor) {
          ForEach(MatchedAnchorChoice.allCases, id: \.self) { choice in
            Text(choice.rawValue).tag(choice)
          }
        }
        .pickerStyle(.segmented)
        .frame(height: 4)
      }
      // Two HStack orderings swapped based on state. The badge is tagged
      // with matchedGeometryEffect scoped to heroNamespace, so the controller
      // recognizes it as the same view across the swap and animates the move
      // between the two slots. Its background and border sit INSIDE the
      // modifier, so the chrome follows the interpolated box.
      HStack(alignment: .top, spacing: 3) {
        if !heroOnRight {
          heroBadge(size: Self.heroLeftSlot)
          heroSlotPlaceholder(size: Self.heroRightSlot)
        } else {
          heroSlotPlaceholder(size: Self.heroLeftSlot)
          heroBadge(size: Self.heroRightSlot)
        }
      }
      // The taller slot plus its border, so the swap never reflows the page.
      .frame(height: Self.heroRightSlot.height + 2, alignment: .topLeading)
      stateLine(
        "heroOnRight=\(heroOnRight) properties=\(heroProperties.rawValue) "
          + "anchor=\(heroAnchor.rawValue) box=\(heroBoxReadout) moves=\(heroMoves) "
          + "settled=\(heroSettled)"
      )
    }
  }

  /// The badge's destination box (its slot plus the border). The
  /// interpolated box is a placed-level overlay, so no GeometryReader can
  /// observe it; the badge's own label shows the layout size and `settled`
  /// counts finished moves.
  private var heroBoxReadout: String {
    let slot = heroOnRight ? Self.heroRightSlot : Self.heroLeftSlot
    return "\(slot.width + 2)x\(slot.height + 2)"
  }

  private func heroBadge(size: CellSize) -> some View {
    GeometryReader { proxy in
      // The badge prints the size it laid out at: the destination size from
      // the first animated frame on, while the drawn box is still growing.
      Text("★\(proxy.size.width)x\(proxy.size.height)")
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .frame(width: size.width, height: size.height)
    // The border draws on the outer ring of its bounds, so pad first: the
    // badge box is the slot plus one cell on every side.
    .padding(1)
    .background(Color.yellow)
    .border(set: .single)
    // Both slots' instances carry the transition, so the swap cross-fades
    // along the matched path: the departing badge's exit overlay travels to
    // the new slot while the arriving one fades in from the old slot.
    .transition(.opacity)
    .matchedGeometryEffect(
      id: "hero",
      in: heroNamespace,
      properties: heroProperties.properties,
      anchor: heroAnchor.unitPoint
    )
  }

  private func heroSlotPlaceholder(size: CellSize) -> some View {
    Text("(empty)")
      .frame(width: size.width, height: size.height)
      .padding(1)
      .border(set: .single)
      .foregroundStyle(.muted)
  }
}

/// The `properties:` argument section 6 offers.
enum MatchedPropertiesChoice: String, CaseIterable, Hashable, Sendable {
  case frame
  case position
  case size

  var properties: MatchedGeometryProperties {
    switch self {
    case .frame: .frame
    case .position: .position
    case .size: .size
    }
  }
}

/// The `anchor:` argument section 6 offers.
enum MatchedAnchorChoice: String, CaseIterable, Hashable, Sendable {
  case center
  case topLeading
  case bottomTrailing

  var unitPoint: UnitPoint {
    switch self {
    case .center: .center
    case .topLeading: .topLeading
    case .bottomTrailing: .bottomTrailing
    }
  }
}
