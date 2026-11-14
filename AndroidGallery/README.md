# Android Gallery

This example embeds the SwiftTUI gallery in an Android Compose host. The same
app runs on a native Jetpack Compose surface through `SwiftTUIAndroidHost`.

## Run

```bash
./gradlew :app:assembleDebug
```

Run the command from this directory. From the repository root, run
`(cd AndroidGallery && ./gradlew :app:assembleDebug)`.

## Demonstrates

- `SwiftTUIAndroidHost` renders the same SwiftTUI `App` on a native Android
  surface. The gallery contains no platform-specific view code.
- A Compose `SwiftTUIHostView` measures the available pixels and converts them
  to a terminal-cell grid. It sends resize information to SwiftTUI, so the
  layout follows the device viewport.
- The Compose renderer paints styled cells, backgrounds, text decorations, and
  embedded images into a retained bitmap. For each new frame it repaints only
  the damaged rows. Decoded image bitmaps stay in a bounded cache.
- A transparent host view exposes virtual children to Android accessibility.
  Their focus, activation, adjustment, and text-edit actions go to the runtime
  through JNI.
- Hardware keys, touch taps and drags, wheel scrolling, and the soft keyboard
  reach SwiftTUI as terminal input, so the gallery is interactive on the
  device. The soft keyboard delivers committed text only.
- `Ctrl+V` and `Shift+Insert` paste the system clipboard as a bracketed paste,
  and text that the app copies goes to the system clipboard. A tap on a
  hyperlink cell opens its destination through the Compose `UriHandler`.

## How it works

The app builds `GalleryAndroidHost` as an `arm64-v8a` Android dynamic library.
This package depends on `GalleryDemoViews`, `SwiftTUIAndroidHost`, and
`SwiftTUIRuntime`. The build copies the Swift Android runtime libraries into
generated `jniLibs`. A small JNI shim connects Kotlin to the
`SwiftTUIAndroidHost` C ABI.

