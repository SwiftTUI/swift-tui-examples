# SwiftTUI Android Gallery

This Android app embeds the SwiftTUI gallery in a Compose host view.

The app builds the Swift gallery host package as an `arm64-v8a` Android dynamic
library, copies the Swift Android runtime libraries into generated `jniLibs`,
and uses a small JNI shim to drive the `SwiftTUIAndroidHost` C ABI from Kotlin.

## Current State

The app currently assembles and packages the Swift gallery host into the debug
APK. The first screen is a Compose `SwiftTUIHostView` backed by a native Swift
host handle. Compose measures the available pixels, converts them to a terminal
cell grid, and publishes resize information back to SwiftTUI.

The renderer is intentionally minimal in this first pass: it parses the
versioned JSON frame snapshot and paints text rows on an Android Canvas. Style
runs, image attachments, animated images, pointer/touch input, IME composition,
clipboard, links, and accessibility projection are not implemented yet.

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

The local command verified on 2026-06-09 was:

```bash
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
ANDROID_HOME="$HOME/Library/Android/sdk" \
ANDROID_NDK_HOME="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d" \
SWIFT_ANDROID_SDK_BUNDLE="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle" \
SWIFT_ANDROID_ROOT="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle/swift-android" \
gradle :app:assembleDebug
```

The Gradle wrapper is committed. In the latest local run on 2026-06-09, both
the system Gradle 9.5.1 command above and `./gradlew :app:assembleDebug`
completed successfully.

## Runtime

The latest local runtime smoke test used an attached `arm64-v8a` emulator
(`sdk_gphone64_arm64`). Install and launch succeeded, the process stayed alive,
and logcat showed `libswift_tui_jni.so` loading. The first rendered screen still
remained on the startup placeholder, `Starting SwiftTUI gallery...`, rather than
painting a SwiftTUI gallery frame.

Before treating the demo as runnable, verify that it opens, paints nonblank
gallery content, accepts basic input, and survives switching across gallery
tabs.
