# SwiftTUI Android Gallery

This Android app embeds the SwiftTUI gallery in a Compose host view.

The app builds the Swift gallery host package as an `arm64-v8a` Android dynamic
library, copies the Swift Android runtime libraries into generated `jniLibs`,
and uses a small JNI shim to drive the `SwiftTUIAndroidHost` C ABI from Kotlin.

`arm64-v8a` is the only packaged ABI by deliberate choice, not a framework
limitation: the framework and its image path (`swift-png`/`JPEG`) also
cross-compile for `x86_64-unknown-linux-android28`. arm64 is preferred here
because the verification lane runs the emulator on Apple Silicon (where arm64
system images are hardware-accelerated and `x86_64` would be slow CPU-emulated)
and because real Android devices are arm64. Adding an `x86_64` lane — most
likely wanted for an `x86_64` CI emulator on Linux runners — is a packaging
change: add the ABI in `app/build.gradle.kts` and `app/src/main/jni/Application.mk`,
and extend the Swift cross-build to emit that ABI too.

## Current State

The app currently assembles and packages the Swift gallery host into the debug
APK. The first screen is a Compose `SwiftTUIHostView` backed by a native Swift
host handle. Compose measures the available pixels, converts them to a terminal
cell grid, and publishes resize information back to SwiftTUI.

The Android host frame parser consumes the versioned JSON snapshot emitted by
`SwiftTUIAndroidHost`. The current schema carries terminal colors, raster cells,
cell styles, ranged damage metadata, image attachments, accessibility nodes,
accessibility announcements, focus presentation, and preferred layout size. The
Compose renderer paints styled cells, cell backgrounds, text decorations, and
embedded image payloads on an Android Canvas, with a transparent semantics
overlay above the canvas for Android accessibility.

Hardware keyboard input and basic touch activation are bridged back to
SwiftTUI. IME composition, clipboard, link opening, Android accessibility focus
synchronization, Android content URI import, and retained bitmap damage caches
remain follow-up work.

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

The local command verified on 2026-06-10 was:

```bash
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
ANDROID_HOME="$HOME/Library/Android/sdk" \
ANDROID_NDK_HOME="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d" \
SWIFT_ANDROID_SDK_BUNDLE="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle" \
SWIFT_ANDROID_ROOT="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle/swift-android" \
gradle :app:assembleDebug
```

The Gradle wrapper is committed. In the latest local run on 2026-06-10,
`./gradlew :app:assembleDebug` completed successfully.

## Runtime

The latest local runtime smoke used the installed
`system-images;android-35;google_apis;arm64-v8a` image with a medium-phone AVD
named `SwiftTUI_AndroidGallery_api35_medium_arm64`. Keep the emulator running as
a foreground long-lived process while issuing `adb` commands from another shell;
launching it as a background job from a short-lived shell can tear it down just
after boot.

With that lane, `adb` reported `emulator-5554 booted`, APK install returned
`Success`, launching `org.swifttui.gallery.android/.MainActivity` returned
`Status: ok`, the process stayed alive, and
`/tmp/swifttui-androidgallery-api35-medium.png` showed the hosted SwiftTUI
gallery (`Logo`, `Counter`, `Life`, `Todo`, and the SwiftTUI logo art) instead
of the startup placeholder.

Before treating the demo as complete, verify that it accepts basic input and
survives switching across gallery tabs.
