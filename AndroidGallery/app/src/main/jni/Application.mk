# arm64-v8a only — keep in sync with app/build.gradle.kts
# (defaultConfig.ndk.abiFilters), which documents why arm64 is the only packaged
# ABI and what to change to add another (e.g. x86_64 for a CI emulator lane).
APP_ABI := arm64-v8a
APP_PLATFORM := android-28
APP_STL := c++_static

