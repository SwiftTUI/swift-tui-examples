plugins {
  id("com.android.library")
  id("org.jetbrains.kotlin.plugin.compose")
}

val userHome = providers.systemProperty("user.home").get()
val androidSdkDir = providers.environmentVariable("ANDROID_HOME")
  .orElse(providers.environmentVariable("ANDROID_SDK_ROOT"))
  .orElse("$userHome/Library/Android/sdk")
val ndkVersionPin = "27.3.13750724"

// The JNI shim is pure C++17 (NDK only — no Swift toolchain). Gate the native
// build on NDK presence so a JVM-only `testDebugUnitTest` gate can configure and
// run without it, mirroring the app's `swiftAndroidToolingAvailable` gate.
val ndkAvailable = androidSdkDir.map { file("$it/ndk/$ndkVersionPin").exists() }

android {
  namespace = "sh.swifttui.android.host"

  compileSdk {
    version = release(36) {
      minorApiLevel = 1
    }
  }

  if (ndkAvailable.get()) {
    ndkVersion = ndkVersionPin
  }

  defaultConfig {
    minSdk = 28

    ndk {
      // arm64-v8a only — keep in sync with src/main/jni/Application.mk. See the
      // app's defaultConfig.ndk for why arm64 is the only packaged ABI and what
      // to change to add another (e.g. x86_64 for a CI emulator lane).
      abiFilters += "arm64-v8a"
    }

    consumerProguardFiles("consumer-rules.pro")
  }

  if (ndkAvailable.get()) {
    externalNativeBuild {
      ndkBuild {
        path = file("src/main/jni/Android.mk")
      }
    }
  }

  buildFeatures {
    compose = true
  }

  testOptions {
    unitTests {
      isIncludeAndroidResources = false
    }
  }
}

dependencies {
  // `api` for the Compose types that appear in this library's public surface
  // (e.g. `Modifier` on SwiftTUIHostView); `implementation` for the rest.
  api(platform("androidx.compose:compose-bom:2026.05.01"))
  api("androidx.compose.ui:ui")
  implementation("androidx.compose.foundation:foundation")
  implementation("androidx.compose.ui:ui-graphics")

  testImplementation("junit:junit:4.13.2")
  // The real org.json, shadowing the stubbed android.jar copy so the frame
  // parser can be exercised in plain JVM unit tests.
  testImplementation("org.json:json:20231013")
}
