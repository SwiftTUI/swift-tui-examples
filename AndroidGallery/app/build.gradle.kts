import java.io.File
import java.nio.file.Files

plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.plugin.compose")
}

val swiftSdkName = "aarch64-unknown-linux-android28"
val swiftToolchainVersion = "+6.3.1"
val swiftSdkArtifactName = "swift-6.3.2-RELEASE_android"
val swiftTuiDependencyUrl = "https://github.com/SwiftTUI/swift-tui.git"
val swiftPackageDir = layout.projectDirectory.dir("../SwiftPackage")
val swiftBuildOutputDir = swiftPackageDir.dir(".build/$swiftSdkName/debug")
val generatedJniLibsDir = layout.buildDirectory.dir("generated/swiftJniLibs")
val generatedSwiftSdksDir = layout.buildDirectory.dir("swift-sdks")

val userHome = providers.systemProperty("user.home").get()
val defaultSwiftSdkBundleDir =
  "$userHome/Library/org.swift.swiftpm/swift-sdks/$swiftSdkArtifactName.artifactbundle"
val swiftSdkBundleDir = providers.environmentVariable("SWIFT_ANDROID_SDK_BUNDLE")
  .orElse(defaultSwiftSdkBundleDir)
val swiftTuiCheckoutDir = providers.environmentVariable("SWIFTTUI_CHECKOUT")
  .orElse(layout.projectDirectory.dir("../../../swift-tui").asFile.absolutePath)
val defaultSwiftAndroidRoot = swiftSdkBundleDir.map { "$it/swift-android" }
val defaultAndroidNdkDir =
  "$userHome/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android/android-ndk-r27d"
val swiftAndroidRoot = providers.environmentVariable("SWIFT_ANDROID_ROOT")
  .orElse(defaultSwiftAndroidRoot)
val swiftAndroidNdkDir = providers.environmentVariable("ANDROID_NDK_HOME")
  .orElse(providers.environmentVariable("ANDROID_NDK_ROOT"))
  .orElse(defaultAndroidNdkDir)
val swiftRuntimeLibDir = swiftAndroidRoot.map {
  file("$it/swift-resources/usr/lib/swift-aarch64/android")
}
val ndkHostTag = providers.provider {
  val osName = System.getProperty("os.name").lowercase()
  when {
    osName.contains("mac") -> "darwin-x86_64"
    osName.contains("linux") -> "linux-x86_64"
    osName.contains("windows") -> "windows-x86_64"
    else -> error("Unsupported NDK host OS: ${System.getProperty("os.name")}")
  }
}
val ndkCxxSharedLib = swiftAndroidNdkDir.zip(ndkHostTag) { ndkDir, hostTag ->
  file("$ndkDir/toolchains/llvm/prebuilt/$hostTag/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so")
}

fun swiftPackageMirrorUrl(checkout: File): String {
  val dotGit = checkout.resolve(".git")
  if (!dotGit.isFile) {
    return checkout.canonicalFile.toPath().toUri().toString()
  }

  val marker = "gitdir:"
  val pointer = dotGit.readText().trim()
  if (!pointer.startsWith(marker)) {
    return checkout.canonicalFile.toPath().toUri().toString()
  }

  val gitDir = pointer.removePrefix(marker).trim()
  return checkout.resolve(gitDir).canonicalFile.toPath().toUri().toString()
}

val prepareSwiftSdkSearchPath = tasks.register("prepareSwiftSdkSearchPath") {
  description = "Creates a generated Swift SDK search path containing only the configured Android SDK."
  group = "build"

  inputs.dir(swiftSdkBundleDir.map { file(it) })
  outputs.dir(generatedSwiftSdksDir)

  doLast {
    val searchDir = generatedSwiftSdksDir.get().asFile
    val bundleLink = searchDir.resolve("$swiftSdkArtifactName.artifactbundle")
    project.delete(bundleLink)
    searchDir.mkdirs()
    Files.createSymbolicLink(
      bundleLink.toPath(),
      file(swiftSdkBundleDir.get()).toPath()
    )
  }
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

val configureSwiftPackageMirrors = tasks.register<Exec>("configureSwiftPackageMirrors") {
  description = "Mirrors the public SwiftTUI dependency to a local checkout when available."
  group = "build"

  onlyIf {
    val checkout = file(swiftTuiCheckoutDir.get())
    if (!checkout.isDirectory) {
      logger.lifecycle("No local SwiftTUI checkout found at $checkout; using public dependency.")
      false
    } else {
      true
    }
  }

  commandLine(
    "swiftly",
    "run",
    "swift",
    "package",
    "--package-path",
    swiftPackageDir.asFile.absolutePath,
    "config",
    "set-mirror",
    "--original",
    swiftTuiDependencyUrl,
    "--mirror",
    swiftPackageMirrorUrl(file(swiftTuiCheckoutDir.get()))
  )
}

val buildSwiftAndroid = tasks.register<Exec>("buildSwiftAndroid") {
  description = "Builds the Swift gallery host as an Android arm64 dynamic library."
  group = "build"
  dependsOn(configureSwiftPackageMirrors, prepareSwiftSdkSearchPath)

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
    "--swift-sdks-path",
    generatedSwiftSdksDir.get().asFile.absolutePath,
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
  from(ndkCxxSharedLib) {
    include("libc++_shared.so")
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
