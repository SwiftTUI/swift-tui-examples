# Sextant

Sextant is a preview-first terminal inspector for files and directories. It
opens text, hexadecimal, metadata, and directory-summary previews without
optional tools. It can use richer external previewers when they are available.

Sextant is read-only: it navigates and inspects, then hands files to the system
opener or your editor. It does not create, rename, move, or delete files.

![Sextant inspecting its README with a built-in preview](docs/assets/sextant.png)

Watch the [short terminal journey](docs/assets/sextant-journey.gif) for preview
focus, generated help, and the command palette.

## Run from source

Sextant currently incubates in `swift-tui-examples`:

```bash
swiftly run swift run --package-path sextant sextant [PATH]
```

`PATH` can be a file or directory. Its default is the current directory. A file
opens its parent directory and selects that file.

```text
sextant [PATH]
  --hidden
  --sort <name|modified|size>
  --preview <auto|built-in|external|off>
  --no-watch
  --config <PATH>
```

The command also provides `--help`, `--version`, and shell-completion
print/install subcommands through SwiftTUI's command surface.

## What works without extra software

- Strict UTF-8 and BOM-aware UTF-8/UTF-16 text previews.
- Bounded hexadecimal previews for binary files.
- Metadata for each selection.
- Summaries for loaded directories.
- Separate states for loading, empty, stale, denied, missing, unsupported, and
  generic failures.
- Local filters and bounded recursive filename search.
- Hidden-file and sort controls.
- Live directory refresh on macOS.
- Responsive layouts with one, two, or three surfaces.

Built-in reads are capped at 256 KiB plus one sentinel byte. Binary output is
capped at 4 KiB. Sextant refuses special/device-file content reads.

## Optional preview enhancements

Sextant examines the launch `PATH` once. It can use `glow`, `jq`, `chafa`,
`unzip`, `tar`, or `bat`. If a tool is absent or fails, Sextant uses the
built-in preview. It passes paths as argv elements and does not add them to
shell source. Preview replacement waits for the previous child to exit.

## Controls

Press `?` in the app for generated help or `:` for the command palette. The
checked-in [key-binding reference](docs/KEYBINDINGS.md) is generated from the
same `CommandCatalog` used for key dispatch.

Highlights:

- Use arrows or `h/j/k/l` to navigate.
- Use `→` or `l` to enter the selected directory. These keys do nothing on a
  file.
- Press Return to focus a file preview or enter a selected directory.
- Use `←` or `h` to go up. You can go above the launch directory.
- Press Tab to move focus between the browser and preview. Press Escape to
  leave an embedded preview.
- Press `/` to filter the active directory from the status bar.
- Press `s` to search filenames recursively. If you enter a path, it moves to
  that path.
- Press `.` to toggle hidden files. Press `r` to refresh.
- Press `o`, `e`, or `R` to open, edit, or reveal the item.
- Press `y` or `Y` to copy the absolute or root-relative path.
- Press `q` or Ctrl-D to exit.

## Configuration and state

Configuration is versioned JSON at
`$XDG_CONFIG_HOME/sextant/config.json`. If the configuration environment
variable is not set, the path is `~/.config/sextant/config.json`. State is
stored separately at `$XDG_STATE_HOME/sextant/state.json`. If the state
environment variable is not set, the path is
`~/.local/state/sextant/state.json`.

Configuration covers default hidden/sort/watch policy, key declarations,
colors, editor argv, and external-preview argv templates. External templates
must contain `{path}` as a standalone argv element and cannot execute inline
shell source. The runtime-owned `application.quit` binding is fixed at `q` and
Ctrl-D. The configuration rejects overrides of this binding. CLI flags
override applicable configuration defaults.

Each adapter versions its external-preview content rules independently. These
rules can limit content types and input size. If an adapter is unavailable or
fails, the app retains the built-in preview:

```json
{
  "id": "small-binary",
  "displayName": "Small binary viewer",
  "executable": "viewer",
  "arguments": ["--", "{path}"],
  "rulesVersion": 1,
  "contentKinds": ["binary"],
  "maximumByteCount": 1048576
}
```

## Build and test

```bash
swiftly run swift build --package-path sextant
swiftly run swift build -c release --package-path sextant
swiftly run swift test --package-path sextant
```

The suite includes deterministic tests for the model, filesystem, and
processes. It also includes 10,000-entry budgets. A production-async real-PTY
journey covers input, resize, preview replacement, focus transfer, and shutdown
without child processes.

See [architecture](docs/ARCHITECTURE.md) and
[development](docs/DEVELOPMENT.md) for the current implementation.

## Privacy, security, and support

Sextant performs local filesystem reads and launches only configured or
built-in argv-based commands. It does not send file content over the network.
External tools have their own behavior. Configure them with the same care as an
editor.

The v0.1 support target is macOS 15 or newer. Linux remains build-tested where
the SwiftTUI dependencies permit it but is not a distribution promise.

## See also

- [API reference](https://swifttui.sh/docs/documentation/) — the SwiftTUI DocC docs.
- [Showcase](https://swifttui.sh/showcase/) — Sextant and the other examples on the website.
- [swift-tui](https://github.com/SwiftTUI/swift-tui) — the framework repository.
