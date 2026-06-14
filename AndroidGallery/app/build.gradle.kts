plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.plugin.compose")
  id("sh.swifttui.android")
}

val ndkVersionPin = "27.3.13750724"
val androidSdkDir = providers.environmentVariable("ANDROID_HOME")
  .orElse(providers.environmentVariable("ANDROID_SDK_ROOT"))
  .orElse(providers.systemProperty("user.home").map { "$it/Library/Android/sdk" })
// Only used to strip the packaged prebuilt `.so`s; gate on NDK presence so a
// JVM-only `testDebugUnitTest` gate can run without it.
val ndkAvailable = androidSdkDir.map { file("$it/ndk/$ndkVersionPin").exists() }

// Populated by the sh.swifttui.android convention plugin's copySwiftAndroidLibraries.
val generatedJniLibsDir = layout.buildDirectory.dir("generated/swiftJniLibs")

android {
  namespace = "org.swifttui.gallery.android"

  compileSdk {
    version = release(36) {
      minorApiLevel = 1
    }
  }

  if (ndkAvailable.get()) {
    ndkVersion = ndkVersionPin
  }

  defaultConfig {
    applicationId = "org.swifttui.gallery.android"
    minSdk = 28
    targetSdk = 36
    versionCode = 1
    versionName = "0.1.0"

    ndk {
      // arm64-v8a only — keep in sync with the host library's Application.mk.
      // The framework and its image path also cross-compile for
      // x86_64-unknown-linux-android28, so this is a deliberate packaging scope
      // choice, not a limitation. To add an x86_64 lane (e.g. a CI emulator),
      // add the ABI here, in :swift-tui-host's Application.mk, and give the
      // convention plugin a second --swift-sdk cross-build + per-ABI copy.
      abiFilters += "arm64-v8a"
    }
  }

  // The JNI shim (libswift_tui_jni.so) ships in the :swift-tui-host AAR. This app
  // contributes only the per-app Swift host `.so` + Swift runtime, which the
  // convention plugin writes here.
  sourceSets["main"].jniLibs.srcDir(generatedJniLibsDir.get().asFile)

  buildFeatures {
    compose = true
  }

  packaging {
    jniLibs {
      useLegacyPackaging = true
    }
  }

  testOptions {
    unitTests {
      isIncludeAndroidResources = false
    }
  }
}

// The one per-app Swift artifact: which SwiftPM product to cross-build. Its
// output (libGalleryAndroidHost.so) is renamed to the canonical
// libswift_tui_app_host.so on the way into jniLibs.
swiftTuiAndroidHost {
  productName = "GalleryAndroidHost"
  additionalSwiftSources.from(layout.projectDirectory.dir("../../gallery"))
}

dependencies {
  implementation(project(":swift-tui-host"))

  implementation(platform("androidx.compose:compose-bom:2026.05.01"))
  implementation("androidx.activity:activity-compose:1.13.0")
  implementation("androidx.compose.foundation:foundation")
  implementation("androidx.compose.ui:ui")
  implementation("androidx.compose.ui:ui-graphics")
  implementation("androidx.compose.ui:ui-tooling-preview")

  debugImplementation("androidx.compose.ui:ui-tooling")
}
