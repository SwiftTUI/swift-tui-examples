# Equatable Demo

The smallest checked-in proof of `View.equatable()` — SwiftTUI's opt-in for memoized-body reuse, showing a stable subtree skip re-evaluation while the rest of the screen ticks, rendered in the terminal.

## Run

```bash
swiftly run swift run --package-path equatable-demo EquatableDemo
```

Press `tick` (or the spacebar) and watch the counter change while the panel below stays put — that panel is reused, not rebuilt, on each tick.

## Demonstrates

- `View.equatable()` applied to a stable boundary view — which means SwiftTUI compares the view by `==` and reuses its whole rendered subtree instead of re-evaluating it.
- The boundary requirement: `DashboardPanel`'s body reads no `@State`/`@Observable`/focus state, so it is a sound, profitable memo boundary.
- The `==`-is-a-correctness-contract caveat: a lossy `==` would serve a stale subtree.

## How it works

A `@State` counter (`ticks`) updates on every `tick` press, invalidating the root. A large static `DashboardPanel` sits beneath it. Because `DashboardPanel` conforms to `Equatable` and is applied with `.equatable()`, SwiftTUI compares it by `==` and reuses its whole rendered subtree across ticks instead of re-evaluating all 48 cells — the panel is unchanged, so its `==` returns equal.

## Controls

| Key | Action |
| --- | --- |
| `tick` / Space | Increment the counter and invalidate the root |

## Test

No test target.

## See also

- [`SwiftTUI` DocC reference](https://swifttui.sh/docs/documentation/) — the public API surface, including `View.equatable()`.
