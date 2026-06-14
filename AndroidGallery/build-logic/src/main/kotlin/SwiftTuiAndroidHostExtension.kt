import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.Property

/**
 * Configuration for the `sh.swifttui.android` convention plugin.
 *
 * A consumer applies the plugin and sets [productName]; everything else has a
 * convention. The plugin cross-builds the named SwiftPM product for Android
 * arm64 and copies it (renamed to `lib<hostLibraryName>.so`) plus the Swift
 * runtime into the app's generated jniLibs.
 */
interface SwiftTuiAndroidHostExtension {
  /** The SwiftPM product to build; its output is `lib<productName>.so`. Required. */
  val productName: Property<String>

  /**
   * Canonical packaged library name (without `lib`/`.so`) the host library's
   * JNI shim dlopen()s. Defaults to `swift_tui_app_host`; overridable per the
   * D2 decision so the on-device name is not pinned to any one product name.
   */
  val hostLibraryName: Property<String>

  /** The SwiftPM package directory to build. Defaults to `../SwiftPackage`. */
  val packageDirectory: DirectoryProperty

  /** Local swift-tui checkout used to mirror the public dependency during dev. */
  val swiftTuiCheckout: DirectoryProperty

  /** Extra Swift source roots to track for incremental rebuilds (e.g. sibling view packages). */
  val additionalSwiftSources: ConfigurableFileCollection
}
