pluginManagement {
  repositories {
    google()
    mavenCentral()
    gradlePluginPortal()
    // The sh.swifttui.android plugin — served from GitHub Pages until the
    // Gradle Plugin Portal graduation.
    maven { url = uri("https://swifttui.github.io/swift-tui-android") }
  }
}

dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    google()
    mavenCentral()
    // The sh.swifttui:android-host AAR — served from GitHub Pages until the
    // Maven Central graduation.
    maven { url = uri("https://swifttui.github.io/swift-tui-android") }
  }
}

rootProject.name = "SwiftTUIGalleryAndroid"
include(":app")

