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
- Swift 6.3.0 available through `swiftly`.
- Swift Android SDK bundle `swift-6.3-RELEASE_android`.
- `ANDROID_NDK_HOME` pointing at the Swift Android bundle's NDK r27d.

The local command verified on 2026-06-09 was:

```bash
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
ANDROID_HOME="$HOME/Library/Android/sdk" \
ANDROID_NDK_HOME="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d" \
gradle :app:assembleDebug
```

The Gradle wrapper is committed. In this local run, `./gradlew` was blocked
before configuration by repeated `services.gradle.org` distribution download
timeouts; the system Gradle 9.5.1 command above completed successfully.

## Runtime

The first runtime smoke test needs an attached `arm64-v8a` Android device or a
configured AVD. At the time this README was added, `adb devices -l` returned no
attached devices and `emulator -list-avds` returned no configured AVDs.

Before treating the demo as runnable, verify that it opens, paints nonblank
gallery content, accepts basic input, and survives switching across gallery
tabs.
