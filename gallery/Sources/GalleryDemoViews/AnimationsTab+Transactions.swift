import SwiftTUIRuntime

// The Transactions page: animation carried by the transaction rather than by
// a plain withAnimation block. Sections 14 to 19 cover the iOS 17 transaction
// surface; section 20 is the Binding.animation toggle.
extension AnimationsTab {
  var transactionsPage: some View {
    pageScroll {
      keyPathTransactionSection
      Divider()
      valueTransactionSection
      Divider()
      scopedTransactionSection
      Divider()
      completionListSection
      Divider()
      flingSection
      Divider()
      logicallyCompleteSection
      Divider()
      bindingAnimationSection
    }
  }

  // MARK: - 14. withTransaction key path

  private var keyPathTransactionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(14, "withTransaction(\\.disablesAnimations, true) inside withAnimation")
      expectLine(
        "the left button cross-fades the bar green/magenta over 1.2 s; the right button flips it instantly"
      )
      HStack(spacing: 2) {
        Button("animate") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            keyPathAccent.toggle()
            keyPathLastWrite = "animate"
          }
        }
        // Same animation scope; the key-path form keeps everything about it
        // except the animation intent, so only this write snaps.
        Button("snap") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            withTransaction(\.disablesAnimations, true) {
              keyPathAccent.toggle()
              keyPathLastWrite = "snap"
            }
          }
        }
      }
      .focusSection()
      Text("██████████████████████████████")
        .foregroundStyle(keyPathAccent ? Color.magenta : Color.green)
      stateLine("accent=\(keyPathAccent) lastWrite=\(keyPathLastWrite)")
    }
  }

  // MARK: - 15. .transaction(value:)

  private static let tensPalette: [Color] = [.green, .yellow, .cyan, .magenta, .red, .blue]

  private var valueTransactionSection: some View {
    let tens = tensCount / 10
    return VStack(alignment: .leading, spacing: 0) {
      sectionTitle(15, ".transaction(value: count / 10) animates only when the tens digit changes")
      expectLine(
        "single steps snap; crossing a ten slides the counter 4 cells and recolors it over 0.8 s")
      HStack(spacing: 2) {
        Button("+1") {
          tensCount += 1
        }
        Button("+10") {
          tensCount += 10
        }
      }
      .focusSection()
      // Plain writes: the only animation intent comes from the value-gated
      // transform, which runs when `count / 10` changes and not otherwise.
      Text("▶ \(tensCount)")
        .foregroundStyle(Self.tensPalette[tens % Self.tensPalette.count])
        .offset(x: (tens % 8) * 4, y: 0)
        .transaction(value: tens) { transaction in
          transaction.animation = .easeInOut(duration: .milliseconds(800))
        }
      stateLine("count=\(tensCount) tens=\(tens)")
    }
  }

  // MARK: - 16. .animation(_:body:) and .transaction(_:body:) scoped forms

  private var scopedTransactionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(16, ".animation(_:body:) and .transaction(_:body:) scope one modifier")
      expectLine(
        "top: slides 24 cells over 1.2 s while its color flips instantly; bottom: slides while its opacity snaps"
      )
      HStack(spacing: 2) {
        Button("shift (plain write)") {
          scopedShift.toggle()
        }
        Button("shift (withAnimation)") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            heldShift.toggle()
          }
        }
      }
      .focusSection()
      // The wrapped view keeps the (absent) outer transaction, so its color
      // snaps; the offset applied in the body animates whenever it changes.
      Text("▶ scoped offset")
        .foregroundStyle(scopedShift ? Color.cyan : Color.yellow)
        .animation(.easeInOut(duration: .milliseconds(1200))) { text in
          text.offset(x: scopedShift ? 24 : 0, y: 0)
        }
      // The inverse: the write animates, the wrapped offset follows it, and
      // the opacity applied in the body is held still by the scoped
      // transaction.
      Text("▶ held opacity")
        .foregroundStyle(Color.magenta)
        .offset(x: heldShift ? 24 : 0, y: 0)
        .transaction({ $0.disablesAnimations = true }) { text in
          text.opacity(heldShift ? 0.4 : 1)
        }
      stateLine("scopedShift=\(scopedShift) heldShift=\(heldShift)")
    }
  }

  // MARK: - 17. Transaction.addAnimationCompletion

  private var completionListSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(17, "Transaction.addAnimationCompletion: two closures on one transaction")
      expectLine(
        "pair: bar swaps green/magenta over 1.2 s, then completions rises by two; fade: removed rises only once the fade ends"
      )
      HStack(spacing: 2) {
        Button("run pair") {
          var transaction = Transaction(animation: .easeInOut(duration: .milliseconds(1200)))
          transaction.addAnimationCompletion {
            pairCompletions += 1
          }
          transaction.addAnimationCompletion {
            pairCompletions += 1
          }
          withTransaction(transaction) {
            pairAccent.toggle()
          }
        }
        Button(removableShown ? "fade out" : "fade in") {
          var transaction = Transaction(animation: .easeInOut(duration: .milliseconds(1200)))
          transaction.addAnimationCompletion(criteria: .removed) {
            removedCompletions += 1
          }
          withTransaction(transaction) {
            removableShown.toggle()
          }
        }
      }
      .focusSection()
      Text("██████████████████████")
        .foregroundStyle(pairAccent ? Color.magenta : Color.green)
      // An invisible twin keeps the slot's size while the removable text is
      // gone, so the removal never reflows the sections below.
      Text("▒▒▒▒ removable ▒▒▒▒")
        .opacity(0)
        .overlay {
          if removableShown {
            Text("▒▒▒▒ removable ▒▒▒▒")
              .foregroundStyle(Color.cyan)
              .transition(.opacity)
          }
        }
      stateLine(
        "completions=\(pairCompletions) accent=\(pairAccent) "
          + "shown=\(removableShown) removed=\(removedCompletions)"
      )
    }
  }

  // MARK: - 18. tracksVelocity fling

  /// The column the fling marker rests at on its track.
  static let flingHome = 20
  /// Columns on the fling track.
  static let flingTrackWidth = 60
  private static let flingSpring = Animation.spring(duration: .milliseconds(700), bounce: 0.15)
  private static let retargetSpring = Animation.spring(duration: .milliseconds(1500), bounce: 0.3)

  private var flingSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(
        18, "tracksVelocity: drag the ◆ and release; the spring keeps the drag's velocity")
      expectLine(
        "a fast drag-release overshoots home (column 20) in the drag direction, then settles; a slow release does not"
      )
      // Touch the task-written slot in body so it binds to this tab instance
      // before the task's first access (the PhaseAnimator trick).
      let _ = retargetServed
      HStack(spacing: 2) {
        Button("retarget spring") {
          retargetRequest += 1
        }
        Button("send home") {
          withAnimation(Self.flingSpring) {
            flingX = Self.flingHome
          } completion: {
            flingSettled += 1
          }
        }
      }
      .focusSection()
      // A long spring toward column 50 retargeted to home 300 ms in: the
      // second spring starts with the first one's velocity, so the marker
      // keeps moving right before it turns back instead of stopping dead.
      .task(id: retargetRequest) { @MainActor in
        guard retargetRequest > retargetServed else { return }
        retargetServed = retargetRequest
        withAnimation(Self.retargetSpring) {
          flingX = Self.flingHome + 30
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        // The completion rides the retarget spring, the one that actually
        // lands: `settled` ticking is the deterministic end-of-motion signal.
        withAnimation(Self.retargetSpring) {
          flingX = Self.flingHome
        } completion: {
          flingSettled += 1
        }
      }
      Text("◆")
        .foregroundStyle(Color.yellow)
        .offset(x: flingX, y: 0)
        .frame(width: Self.flingTrackWidth, height: 1, alignment: .leading)
        .contentShape(
          CellRect(
            origin: .init(x: 0, y: 0),
            size: .init(width: Self.flingTrackWidth, height: 1)
          )
        )
        .coordinateSpace(.named("fling-track"))
        .gesture(
          DragGesture(minimumDistance: 0, coordinateSpace: .named("fling-track"))
            .onChanged { value in
              if flingDragStart == nil {
                flingDragStart = value.time
              }
              let delta = Int(value.translation.dx.rounded())
              flingLastDelta = delta
              // Each during-drag write is velocity-tracked, so the release
              // spring below starts with the drag's release velocity.
              withTransaction(\.tracksVelocity, true) {
                flingX = min(max(Self.flingHome + delta, 0), Self.flingTrackWidth - 1)
              }
            }
            .onEnded { value in
              if let start = flingDragStart {
                let elapsed = start.duration(to: value.time)
                flingLastElapsedMilliseconds = Int((elapsed.totalSeconds * 1000).rounded())
              }
              flingDragStart = nil
              flingLastDelta = Int(value.translation.dx.rounded())
              withAnimation(Self.flingSpring) {
                flingX = Self.flingHome
              } completion: {
                flingSettled += 1
              }
            }
        )
      Text(String(repeating: " ", count: Self.flingHome) + "▲ home")
        .foregroundStyle(.muted)
      stateLine(
        "x=\(flingX) lastDelta=\(flingLastDelta) elapsedMs=\(flingLastElapsedMilliseconds) "
          + "settled=\(flingSettled)")
    }
  }

  // MARK: - 19. Animation.logicallyComplete(after:)

  private var logicallyCompleteSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(19, "Animation.logicallyComplete(after:) fires .logicallyComplete early")
      expectLine(
        "bar springs 10 to 40 cells and bounces for 1.5 s; logical ticks at 0.5 s mid-bounce, removed only once it stops"
      )
      HStack(spacing: 2) {
        Button("run spring") {
          var transaction = Transaction(
            animation: .spring(duration: .milliseconds(1500), bounce: 0.4)
              .logicallyComplete(after: .milliseconds(500))
          )
          transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            logicalCompletions += 1
          }
          transaction.addAnimationCompletion(criteria: .removed) {
            removedBarrierCompletions += 1
          }
          withTransaction(transaction) {
            logicalWide.toggle()
          }
        }
      }
      .focusSection()
      // A glyph bar (not a filled Rectangle) so the width is legible in a
      // text capture, frame strip included.
      Text(String(repeating: "█", count: 40))
        .foregroundStyle(logicalWide ? Color.cyan : Color.yellow)
        .frame(maxWidth: .finite(logicalWide ? 40 : 10), alignment: .leading)
      stateLine(
        "logical=\(logicalCompletions) removed=\(removedBarrierCompletions) wide=\(logicalWide)")
    }
  }

  // MARK: - 20. Binding.animation toggle

  private var bindingAnimationSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle(20, "Binding.animation toggle")
      expectLine(
        "bar grows 12 to 40 cells (or back); toggle uses .snappy, button uses 1.5 s easeInOut")
      HStack(spacing: 2) {
        // The Toggle writes through a binding that carries .snappy, so the
        // control itself never mentions animation.
        Toggle("Wide", isOn: $transactionWide.animation(.snappy))
        // Same write path, different curve: the transaction travels with the
        // binding, not with the call site.
        Button("flip (easeInOut)") {
          $transactionWide
            .animation(.easeInOut(duration: .milliseconds(1500)))
            .wrappedValue
            .toggle()
        }
      }
      .focusSection()
      Rectangle()
        .fill(transactionWide ? Color.green : Color.magenta)
        .frame(maxWidth: .finite(transactionWide ? 40 : 12), alignment: .leading)
        .frame(height: 1)
      stateLine("wide=\(transactionWide)")
    }
  }
}
