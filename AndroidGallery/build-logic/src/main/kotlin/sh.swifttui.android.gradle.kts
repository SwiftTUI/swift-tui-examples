import java.io.File
import java.nio.file.Files

// SwiftTUI Android convention plugin. Owns the per-app Swift -> arm64 `.so`
// cross-build, the Swift-SDK search path, the dev dependency mirror, and the
// jniLibs copy (renaming the product to the canonical host library name). The
// app applies `id("sh.swifttui.android")` instead of pasting these tasks.

val hostConfig = extensions.create("swiftTuiAndroidHost", SwiftTuiAndroidHostExtension::class.java)
hostConfig.hostLibraryName.convention("swift_tui_app_host")
hostConfig.packageDirectory.convention(layout.projectDirectory.dir("../SwiftPackage"))
hostConfig.swiftTuiCheckout.convention(layout.projectDirectory.dir("../../../swift-tui"))

val swiftSdkName = "aarch64-unknown-linux-android28"
val swiftToolchainVersion = "+6.3.1"
val swiftSdkArtifactName = "swift-6.3.2-RELEASE_android"
val swiftTuiDependencyUrl = "https://github.com/SwiftTUI/swift-tui.git"
val swiftBuildSubpath = ".build/$swiftSdkName/debug"
val generatedJniLibsDir = layout.buildDirectory.dir("generated/swiftJniLibs")
val generatedSwiftSdksDir = layout.buildDirectory.dir("swift-sdks")

val userHome = providers.systemProperty("user.home").get()
val defaultSwiftSdkBundleDir =
  "$userHome/Library/org.swift.swiftpm/swift-sdks/$swiftSdkArtifactName.artifactbundle"
val swiftSdkBundleDir = providers.environmentVariable("SWIFT_ANDROID_SDK_BUNDLE")
  .orElse(defaultSwiftSdkBundleDir)
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

// True only when both the Android NDK and the Swift Android SDK bundle are
// present. When false the native Swift build is skipped so a JVM-only
// `testDebugUnitTest` gate can configure and run without them.
val swiftAndroidToolingAvailable = providers.provider {
  file(swiftAndroidNdkDir.get()).exists() && file(swiftSdkBundleDir.get()).exists()
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

val configureSwiftPackageMirrors = tasks.register<Exec>("configureSwiftPackageMirrors") {
  description = "Mirrors the public SwiftTUI dependency to a local checkout when available."
  group = "build"

  val packageDir = hostConfig.packageDirectory.get().asFile
  val checkout = hostConfig.swiftTuiCheckout.get().asFile

  onlyIf {
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
    packageDir.absolutePath,
    "config",
    "set-mirror",
    "--original",
    swiftTuiDependencyUrl,
    "--mirror",
    swiftPackageMirrorUrl(checkout)
  )
}

val buildSwiftAndroid = tasks.register<Exec>("buildSwiftAndroid") {
  description = "Builds the configured Swift host product as an Android arm64 dynamic library."
  group = "build"

  val packageDir = hostConfig.packageDirectory.get().asFile
  val product = hostConfig.productName.get()

  // Skip (rather than fail) when the Android NDK or Swift Android SDK bundle is
  // absent, so a JVM-only `testDebugUnitTest` gate can run without them.
  onlyIf {
    val available = swiftAndroidToolingAvailable.get()
    if (!available) {
      logger.lifecycle(
        "Skipping Swift Android build: NDK or Swift Android SDK bundle not found. " +
          "The APK will lack the Swift host library; unit tests are unaffected."
      )
    }
    available
  }
  dependsOn(configureSwiftPackageMirrors, prepareSwiftSdkSearchPath)

  inputs.files(fileTree(packageDir) {
    include("Package.swift")
    include("Sources/**/*.swift")
  })
  inputs.files(hostConfig.additionalSwiftSources)
  inputs.files(fileTree(hostConfig.swiftTuiCheckout.get()) {
    include("Package.swift")
    include("Sources/**/*.swift")
    include("Platforms/Android/**/*.swift")
    include("Vendor/swift-figlet/**/*.swift")
  })
  outputs.file(File(packageDir, "$swiftBuildSubpath/lib$product.so"))

  environment("DISABLE_EXPLICIT_PLATFORMS", "1")
  environment("ANDROID_NDK_HOME", swiftAndroidNdkDir.get())
  commandLine(
    "swiftly",
    "run",
    "swift",
    "build",
    swiftToolchainVersion,
    "--package-path",
    packageDir.absolutePath,
    "--swift-sdks-path",
    generatedSwiftSdksDir.get().asFile.absolutePath,
    "--swift-sdk",
    swiftSdkName,
    "--product",
    product
  )
}

// Sync (not Copy) so the generated jniLibs dir exactly mirrors the produced set:
// a renamed product (e.g. libGalleryAndroidHost.so -> libswift_tui_app_host.so)
// must not leave the old `.so` orphaned in the merged APK.
val copySwiftAndroidLibraries = tasks.register<Sync>("copySwiftAndroidLibraries") {
  description = "Syncs the Swift host product (renamed to canonical) and Swift runtime into jniLibs."
  group = "build"
  onlyIf { swiftAndroidToolingAvailable.get() }
  dependsOn(buildSwiftAndroid)

  val packageDir = hostConfig.packageDirectory.get().asFile
  val product = hostConfig.productName.get()
  val canonical = hostConfig.hostLibraryName.get()

  from(File(packageDir, swiftBuildSubpath)) {
    include("lib$product.so")
    // Standardize the per-app Swift product to the canonical name the host
    // library's JNI shim dlopen()s (D2). Decouples the on-device library name
    // from any one consumer's SwiftPM product name.
    rename("lib$product.so", "lib$canonical.so")
  }
  from(swiftRuntimeLibDir) {
    include("*.so")
  }
  from(ndkCxxSharedLib) {
    include("libc++_shared.so")
  }
  into(generatedJniLibsDir.map { it.dir("arm64-v8a") })
}

// preBuild is created by AGP; wire lazily so apply-order does not matter.
tasks.matching { it.name == "preBuild" }.configureEach {
  dependsOn(copySwiftAndroidLibraries)
}
