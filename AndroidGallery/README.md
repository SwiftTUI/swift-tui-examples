# Android Gallery

Embed the SwiftTUI gallery in an Android Compose host — the Android surface of the same App, running on a native Android surface (Jetpack Compose via `SwiftTUIAndroidHost`).

## Run

```bash
./gradlew :app:assembleDebug
```

Run from this directory. The roster uses the `(cd AndroidGallery && ./gradlew :app:assembleDebug)` form from the repo root — same command.

## Demonstrates

- `SwiftTUIAndroidHost` — which means the same SwiftTUI `App` renders on a native Android surface, with no platform-specific view code in the gallery itself.
- A Compose `SwiftTUIHostView` measures available pixels, converts them to a terminal cell grid, and publishes resize information back to SwiftTUI — so layout follows the device viewport.
- The Compose renderer paints styled cells, cell backgrounds, text decorations, and embedded image payloads on an Android Canvas, with a transparent semantics overlay above the canvas for Android accessibility — driven entirely by the host's versioned JSON snapshot.
- Hardware keyboard input and basic touch activation bridge back to SwiftTUI, so the gallery is interactive on-device.

## How it works

The app builds the Swift gallery host package (`GalleryAndroidHost`, which depends on `GalleryDemoViews`, `SwiftTUIAndroidHost`, and `SwiftTUIRuntime`) as an `arm64-v8a` Android dynamic library, copies the Swift Android runtime libraries into generated `jniLibs`, and uses a small JNI shim to drive the `SwiftTUIAndroidHost` C ABI from Kotlin.

The first screen is a Compose `SwiftTUIHostView` backed by a native Swift host handle. The Android host frame parser consumes the versioned JSON snapshot emitted by `SwiftTUIAndroidHost`; the current schema carries terminal colors, raster cells, cell styles, ranged damage metadata, image attachments, accessibility nodes, accessibility announcements, focus presentation, and preferred layout size.

The demo is packaged only for `arm64-v8a`, but the framework also cross-compiles for `x86_64-unknown-linux-android28` — this is a deliberate packaging-scope choice, not a limitation. To add an `x86_64` lane (e.g. a CI emulator), add the ABI in `app/build.gradle.kts`, in `:swift-tui-host`'s `Application.mk`, and give the convention plugin a second `--swift-sdk` cross-build with a per-ABI copy.

## Build

Prerequisites:

- Android Studio / Android SDK with Android SDK Platform 36.1.
- Swift 6.3.1 available through `swiftly`.
- Swift Android SDK bundle `swift-6.3.2-RELEASE_android`.
- `ANDROID_NDK_HOME` pointing at an Android NDK r27d or newer. The local
  fallback is the r27d NDK bundled with `swift-6.3-RELEASE_android`.

After installing the 6.3.2 Swift Android SDK, materialize its `ndk-sysroot` once:

```bash
ANDROID_NDK_HOME="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d" \
"$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh"
```

The Gradle build creates a generated `app/build/swift-sdks` search path that
contains only the configured `swift-6.3.2-RELEASE_android` bundle before calling
SwiftPM. If the bundle is not in the default SwiftPM SDK directory, set
`SWIFT_ANDROID_SDK_BUNDLE` to the `.artifactbundle` path.

The Swift package manifest uses a public HTTPS SwiftTUI dependency. During
org-root development, Gradle mirrors that URL to `SWIFTTUI_CHECKOUT` or the
default sibling checkout at `../../../swift-tui` so pre-release Android host
changes build against the pinned local checkout.

A fully env-prefixed local invocation (useful when the SDK/NDK are not on the
default paths):

```bash
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
ANDROID_HOME="$HOME/Library/Android/sdk" \
ANDROID_NDK_HOME="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d" \
SWIFT_ANDROID_SDK_BUNDLE="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle" \
SWIFT_ANDROID_ROOT="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle/swift-android" \
gradle :app:assembleDebug
```

The Gradle wrapper is committed, so `./gradlew :app:assembleDebug` is the
preferred entry point.

## Status

The app assembles and packages the Swift gallery host into the debug APK and renders the interactive gallery on-device. IME composition, clipboard, link opening, Android accessibility focus synchronization, Android content URI import, and retained bitmap damage caches remain follow-up work.

## Test

No test target. (The host `SwiftPackage` declares only the `GalleryAndroidHost` dynamic library; build verification runs through Gradle.)

## See also

- [`../WebExample`](../WebExample) — the browser/WASI surface of the SwiftTUI gallery.
- DocC reference: https://swifttui.sh/docs/documentation/
