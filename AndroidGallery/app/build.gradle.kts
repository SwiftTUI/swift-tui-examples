plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.plugin.compose")
}

val swiftSdkName = "aarch64-unknown-linux-android28"
val swiftToolchainVersion = "+6.3.0"
val swiftPackageDir = layout.projectDirectory.dir("../SwiftPackage")
val swiftBuildOutputDir = swiftPackageDir.dir(".build/$swiftSdkName/debug")
val generatedJniLibsDir = layout.buildDirectory.dir("generated/swiftJniLibs")

val userHome = providers.systemProperty("user.home").get()
val defaultSwiftAndroidRoot =
  "$userHome/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android"
val swiftAndroidRoot = providers.environmentVariable("SWIFT_ANDROID_ROOT")
  .orElse(defaultSwiftAndroidRoot)
val swiftAndroidNdkDir = providers.environmentVariable("ANDROID_NDK_HOME")
  .orElse(providers.environmentVariable("ANDROID_NDK_ROOT"))
  .orElse(swiftAndroidRoot.map { "$it/android-ndk-r27d" })
val swiftRuntimeLibDir = swiftAndroidRoot.map {
  file("$it/swift-resources/usr/lib/swift-aarch64/android")
}

android {
  namespace = "org.swifttui.gallery.android"

  compileSdk {
    version = release(36) {
      minorApiLevel = 1
    }
  }

  ndkVersion = "27.3.13750724"
  ndkPath = swiftAndroidNdkDir.get()

  defaultConfig {
    applicationId = "org.swifttui.gallery.android"
    minSdk = 28
    targetSdk = 36
    versionCode = 1
    versionName = "0.1.0"

    ndk {
      abiFilters += "arm64-v8a"
    }
  }

  externalNativeBuild {
    ndkBuild {
      path = file("src/main/jni/Android.mk")
    }
  }

  sourceSets["main"].jniLibs.srcDir(generatedJniLibsDir.get().asFile)

  buildFeatures {
    compose = true
  }

  packaging {
    jniLibs {
      useLegacyPackaging = true
    }
  }
}

val buildSwiftAndroid = tasks.register<Exec>("buildSwiftAndroid") {
  description = "Builds the Swift gallery host as an Android arm64 dynamic library."
  group = "build"

  inputs.files(fileTree(swiftPackageDir) {
    include("Package.swift")
    include("Sources/**/*.swift")
  })
  inputs.files(fileTree(layout.projectDirectory.dir("../../gallery")) {
    include("Package.swift")
    include("Sources/**/*.swift")
  })
  inputs.files(fileTree(layout.projectDirectory.dir("../../../swift-tui")) {
    include("Package.swift")
    include("Sources/**/*.swift")
    include("Platforms/Android/**/*.swift")
    include("Vendor/swift-figlet/**/*.swift")
  })
  outputs.file(swiftBuildOutputDir.file("libGalleryAndroidHost.so"))

  environment("DISABLE_EXPLICIT_PLATFORMS", "1")
  environment("ANDROID_NDK_HOME", swiftAndroidNdkDir.get())
  commandLine(
    "swiftly",
    "run",
    "swift",
    "build",
    swiftToolchainVersion,
    "--package-path",
    swiftPackageDir.asFile.absolutePath,
    "--swift-sdk",
    swiftSdkName,
    "--product",
    "GalleryAndroidHost"
  )
}

val copySwiftAndroidLibraries = tasks.register<Copy>("copySwiftAndroidLibraries") {
  description = "Copies the Swift gallery host and Swift Android runtime libraries into jniLibs."
  group = "build"
  dependsOn(buildSwiftAndroid)

  from(swiftBuildOutputDir) {
    include("libGalleryAndroidHost.so")
  }
  from(swiftRuntimeLibDir) {
    include("*.so")
  }
  into(generatedJniLibsDir.map { it.dir("arm64-v8a") })
}

tasks.named("preBuild") {
  dependsOn(copySwiftAndroidLibraries)
}

dependencies {
  implementation(platform("androidx.compose:compose-bom:2026.05.01"))
  implementation("androidx.activity:activity-compose:1.13.0")
  implementation("androidx.compose.foundation:foundation")
  implementation("androidx.compose.ui:ui")
  implementation("androidx.compose.ui:ui-graphics")
  implementation("androidx.compose.ui:ui-tooling-preview")

  debugImplementation("androidx.compose.ui:ui-tooling")
}
