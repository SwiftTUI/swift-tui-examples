# Compiled reload counter

Run the counter normally with its tagged framework dependency:

```sh
swiftly run swift run --package-path hot-reload HotReloadDemo
```

Press Return to increment both an integer and a Codable reference value. The
displayed generation string is an editable marker; lifecycle modifiers own one
cancellable task.

The opt-in `SWIFTTUI_HOT_RELOAD` compilation branch exports the root for the
framework's `swifttui-dev` executable. The pinned `0.14.0` release provides the
reload API. Build the matching driver from that framework tag:

```sh
git clone --branch 0.14.0 --depth 1 https://github.com/SwiftTUI/swift-tui.git
(cd swift-tui && swiftly run swift build --product swifttui-dev)
swift-tui/.build/debug/swifttui-dev --package-path hot-reload --product HotReloadDemo
```

If the matching driver is already on your PATH:

```sh
swifttui-dev --package-path hot-reload --product HotReloadDemo
```

Edit `GEN-000` in `Sources/HotReloadDemo/App.swift`. Compatible values replay into
fresh owners. Compiler errors keep the current app running; fixing the source
resumes compilation. Dependency changes require a restart, and 100 images is
the default limit. macOS and Linux terminal sessions are supported. Release,
WASI and native GUI hosts do not enable the reload branch.

`SWIFTTUI_RELOAD_PROBE` optionally names a lifecycle event file for process
verification; it is unused during normal interaction.

`Fidelity.swift` supplies a second root for the coordination process journey. It
exercises focus, scroll, inactive-tab counters and a deliberately non-Codable
command sink. The harness substitutes this root only in its scratch copy. The
sink resets on reload while lifecycle modifiers install fresh action handlers.
