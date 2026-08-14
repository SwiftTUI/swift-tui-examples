import CoreGraphics
import XCTest

#if os(iOS)
  import UIKit
#endif

final class PreviewReadinessJourneyTests: XCTestCase {
  private let clipboardToken = "SwiftTUI preview clipboard token"

  @MainActor
  func testPreviewReadinessJourney() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments.append("--preview-readiness-journey")
    app.launch()

    let heading = element(label: "Preview readiness host journey", in: app)
    XCTAssertTrue(heading.waitForExistence(timeout: 20))
    #if os(iOS)
      XCTAssertTrue(
        app.staticTexts.matching(
          NSPredicate(format: "label == %@", "Preview readiness host journey")
        ).firstMatch.exists
      )
    #elseif os(macOS)
      // The macOS host exposes the authored heading through the generic
      // semantic element class. Button and image roles are asserted below.
      XCTAssertEqual(heading.label, "Preview readiness host journey")
    #endif

    let geometry = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'Geometry cells '")
    ).firstMatch
    XCTAssertTrue(geometry.waitForExistence(timeout: 10))
    XCTAssertTrue(geometry.label.range(of: #"\d+ by \d+"#, options: .regularExpression) != nil)
    let initialGeometryLabel = geometry.label

    #if os(macOS)
      // Exercise window resizing before assertions about the released host's
      // input behavior can stop the journey.
      assertGeometryMutation(from: initialGeometryLabel, in: app)
    #endif

    // The scene authors a default FocusState request. Keyboard synthesis goes
    // to the host surface's actual first responder; no accessibility editing
    // action is invoked or claimed here.
    let editor = element(label: "Journey editor", in: app)
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    // Do not tap the field: successful text synthesis below is the observable
    // proof that the runtime-origin focus request made the native surface the
    // platform first responder.
    app.typeText("-native")
    XCTAssertTrue(
      element(label: "Editor state seed-native", in: app).waitForExistence(timeout: 10)
    )

    // Locate with one-way semantics, then synthesize an ordinary pointer/touch
    // at the mapped frame. This is not assistive-origin activation.
    let pointer = element(label: "Pointer count 0", in: app)
    XCTAssertTrue(pointer.waitForExistence(timeout: 10))
    XCTAssertTrue(button(label: "Pointer count 0", in: app).exists)
    activateWithOrdinaryPointer(pointer)
    XCTAssertTrue(element(label: "Pointer count 1", in: app).waitForExistence(timeout: 10))

    #if os(iOS)
      // Preserve the runtime-origin focus proof before rotating the device.
      assertGeometryMutation(from: initialGeometryLabel, in: app)
    #endif

    // These are authored buttons whose ordinary pointer actions mutate the
    // real TabView selection. Semantics only locates their native frames; the
    // journey does not query or claim activation of ordinary tab chrome.
    let showEvidence = element(label: "Show evidence", in: app)
    XCTAssertTrue(button(label: "Show evidence", in: app).exists)
    activateWithOrdinaryPointer(showEvidence)
    XCTAssertTrue(
      element(label: "Navigation state evidence actions 1", in: app)
        .waitForExistence(timeout: 10)
    )

    let image = element(label: "Half opacity red image", in: app)
    XCTAssertTrue(image.waitForExistence(timeout: 10))
    #if os(iOS)
      XCTAssertTrue(
        app.images.matching(NSPredicate(format: "label == %@", "Half opacity red image"))
          .firstMatch.exists
      )
    #elseif os(macOS)
      // Like the heading, the macOS one-way host exposes this authored name
      // through a generic semantic element. Button roles remain asserted.
      XCTAssertEqual(image.label, "Half opacity red image")
    #endif
    assertHalfOpacityRedOverBlue(image.screenshot())

    let showEditor = element(label: "Show editor", in: app)
    XCTAssertTrue(button(label: "Show editor", in: app).exists)
    activateWithOrdinaryPointer(showEditor)
    XCTAssertTrue(
      element(label: "Navigation state editor actions 2", in: app)
        .waitForExistence(timeout: 10)
    )
    XCTAssertTrue(element(label: "Editor state seed-native", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(element(label: "Pointer count 1", in: app).waitForExistence(timeout: 10))

    let copy = element(label: "Copy journey token", in: app)
    activateWithOrdinaryPointer(copy)
    let copiedStatus = element(label: "Clipboard: copied", in: app)
    XCTAssertTrue(copiedStatus.waitForExistence(timeout: 10))

    // Paste with ordinary platform keyboard input. This both proves the copy
    // action reached the real system clipboard and avoids reading another
    // process's pasteboard container from the UI-test runner.
    let pasteVerifier = element(label: "Paste verifier", in: app)
    activateWithOrdinaryPointer(pasteVerifier)
    XCTAssertTrue(element(label: "Paste focus active", in: app).waitForExistence(timeout: 10))
    app.typeKey("v", modifierFlags: .command)
    XCTAssertTrue(
      element(label: "Paste state \(clipboardToken)", in: app).waitForExistence(timeout: 10)
    )

    let logical = element(label: "Run logical completion", in: app)
    activateWithOrdinaryPointer(logical)
    XCTAssertTrue(
      element(label: "Completion counts: logical 1, removed 0", in: app)
        .waitForExistence(timeout: 10)
    )

    let removed = element(label: "Run removed completion", in: app)
    activateWithOrdinaryPointer(removed)
    XCTAssertTrue(
      element(label: "Completion counts: logical 1, removed 1", in: app)
        .waitForExistence(timeout: 10)
    )

    // Names, roles, and runtime-origin focus are covered above. VoiceOver can
    // read this one-way tree, but assistive-origin activation/editing/focus are
    // intentionally not exercised or recorded as supported by this test.
  }

  @MainActor
  private func element(label: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", label)
    ).firstMatch
  }

  @MainActor
  private func button(label: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
  }

  @MainActor
  private func activateWithOrdinaryPointer(_ element: XCUIElement) {
    let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    #if os(macOS)
      coordinate.click()
    #elseif os(iOS)
      coordinate.tap()
    #endif
  }

  @MainActor
  private func assertGeometryMutation(
    from initialGeometryLabel: String,
    in app: XCUIApplication
  ) {
    #if os(iOS)
      let device = XCUIDevice.shared
      let actionableOrientation = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          switch device.orientation {
          case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            true
          default:
            false
          }
        },
        object: nil
      )
      XCTAssertEqual(XCTWaiter.wait(for: [actionableOrientation], timeout: 5), .completed)

      let initialOrientation = device.orientation
      let targetOrientation: UIDeviceOrientation
      switch initialOrientation {
      case .portrait, .portraitUpsideDown:
        targetOrientation = .landscapeLeft
      case .landscapeLeft, .landscapeRight:
        targetOrientation = .portrait
      default:
        return XCTFail("device did not report a portrait or landscape orientation")
      }
      defer { device.orientation = initialOrientation }

      let window = app.windows.firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: 5))
      let initialWindowFrame = window.frame
      let initialWindowIsPortrait = initialWindowFrame.height > initialWindowFrame.width

      device.orientation = targetOrientation
      let windowChangedOrientationClass = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          let changedFrame = window.frame
          return changedFrame.size != initialWindowFrame.size
            && (changedFrame.height > changedFrame.width) != initialWindowIsPortrait
        },
        object: nil
      )
      XCTAssertEqual(
        XCTWaiter.wait(for: [windowChangedOrientationClass], timeout: 10),
        .completed
      )
    #elseif os(macOS)
      let window = app.windows.firstMatch
      XCTAssertTrue(window.exists)
      let initialWindowSize = window.frame.size
      let resizeButton = app.buttons["Resize preview window"]
      XCTAssertTrue(resizeButton.waitForExistence(timeout: 5))
      // This is native host chrome, not the hosted one-way semantic overlay;
      // click() synthesizes an ordinary macOS pointer click.
      resizeButton.click()
      let windowSizeChanged = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in window.frame.size != initialWindowSize },
        object: nil
      )
      XCTAssertEqual(XCTWaiter.wait(for: [windowSizeChanged], timeout: 10), .completed)
    #endif

    let changedGeometry = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "label BEGINSWITH 'Geometry cells ' AND label != %@",
        initialGeometryLabel
      )
    ).firstMatch
    XCTAssertTrue(changedGeometry.waitForExistence(timeout: 10))

    #if os(iOS)
      // XCUIElement queries stay live. Snapshot the landscape value before
      // asking UIKit to restore portrait; reading it later would capture the
      // restored label and make the settle predicate self-contradictory.
      let changedGeometryLabel = changedGeometry.label

      // Rotation restoration is asynchronous. Do not let the next semantic
      // coordinate tap race a portrait window whose host grid is still the
      // landscape grid used to produce the accessibility frame.
      device.orientation = initialOrientation
      let windowRestoredOrientationClass = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          let restoredFrame = window.frame
          return restoredFrame.size == initialWindowFrame.size
            && (restoredFrame.height > restoredFrame.width) == initialWindowIsPortrait
        },
        object: nil
      )
      XCTAssertEqual(
        XCTWaiter.wait(for: [windowRestoredOrientationClass], timeout: 10),
        .completed
      )

      let restoredGeometry = app.descendants(matching: .any).matching(
        NSPredicate(
          format: "label BEGINSWITH 'Geometry cells ' AND label != %@",
          changedGeometryLabel
        )
      ).firstMatch
      XCTAssertTrue(restoredGeometry.waitForExistence(timeout: 10))
      XCTAssertTrue(window.frame.contains(restoredGeometry.frame))

      XCTContext.runActivity(named: "Post-rotation semantic geometry settled") { activity in
        let attachment = XCTAttachment(
          string:
            "initial=\(initialGeometryLabel); landscape=\(changedGeometryLabel); restored=\(restoredGeometry.label); window=\(window.frame); semanticFrame=\(restoredGeometry.frame)"
        )
        attachment.lifetime = .keepAlways
        activity.add(attachment)
      }
    #endif
  }

  private func assertHalfOpacityRedOverBlue(_ screenshot: XCUIScreenshot) {
    #if os(macOS)
      var proposed = CGRect(origin: .zero, size: screenshot.image.size)
      guard
        let image = screenshot.image.cgImage(
          forProposedRect: &proposed,
          context: nil,
          hints: nil
        )
      else {
        return XCTFail("image screenshot has no CGImage")
      }
    #elseif os(iOS)
      guard let image = screenshot.image.cgImage else {
        return XCTFail("image screenshot has no CGImage")
      }
    #endif
    guard let components = centerPixel(in: image) else {
      return XCTFail("could not sample image screenshot")
    }
    let red = components.0
    let green = components.1
    let blue = components.2
    XCTAssertGreaterThan(Int(red), Int(green) + 35)
    XCTAssertGreaterThan(Int(blue), Int(green) + 35)
    XCTAssertLessThan(abs(Int(red) - Int(blue)), 90)
  }

  private func centerPixel(in image: CGImage) -> (UInt8, UInt8, UInt8)? {
    var pixel = [UInt8](repeating: 0, count: 4)
    guard
      let context = CGContext(
        data: &pixel,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.interpolationQuality = .none
    context.draw(
      image,
      in: CGRect(
        x: -CGFloat(image.width / 2),
        y: -CGFloat(image.height / 2),
        width: CGFloat(image.width),
        height: CGFloat(image.height)
      )
    )
    return (pixel[0], pixel[1], pixel[2])
  }
}
