import SwiftTUIRuntime

// The Matched page: matchedGeometryEffect with its properties and anchor
// (section 6), and co-present adoption via `isSource: false` (section 13,
// whose reserved number survived the stage's deferral until 0.9.12).
extension AnimationsTab {
  var matchedPage: some View {
    pageScroll {
      matchedGeometrySection
      Divider()
      adoptionSection
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

  // MARK: - 13. Co-present adoption (isSource: false)

  /// Inner size of the card in any of its three slots, before its border.
  static let adoptionCardSize = CellSize(width: 8, height: 1)

  private var adoptionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(13, "matchedGeometryEffect(isSource: false): the badge adopts the card")
      // The prose must not contain any control label or readout target (the
      // button labels, the badge's glyph): the runtime test aims clicks and
      // scoped readouts below the title, and a match inside this line would
      // hit inert text (the 2026-08-30 drag-probe lesson).
      expectLine(
        "the yellow badge renders on the card's top-trailing corner, never at its own slot "
          + "below; moving slides card and badge together over 1.5 s; detaching returns the "
          + "badge to its slot from the adopted rect; re-attaching adopts the third slot"
      )
      HStack(spacing: 2) {
        // A fixed label: the runtime test aims clicks from a pre-run render,
        // so button geometry must not shift with state. The state line says
        // which slot the card is in.
        Button("move card") {
          withAnimation(.easeInOut(duration: .milliseconds(1500))) {
            cardSlot = cardSlot == .left ? .right : .left
            cardMoves += 1
          } completion: {
            cardSettled += 1
          }
        }
        Button(cardAttached ? "detach card" : "attach third") {
          withAnimation(.easeInOut(duration: .milliseconds(1500))) {
            if cardAttached {
              cardAttached = false
            } else {
              cardAttached = true
              cardSlot = .third
            }
          } completion: {
            cardSettled += 1
          }
        }
      }
      .focusSection()
      // Three fixed slots; the card occupies exactly one of them (or none
      // while detached), so the row never reflows. The badge is declared in
      // its own row BELOW — layout keeps its slot there, but whenever a
      // source card is on screen the badge is drawn at the card's corner
      // instead: co-present adoption is a render-time rule, applied every
      // frame and without an animation of its own.
      HStack(alignment: .top, spacing: 3) {
        adoptionSlot(.left)
        adoptionSlot(.right)
        adoptionSlot(.third)
      }
      .frame(height: Self.adoptionCardSize.height + 2, alignment: .topLeading)
      HStack(spacing: 1) {
        Text("badge home:").foregroundStyle(.muted)
        // `.position` with a `.topTrailing` anchor: the badge keeps its own
        // size and pins its top-trailing corner to the card's. When the card
        // leaves inside the animated detach transaction, the badge slides
        // back here from the rect it was drawn at.
        Text("NEW")
          .foregroundStyle(Color.black)
          .background(Color.yellow)
          .matchedGeometryEffect(
            id: "card",
            in: badgeNamespace,
            properties: .position,
            anchor: .topTrailing,
            isSource: false
          )
      }
      stateLine(
        "cardSlot=\(cardSlot.rawValue) attached=\(cardAttached) moves=\(cardMoves) "
          + "settled=\(cardSettled)"
      )
    }
  }

  private func adoptionSlot(_ slot: AdoptionCardSlot) -> some View {
    Group {
      if cardAttached, cardSlot == slot {
        Text("CARD")
          .frame(width: Self.adoptionCardSize.width, height: Self.adoptionCardSize.height)
          .padding(1)
          .border(set: .single)
          .matchedGeometryEffect(id: "card", in: badgeNamespace)
      } else {
        Text("(empty)")
          .frame(width: Self.adoptionCardSize.width, height: Self.adoptionCardSize.height)
          .padding(1)
          .border(set: .single)
          .foregroundStyle(.muted)
      }
    }
  }
}

/// The slot the section 13 card occupies.
enum AdoptionCardSlot: String, Hashable, Sendable {
  case left
  case right
  case third
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
