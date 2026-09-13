# Compiled reload counter

Run the counter normally with its tagged framework dependency:

```sh
swiftly run swift run --package-path hot-reload HotReloadDemo
```

Press Return to increment both an integer and a Codable reference value. The
displayed generation string is an editable marker; lifecycle modifiers own one
cancellable task.

The opt-in `SWIFTTUI_HOT_RELOAD` compilation branch exports the root for the
framework's `swifttui-dev` executable. The current pinned `0.13.2` release does
not provide that executable or `HotReloadExport`; normal launches compile with
the branch disabled. Reload integration is exercised against framework HEAD
through the coordination repository's temporary source overlay. This example
does not claim a released hot-reload workflow for `0.13.2`.

With a framework build providing that API and its matching driver:

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
