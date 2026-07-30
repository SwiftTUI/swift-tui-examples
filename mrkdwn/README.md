# mrkdwn

`mrkdwn` is a responsive terminal Markdown reader built as an advanced
[SwiftTUI](https://github.com/SwiftTUI/swift-tui) example. It compiles
CommonMark and GitHub-flavored Markdown with
[`swift-markdown`](https://github.com/swiftlang/swift-markdown), renders
Mermaid fences with `MrkdwnMermaid` — a portable, dependency-free terminal
Mermaid renderer vendored into this example (see
[`Sources/MrkdwnMermaid/NOTICE`](Sources/MrkdwnMermaid/NOTICE) for its Apache-2.0
provenance and [`SYNTAX.md`](Sources/MrkdwnMermaid/SYNTAX.md) for the supported
diagram families) — and keeps all navigation, search, reload, and resource state
behind one observable model.

## Run it

From the `swift-tui-examples` checkout:

```bash
swiftly run swift run --package-path mrkdwn mrkdwn README.md
swiftly run swift run --package-path mrkdwn mrkdwn - < document.md
```

The full command is:

```text
mrkdwn [FILE|-] [--config PATH] [--no-config] [--watch|--no-watch]
                 [--allow-remote-images] [--print-default-theme]
```

A missing `FILE` selects `README.md` in the launch directory. Regular files
watch for changes by default; standard input is read once. Source is UTF-8 and
capped at 16 MiB. Source and explicit-theme failures are printed before
SwiftTUI takes over the terminal.

For an interactive `mrkdwn -`, the app consumes the document from standard
input and then scopes terminal input to the process's controlling `/dev/tty`;
the original descriptor is restored during teardown. This means an interactive
stdin launch needs a controlling terminal even though the Markdown arrives
through a pipe. Non-TTY output uses SwiftTUI's render-once path and does not
need that handoff.

Remote images are disabled by default. Opt in with
`--allow-remote-images`. Remote loads accept only credential-free HTTP(S)
destinations on standard ports whose authority is a literal public IPv4 or
IPv6 address. DNS hostnames are rejected before URLSession starts so a
rebinding hostname cannot send a blind request to a local service. Every
redirect must remain a literal public address, and URLSession's collected
transaction metrics must identify the same class of direct public-network
peer before any buffered response is accepted. Loopback, private, link-local,
hostname, proxy, and Private Relay transactions are rejected.
Local image and theme inputs must be regular files. Local and remote PNG/JPEG
payloads still pass encoded, dimension, and decoded-size checks before
SwiftTUI sees them.

Search runs outside the UI actor and retains at most the first 1,000 matches
from a bounded document scan. The search overlay and status line show a `+`
when additional matches were intentionally discarded.

## Keys

| Keys | Action |
| --- | --- |
| `j` / `k`, arrows | Scroll one line |
| Page Down / Page Up, Space / Shift-Space | Scroll one page |
| `g` / `G`, Home / End | Top / bottom |
| `]` / `[` | Next / previous heading |
| `t` | Toggle table of contents |
| `/` | Search; `n` / `N` moves between matches |
| `b` / `f` | Back / forward local Markdown history |
| `r` | Reload document and theme |
| `m` / `Alt-M` | Toggle the focused/first Mermaid source; reveal the next hidden Mermaid source |
| `?` | Help |
| `q`, Control-C | Quit |

Tab and Shift-Tab retain SwiftTUI's normal focus traversal for links and
controls. Enter activates the focused item. When nested view composition does
not expose a Mermaid diagram through that traversal, `Alt-M` globally reveals
the next hidden diagram in deterministic authored order.

## Theme

The built-in theme needs no file. To inspect or customize every role:

```bash
swiftly run swift run --package-path mrkdwn mrkdwn --print-default-theme
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/mrkdwn"
swiftly run swift run --package-path mrkdwn mrkdwn --print-default-theme \
  > "${XDG_CONFIG_HOME:-$HOME/.config}/mrkdwn/theme.toml"
```

Lookup order is `--no-config`, `--config PATH`, an absolute nonempty
`$XDG_CONFIG_HOME/mrkdwn/theme.toml`, then
`~/.config/mrkdwn/theme.toml`. A missing implicit file selects the built-in
theme; a missing explicit file is an error.

The decoder intentionally supports only the profile printed by
`--print-default-theme`: TOML `version = 1`, comments, basic quoted strings,
and the `[theme]` / `[theme.mermaid]` tables. Unknown or duplicate keys,
unsupported TOML constructs, and colors other than `#RRGGBB` fail with a
line-and-column diagnostic. [`default-theme.toml`](default-theme.toml) is the
complete schema.

## Markdown and Mermaid

The viewer handles headings, paragraphs, breaks, nested inline styles, code,
links and autolinks, standalone and mixed images, quotes, ordered/unordered
lists, tasks, fenced/indented code, rules, GFM tables, and literal raw HTML.
Unknown nodes produce a visible source fallback and compiler diagnostic.

A normalized `mermaid` code fence is rendered asynchronously. MrkdwnMermaid
provides semantic cells and intrinsic/minimum sizing; the app preserves wide
grapheme leaders and continuation columns when mapping them into a
SwiftTUI `ForeignSurface`. Unsupported or malformed diagrams show their source
and a local diagnostic without blanking the document.

## Test it

```bash
swiftly run swift test --package-path mrkdwn
MRKDWN_REAL_PTY_TESTS=1 swiftly run swift test --package-path mrkdwn
MRKDWN_PERFORMANCE_BUDGETS=1 swiftly run swift test --package-path mrkdwn
swiftly run swift build -c release --package-path mrkdwn
```

The focused suite covers the Markdown matrix, TOML and XDG contracts, links,
image headers and bounds, cache eviction, model actions, responsive
60/80/120/180-column rendering, Mermaid sizing, and Unicode continuation-cell
bridging. The environment-gated lane additionally owns real PTYs and runs the
rebuilt executable through document history, search, nested Mermaid keyboard
traversal/source reveal,
atomic live reload, invalid-theme recovery, resize, platform link-opening
failure, invalid preflight, and clean exit. It also proves standard-input
descriptor handoff and restoration; the examples gate enables it on macOS and
Linux.

## Capture it

For a comparable screenshot or terminal recording, use a 120×40 Unicode
terminal, the built-in theme, and the complete fixture:

```bash
swiftly run swift run --package-path mrkdwn mrkdwn \
  mrkdwn/Tests/MrkdwnTests/Fixtures/full-surface.md \
  --no-config --no-watch
```

Wait for the Mermaid surface to replace its pending state before capturing.
Keep remote images disabled, include the terminal name and `swift --version`
with published captures, and state any dimensions other than 120×40. Use the
same command at 60×16 when capturing the compact layout.

## Performance envelope

The wall-clock budgets below are **opt-in**: the suite always measures and
prints these durations, but only enforces them under
`MRKDWN_PERFORMANCE_BUDGETS=1`. Shared CI runners are slower and contended
enough to report hardware noise as a product regression, so run them on a quiet
machine. Every *structural* assertion in the same tests — node counts, geometry
recomputation counts, visible rows, scroll positions, cache bounds — runs
everywhere, including the native Linux gate, and is the actual regression guard.

The reference run was an Apple M5 Max Mac17,7 with 128 GiB RAM, macOS 27, and
Swift 6.3.3. The Phase 4 debug baseline compiled the 1 MiB / 10,000-block
document in about 0.10 seconds, against a 0.20-second budget. The settled
geometry path took about 0.60 seconds for its first 10,000-block layout and
0.8 milliseconds for 1,000 cached scroll updates; their budgets are 1.20 seconds
and 1.5 milliseconds.

The root-shaped 80×24 table fixture compiled 500×20 cells in about 0.064
seconds, computed wrapped metrics in 0.151 seconds, painted its first frame in
0.62 seconds, and repainted after combined outer-vertical and inner-horizontal
scrolling in 0.85 seconds. Their budgets are 0.130, 0.300, 1.230, and 1.700
seconds respectively, and fewer than 1,250 render-pipeline nodes per table frame
is checked unconditionally. Separate fixtures submit 100 Mermaid jobs and assert
a peak of two, and insert 100 image payloads while asserting the 64-entry /
64 MiB encoded cache bounds. Viewer admission and retained ready/error/loading
states are capped at 128 resources; image execution admits four active and 64
queued loads, with hidden work canceled. These are regression budgets, not
user-facing speed claims.

## What to copy

This is an advanced app, not a minimal tutorial. The useful boundaries to copy
are:

- compile third-party syntax once into app-owned `Sendable` values;
- isolate effects and generation checks in one observable model;
- negotiate foreign renderer width before constructing an exact-size
  `ForeignSurface`; and
- validate configuration and resource limits before handing data to views.

## Current limitations

- Markdown is read-only; task checkboxes are presentation only.
- Raw HTML is displayed literally and never executed.
- Code has a language label but no syntax highlighting.
- Mermaid support is MrkdwnMermaid's documented six-family subset, not
  Mermaid.js compatibility.
- Bidirectional controls are rejected by MrkdwnMermaid; strong RTL text is
  retained in logical source order with a fidelity warning.
- Terminal image display depends on host attachment support; alt text remains
  visible for blocked or failed images.
- Remote image loading intentionally does not operate through HTTP proxies or
  iCloud Private Relay because those transports hide the origin peer address.
- Position and history are not persisted between launches.
