plugins {
  `kotlin-dsl`
}

// Hosts the SwiftTUI Android convention plugin (id: "sh.swifttui.android"),
// which wires the per-app Swift -> .so cross-build + jniLibs merge so consumers
// apply it instead of pasting build logic. Pure Gradle API — no AGP dependency
// (the app keeps its own `android {}` jniLibs source set; the plugin only owns
// the Swift build tasks and the preBuild wiring).
