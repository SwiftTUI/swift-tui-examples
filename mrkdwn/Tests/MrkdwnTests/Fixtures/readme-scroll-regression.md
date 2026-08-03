# mrkdwn

`mrkdwn` is a responsive terminal Markdown reader built as an advanced
[SwiftTUI](https://github.com/SwiftTUI/swift-tui) example. It compiles
CommonMark and GitHub-flavored Markdown with
[`swift-markdown`](https://github.com/swiftlang/swift-markdown). It renders
Markdown into app-owned values. One observable model owns navigation, search,
reload, and resource state.

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

If `FILE` is absent, the app selects `README.md` in the launch directory. By
default, the app watches regular files for changes. It reads standard input
once. Source text is UTF-8 and has a 16 MiB limit. The app prints source and
explicit-theme failures before SwiftTUI controls the terminal.

For an interactive `mrkdwn -`, the app reads the document from standard input.
Then it reads terminal input from the process `/dev/tty`. During shutdown, it
restores the original descriptor. Thus, an interactive standard-input launch
requires a controlling terminal. The Markdown can still arrive through a pipe.
Non-TTY output uses the SwiftTUI render-once path and does not require this
handoff.

Remote images are disabled by default. Enable them with
`--allow-remote-images`. Remote loads accept only credential-free HTTP(S)
destinations on standard ports. The authority must be a literal public IPv4 or
IPv6 address. The app rejects DNS hostnames before URLSession starts. Thus, DNS
rebinding cannot send a request to a local service. Each redirect must remain a
literal public address. Before the app accepts a response, URLSession metrics
must identify a direct public-network peer. The app rejects loopback, private,
link-local, hostname, proxy, and Private Relay transactions.
Local image and theme inputs must be regular files. Local and remote PNG/JPEG
payloads still pass encoded, dimension, and decoded-size checks before
SwiftTUI sees them.

Search runs outside the UI actor. A bounded document scan retains the first
1,000 matches. Search input and result counts stay in the bottom toolbar. If
the scan discards more matches, the toolbar shows a `+`.

## Keys

| Keys | Action |
| --- | --- |
| `j` / `k`, arrows | Scroll one line |
| Page Down / Page Up, Space / Shift-Space | Scroll one page |
| `g` / `G`, Home / End | Top / bottom |
| `]` / `[` | Next / previous heading |
| `t` | Toggle table of contents |
| `/` | Search. `n` / `N` moves between matches |
| `b` / `f` | Back / forward local Markdown history |
| `r` | Reload document and theme |
| `?` | Help |
| `q`, Control-C | Quit |

Tab and Shift-Tab use the standard SwiftTUI focus traversal for links and
controls. Enter activates the focused item.

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
theme. A missing explicit file is an error.

The decoder supports only the profile printed by
`--print-default-theme`: TOML `version = 1`, comments, basic quoted strings,
and the `[theme]` table. Unknown or duplicate keys, unsupported TOML
constructs, and colors other than `#RRGGBB` fail with a line-and-column
diagnostic. [`default-theme.toml`](default-theme.toml) is the complete schema.

## Markdown

The viewer supports headings, paragraphs, breaks, inline styles, code, links,
autolinks, images, and quotes. It also supports ordered and unordered lists,
tasks, fenced and indented code, rules, GFM tables, and literal raw HTML.
Unknown nodes produce a visible source fallback and compiler diagnostic.

## Test it

```bash
swiftly run swift test --package-path mrkdwn
MRKDWN_REAL_PTY_TESTS=1 swiftly run swift test --package-path mrkdwn
MRKDWN_PERFORMANCE_BUDGETS=1 swiftly run swift test --package-path mrkdwn
swiftly run swift build -c release --package-path mrkdwn
```

The focused suite covers the Markdown matrix, TOML and XDG contracts, links,
image bounds, cache eviction, and model actions. It also covers responsive
60/80/120/180-column rendering. The environment gate owns real PTYs. It runs
the rebuilt executable through history, search, atomic reload, invalid-theme
recovery, resize, link failures, invalid preflight, and clean exit. The gate
makes sure that standard-input descriptor handoff and restoration succeed. The
examples gate enables this lane on macOS and Linux.

## Capture it

For a comparable screenshot or terminal recording, use a 120×40 Unicode
terminal, the built-in theme, and the complete fixture:

```bash
swiftly run swift run --package-path mrkdwn mrkdwn \
  mrkdwn/Tests/MrkdwnTests/Fixtures/full-surface.md \
  --no-config --no-watch
```

Keep remote images disabled. Include the terminal name and `swift --version`
with published captures. If the dimensions are not 120×40, state the actual
dimensions. For the compact layout, use the same command at 60×16.

## Performance envelope

Timing assertions have two tiers. Every environment makes sure that each
measurement is below a **ceiling**. The native Linux gate also uses this
ceiling. A ceiling is
approximately five times its budget. A result above a ceiling indicates a
large regression, such as a lost cache or accidental O(n²) behavior. Tight
**budgets** are optional under `MRKDWN_PERFORMANCE_BUDGETS=1`. Shared CI runners
are two to three times slower than the calibration machine. Thus, CI does not
apply developer-machine budgets. Run the budget lane on a quiet machine. Tests
always print durations. All environments apply limits to node counts, geometry
computations, visible rows, scroll positions, and cache size.

The reference machine was an Apple M5 Max Mac17,7 with 128 GiB RAM, macOS 27,
and Swift 6.3.3. The Phase 4 debug baseline compiled a 1 MiB, 10,000-block
document in approximately 0.10 seconds. Its budget is 0.20 seconds. The settled
geometry path took approximately 0.60 seconds for the first 10,000-block
layout. It took 0.8 milliseconds for 1,000 cached scroll updates. The budgets
are 1.20 seconds and 1.5 milliseconds.

The root-shaped 80×24 table fixture compiled 500×20 cells in approximately
0.064 seconds. It computed wrapped metrics in 0.151 seconds and painted the
first frame in 0.62 seconds. A combined vertical and horizontal scroll caused
a repaint in 0.85 seconds. The respective budgets are 0.130, 0.300, 1.230, and
1.700 seconds. Each environment limits a table frame to fewer than 1,250 render
nodes. Separate fixtures insert image payloads and make sure that the encoded
cache stays within 64 entries and 64 MiB. Viewer admission and retained
resource states have a limit of 128.
Image execution permits four active loads and 64 queued loads. The app cancels
hidden work. These are regression budgets, not user-facing speed claims.

## What to copy

This is an advanced app, not a minimal tutorial. The useful boundaries to copy
are:

- Compile third-party syntax once into app-owned `Sendable` values.
- Isolate effects and generation checks in one observable model.
- Make sure that the configuration and resource limits are valid before you
  give data to views.

## Current limitations

- Markdown is read-only. Task checkboxes are presentation only.
- Raw HTML is displayed literally and never executed.
- Code has a language label but no syntax highlighting.
- Terminal image display depends on host attachment support. Alt text remains
  visible for blocked or failed images.
- Remote image loading intentionally does not operate through HTTP proxies or
  iCloud Private Relay because those transports hide the origin peer address.
- Position and history are not persisted between launches.