The first screen is a Compose `SwiftTUIHostView` with a native Swift host
handle. The host library polls that handle and decodes the shared SwiftTUI
`web-surface` wire, the record format that the browser host also reads. A
full-frame record carries the whole grid. A delta record replaces whole rows of
the previous frame. A record contains terminal colors, raster rows, cell
styles, link targets, damage metadata, and image attachments. It also contains
the accessibility tree, announcements, focus presentation, and the preferred
layout size. The
[host wire contract](https://github.com/SwiftTUI/swift-tui/blob/main/docs/HOST-WIRE-CONTRACT.md)
is the normative description.

The demo package supports only `arm64-v8a`. The framework also cross-compiles
for `x86_64-unknown-linux-android28`. This difference is a packaging-scope
choice, not a framework limitation: the published host AAR and Gradle plugin
build and stage `arm64-v8a` only. An `x86_64` lane needs these changes. All but
the first belong to `swift-tui-android`:

1. Add the ABI to `app/build.gradle.kts`.
2. Add the ABI to the `:swift-tui-host` `Application.mk`.
3. Add a second `--swift-sdk` cross-build to the convention plugin.
4. Copy the output for each ABI.

## Build

Prerequisites:

- Install Android Studio and Android SDK Platform 37.1.
- Install Swift 6.4.0 through `swiftly`.
- Install the Swift Android SDK bundle `swift-6.4.0-RELEASE_android`.
- Install Android NDK `30.0.16248370` through Android Studio's SDK Manager.
  The build uses it from the Android SDK directory by default; set
  `ANDROID_NDK_HOME` to use another installation.

After installing the 6.4.0 Swift Android SDK, materialize its `ndk-sysroot` once:

```bash
ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/30.0.16248370" \
"$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh"
```

The Gradle build creates the `app/build/swift-sdks` search path before it calls
SwiftPM. This path contains only the configured
`swift-6.4.0-RELEASE_android` bundle. If the bundle is not in the default
SwiftPM SDK directory, set
`SWIFT_ANDROID_SDK_BUNDLE` to the `.artifactbundle` path.

The Swift package manifest uses a public HTTPS SwiftTUI dependency.
Pre-release integration against a local framework checkout happens in the
SwiftTUI coordination root, not here.

If the SDK and NDK are not on the default paths, use this command:

```bash
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
ANDROID_HOME="$HOME/Library/Android/sdk" \
ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/30.0.16248370" \
SWIFT_ANDROID_SDK_BUNDLE="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_android.artifactbundle" \
SWIFT_ANDROID_ROOT="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_android.artifactbundle/swift-android" \
gradle :app:assembleDebug
```

The Gradle wrapper is committed, so `./gradlew :app:assembleDebug` is the
preferred entry point.

## Status

The app packages the Swift gallery host in the debug APK. It renders the
interactive gallery on the device.

The host library that the app consumes provides these capabilities:

- Rendering into a retained bitmap with damage-row repaints, and a bounded
  cache of decoded image bitmaps. The decoder still rebuilds its cell objects
  for every frame.
- The converged `web-surface` wire decoder, including delta frames.
- Committed-text input from the soft keyboard, hardware keys, touch taps and
  drags, and wheel scrolling.
- System clipboard plumbing: paste as a bracketed paste, and copy requested by
  the app.
- Hyperlink taps, opened through the Compose `UriHandler`. Key activation of a
  focused link opens nothing.
- A virtual accessibility hierarchy that sends focus, activation, adjustment,
  and text-edit actions to the runtime.

These gaps remain:

- IME marked-text (pre-edit) composition. Only committed text reaches the
  runtime.
- Content URI (`content://`) imports.
- `x86_64` packaging. The app is `arm64-v8a` only.

The evidence differs by capability. Passing JVM tests and a successful APK
build are not device evidence.

- The connected journey in [Test](#test) covers rendering, touch,
  hardware-key filtering, a state-changing repaint, tab retention, the virtual
  accessibility nodes, and image alpha on an arm64 emulator. No CI job runs it.
- `AndroidLinkActivationJourneyTest` covers a hyperlink tap on the same kind of
  emulator: one `ACTION_VIEW` intent with the exact destination, nothing for a
  press dragged off the link, and a usable app after a refused intent.
- The clipboard bridge has unit tests in `swift-tui` and `swift-tui-android`.
  No connected run in this app covers a copy or a paste.
- No TalkBack run has verified the accessibility actions.

## Test

The Swift package declares the `GalleryAndroidHost` dynamic library, and the
Android app adds a connected `androidTest` journey around that public host. The
journey launches the real gallery, verifies its first frame and semantic
presentation, dispatches touch and hardware-keyboard input, observes a
state-changing repaint, switches tabs and verifies retained counter state, and
checks the embedded PNG's transparent pixels against the rendered surface.

With an arm64 emulator or device online, run:

```bash
ANDROID_HOME="$HOME/Library/Android/sdk" \
./gradlew :app:connectedDebugAndroidTest
```

The test reads the virtual accessibility nodes published by the Android host,
checks their roles and actions, and compares their screen bounds with the public
Swift frame. Compose supplies the rendering surface and focused text input.
The assertions do not originate from TalkBack or another assistive technology. Manual TalkBack observation remains a separate device check.

A second journey, `AndroidLinkActivationJourneyTest`, follows a gallery `Link`
to Android. It finds the link's hyperlink cells in the public frame, taps them,
and checks that the host starts exactly one `ACTION_VIEW` intent carrying the
link's exact destination. An instrumentation activity monitor stands in for the
installed handler, so the journey observes the real intent without leaving the
app. It then checks that a press dragged off the link starts nothing, and that
an intent the platform refuses for lack of a handler leaves the gallery
responding to touch.

Hardware character events reach the focused command-palette filter. Hardware
Enter in that filter reaches the runtime as Return and submits the selected
command. The connected journey does not use Enter: it proves hardware filtering
and repaint, then activates the exact filtered semantic command with a physical
touch.

## See also

- [`swift-tui-counter-demo`](https://github.com/SwiftTUI/swift-tui-counter-demo): the browser/WASI counter demo (own repo).
- DocC reference: https://swifttui.sh/docs/documentation/
