# SwiftUI host for three-hosts-demo

This directory holds the source for a native SwiftUI macOS app that embeds
`ThreeHostsDemoCore.CounterApp` via `SwiftUIHost`. It is the third surface in
the marketing "same App, three hosts" capture.

The file is **not** built by the parent `Package.swift`. Native SwiftUI macOS
apps need an Xcode project (or XcodeGen / Tuist) to produce a `.app` bundle
with the right Info.plist. Mirror the layout used by
[`../../SwiftUIExample/`](../../SwiftUIExample/):

1. `open -a Xcode .` from this directory (or set up XcodeGen).
2. Add a new macOS App target; point its sources at `SwiftUIHostApp.swift`.
3. Add a SwiftPM package dependency on `../` (the `three-hosts-demo` package)
   and link `ThreeHostsDemoCore`. Also link the `SwiftUIHost` product from
   `swift-tui` (transitively re-exported by `ThreeHostsDemoCore` via the
   `SwiftTUI` umbrella import).
4. Build & run. A native window appears showing the same `CounterView`
   rendering as the terminal and browser hosts.

When the Xcode project exists, the org-level marketing recording (Task 2.4
in `swift-tui-org/docs/plans/2026-05-27-002-marketing-improvements-plan.md`)
captures all three windows side-by-side.
