import Foundation
import SwiftTUIRuntime

/// One deliberately small scene shared by the terminal and native SwiftUI
/// host journeys. It uses only the public package surface consumed by an
/// external application.
public struct PreviewReadinessApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Preview Readiness") {
      PreviewReadinessView()
    }
  }
}

public struct PreviewReadinessView: View {
  private enum JourneyTab: Hashable, Sendable {
    case editor
    case evidence
  }

  @Environment(\.requestTermination) private var requestTermination
  @State private var selection: JourneyTab = .editor
  @State private var navigationActionCount = 0
  @State private var logicalOpacity = 1.0
  @State private var removedOpacity = 1.0
  @State private var logicalCompletionCount = 0
  @State private var removedCompletionCount = 0

  public init() {}

  public var body: some View {
    GeometryReader { geometry in
      VStack(alignment: .leading, spacing: 1) {
        Text("Preview readiness host journey")
          .accessibilityRole(.heading(level: 1))
        Text("Geometry cells: \(geometry.size.width)x\(geometry.size.height)")
          .accessibilityLabel(
            "Geometry cells \(geometry.size.width) by \(geometry.size.height)"
          )

        HStack(spacing: 1) {
          Button("Show editor") {
            navigationActionCount += 1
            selection = .editor
          }
          .accessibilityLabel("Show editor")
          .accessibilityHint("Presents the editor tab using ordinary pointer input.")

          Button("Show evidence") {
            navigationActionCount += 1
            selection = .evidence
          }
          .accessibilityLabel("Show evidence")
          .accessibilityHint("Presents the evidence tab using ordinary pointer input.")
        }

        Text(
          "Navigation state: \(selection == .editor ? "editor" : "evidence"), actions: \(navigationActionCount)"
        )
        .accessibilityRole(.status)
        .accessibilityLabel(
          "Navigation state \(selection == .editor ? "editor" : "evidence") actions \(navigationActionCount)"
        )

        TabView(selection: $selection) {
          Tab("Editor", value: JourneyTab.editor) {
            EditorJourneyTab()
          }
          Tab("Evidence", value: JourneyTab.evidence) {
            evidenceTab
          }
        }
        .tabViewStyle(.literalTabs)

        completionEvidence

        Button("Quit journey") {
          _ = requestTermination()
        }
        .accessibilityHint("Terminates the terminal journey executable.")
      }
      .padding(1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private struct EditorJourneyTab: View {
    private static let clipboardToken = "SwiftTUI preview clipboard token"

    @Environment(\.clipboardWriteAction) private var clipboardWriteAction
    @State private var pointerCount = 0
    @State private var editorText = "seed"
    @State private var clipboardStatus = "Clipboard: idle"
    @State private var pastedText = ""
    @FocusState private var editorFocused: Bool
    @FocusState private var pasteFocused: Bool

    var body: some View {
      VStack(alignment: .leading, spacing: 1) {
        TextField("Journey editor", text: $editorText)
          .focused($editorFocused)
          .defaultFocus($editorFocused)
          .accessibilityLabel("Journey editor")
          .accessibilityHint("Edits persistent tab-local text.")

        Button("Pointer count: \(pointerCount)") {
          pointerCount += 1
        }
        .accessibilityLabel("Pointer count \(pointerCount)")
        .accessibilityHint("Increments the pointer journey count.")

        Button("Copy journey token") {
          let copied = clipboardWriteAction(Self.clipboardToken)
          clipboardStatus = copied ? "Clipboard: copied" : "Clipboard: unavailable"
        }
        .accessibilityLabel("Copy journey token")
        .accessibilityHint("Writes the preview token to the native system clipboard.")

        Text(clipboardStatus)
          .accessibilityRole(.status)
          .accessibilityLiveRegion(.polite)

        TextField("Paste verifier", text: $pastedText)
          .focused($pasteFocused)
          .accessibilityLabel("Paste verifier")
          .accessibilityHint("Accepts an ordinary platform paste command.")

        Text("Paste focus: \(pasteFocused ? "active" : "inactive")")
          .accessibilityLabel("Paste focus \(pasteFocused ? "active" : "inactive")")

        Text("Paste state: \(pastedText)")
          .accessibilityLabel("Paste state \(pastedText)")

        Text("Editor state: \(editorText)")
          .accessibilityLabel("Editor state \(editorText)")
      }
    }
  }

  private var evidenceTab: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Half-opacity red image on blue")
      Image(data: Self.redPNGBytes)
        .resizable()
        .frame(width: 4, height: 2)
        .opacity(0.5)
        .background(Color.blue)
        .accessibilityLabel("Half opacity red image")
    }
  }

  private var completionEvidence: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Text("logical target")
          .opacity(logicalOpacity)
        Text("removed target")
          .opacity(removedOpacity)
      }

      HStack(spacing: 1) {
        Button("Run logical completion") {
          withAnimation(
            .linear(duration: .milliseconds(700)),
            completionCriteria: .logicallyComplete
          ) {
            logicalOpacity = 0.2
          } completion: {
            logicalCompletionCount += 1
          }
        }
        .accessibilityLabel("Run logical completion")

        Button("Run removed completion") {
          withAnimation(
            .linear(duration: .milliseconds(700)),
            completionCriteria: .removed
          ) {
            removedOpacity = 0.2
          } completion: {
            removedCompletionCount += 1
          }
        }
        .accessibilityLabel("Run removed completion")
      }

      Text(
        "Completion counts: logical \(logicalCompletionCount), removed \(removedCompletionCount)"
      )
      .accessibilityRole(.status)
      .accessibilityLiveRegion(.polite)
    }
  }

  private static let redPNGBytes: [UInt8] = {
    let encoded =
      "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQAQMAAAAlPW0iAAAAA1BMVEX/AAAZ4gk3"
      + "AAAADElEQVQI12NgIA0AAAAwAAHHqoWOAAAAAElFTkSuQmCC"
    return Data(base64Encoded: encoded).map { Array($0) } ?? []
  }()
}
