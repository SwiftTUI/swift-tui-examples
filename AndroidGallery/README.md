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
  embedded images on an Android Canvas. A transparent semantics overlay adds
  Android accessibility. The host versioned JSON snapshot supplies all data.
- Hardware keyboard input and basic touch activation connect to SwiftTUI, so
  the gallery is interactive on the device.

## How it works

The app builds `GalleryAndroidHost` as an `arm64-v8a` Android dynamic library.
This package depends on `GalleryDemoViews`, `SwiftTUIAndroidHost`, and
`SwiftTUIRuntime`. The build copies the Swift Android runtime libraries into
generated `jniLibs`. A small JNI shim connects Kotlin to the
`SwiftTUIAndroidHost` C ABI.

The first screen is a Compose `SwiftTUIHostView` with a native Swift host
handle. The Android frame parser consumes a versioned JSON snapshot from
`SwiftTUIAndroidHost`. The schema contains terminal colors, raster cells, cell
styles, damage metadata, and image attachments. It also contains accessibility
nodes, announcements, focus presentation, and the preferred layout size.

The demo package supports only `arm64-v8a`. The framework also cross-compiles
for `x86_64-unknown-linux-android28`. This difference is a package-scope choice,
not a framework limitation. To add an `x86_64` lane:

1. Add the ABI to `app/build.gradle.kts`.
2. Add the ABI to the `:swift-tui-host` `Application.mk`.
3. Add a second `--swift-sdk` cross-build to the convention plugin.
4. Copy the output for each ABI.

## Build

Prerequisites:

- Install Android Studio and Android SDK Platform 36.1.
- Install Swift 6.3.3 through `swiftly`.
- Install the Swift Android SDK bundle `swift-6.3.3-RELEASE_android`.
- Set `ANDROID_NDK_HOME` to an Android NDK r27d or newer. The local
  fallback is the r27d NDK bundled with `swift-6.3-RELEASE_android`.

After installing the 6.3.3 Swift Android SDK, materialize its `ndk-sysroot` once:

```bash
ANDROID_NDK_HOME="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d" \
"$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh"
```

The Gradle build creates the `app/build/swift-sdks` search path before it calls
SwiftPM. This path contains only the configured
`swift-6.3.3-RELEASE_android` bundle. If the bundle is not in the default
SwiftPM SDK directory, set
`SWIFT_ANDROID_SDK_BUNDLE` to the `.artifactbundle` path.

The Swift package manifest uses a public HTTPS SwiftTUI dependency.
Pre-release integration against a local framework checkout happens in the
SwiftTUI coordination root, not here.

If the SDK and NDK are not on the default paths, use this command:

```bash
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
ANDROID_HOME="$HOME/Library/Android/sdk" \
ANDROID_NDK_HOME="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d" \
SWIFT_ANDROID_SDK_BUNDLE="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle" \
SWIFT_ANDROID_ROOT="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android" \
gradle :app:assembleDebug
```

The Gradle wrapper is committed, so `./gradlew :app:assembleDebug` is the
preferred entry point.

## Status

The app packages the Swift gallery host in the debug APK. It renders the
interactive gallery on the device. The app does not yet support IME
composition, the clipboard, or link opening. It also lacks accessibility-focus
synchronization, content URI imports, and retained bitmap damage caches.

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

The automated semantics assertions verify the Android accessibility tree that
Compose presents. They do not originate from TalkBack or another assistive
technology. Manual TalkBack observation remains a separate device check.

Hardware character events reach the focused command-palette filter, but the
current Compose text-input sink treats hardware Enter as a multiline newline
instead of forwarding it as palette submission. The connected journey records
that preview limitation explicitly: it proves hardware filtering and repaint,
then activates the exact filtered semantic command with a physical touch.

## See also

- [`swift-tui-counter-demo`](https://github.com/SwiftTUI/swift-tui-counter-demo): the browser/WASI counter demo (own repo).
- DocC reference: https://swifttui.sh/docs/documentation/
