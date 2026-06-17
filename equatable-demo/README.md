# equatable-demo

Smallest checked-in example of `View.equatable()` — SwiftTUI's opt-in for
memoized-body reuse.

A `@State` counter (`ticks`) updates on every `tick` press, invalidating the
root. A large static `DashboardPanel` sits beneath it. Because `DashboardPanel`
conforms to `Equatable` and is applied with `.equatable()`, SwiftTUI compares it
by `==` and reuses its whole rendered subtree across ticks instead of
re-evaluating all 48 cells — the panel is unchanged, so its `==` returns equal.

## Demonstrates

- `View.equatable()` applied to a stable boundary view.
- The boundary requirement: `DashboardPanel`'s body reads no
  `@State`/`@Observable`/focus state, so it is a sound, profitable memo boundary.
- The `==`-is-a-correctness-contract caveat (a lossy `==` would serve a stale
  subtree).

## Run

```bash
swiftly run swift run --package-path equatable-demo equatable-demo
```

Press `tick` (or the spacebar) and watch the counter change while the panel
below stays put — that panel is reused, not rebuilt, on each tick. This example
has no test target.
