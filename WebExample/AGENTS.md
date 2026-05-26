# AGENTS.md

Guidance for agentic assistants working in **WebExample**. Keep this concise;
[`README.md`](README.md) is the full reference.

## What this is

The **reference embedding pattern** for SwiftTUI in a Bun-served browser app. A
real SwiftTUI `App` is built for WASI and mounted onto a canvas via
`@swifttui/web` — there is **no terminal-emulator dependency**. The public
website iframes this as the live demo; keep this package small and focused on
the embedding contract.

Two cooperating parts:

- **`TerminalApp/`** — a Swift package: a reusable `WebExampleScenes` library +
  a thin `WebExampleApp` executable that calls `WASIRunner.run(...)`.
- **`src/`** — a Bun host that runs the Swift WASI build, serves the artifacts
  with COOP/COEP headers, and mounts `WebHost`. The load-bearing bootstrap is
  ~60 lines in [`src/frontend.ts`](src/frontend.ts).

Depends on `@swifttui/web` and `@swifttui/build`. Pre-public source checkouts
may use workspace deps, but the public cutover should use npm versions or
public release tarballs.

## Toolchains

- **Bun** for the web app, bundler, and test runner.
- **`swiftly`** Swift 6.3.1 + the `swift-6.3.1-RELEASE_wasm` SDK for the WASI
  build. Use `swiftly run swift ...`, not bare `swift`.

## Commands

```bash
bun install            # workspace install (root preferred, but works here)
bun dev                # build TerminalApp wasm/manifest, then serve
bun run build          # dist/ (web) + pages-dist/ (web + TerminalApp/dist)
bun run start          # serve a production build
bun test               # unit tests
bun run test:browser   # Playwright browser-integration specs (*.browser.ts)
```

## Gotchas

- **WASI build flags are load-bearing.** The release build needs
  `-Xswiftc -Osize` **plus**
  `-Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass`. Plain `-O`
  (and on some Darwin runners even plain `-Osize`) emits merged outlined copy
  helpers whose signatures exceed the browser WebAssembly API's 1000-parameter
  limit, causing `WebAssembly.Module doesn't parse` at startup. The canonical
  command lives in the build script (`src/build-terminal.ts` / `TerminalApp`).
- **COOP/COEP headers are required.** The host must serve
  `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp` so `SharedArrayBuffer`-backed
  stdin works. HMR is disabled — refresh after frontend edits.

## Conventions

`AGENTS.md` is the real file; `CLAUDE.md` is a symlink to it. Edit `AGENTS.md`.
See the SwiftTUI package `docs/DEVELOPMENT.md` for the full
toolchain/environment story.
