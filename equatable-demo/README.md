# Equatable Demo

This is the smallest example of `View.equatable()`. This API enables
memoized-body reuse. A stable subtree skips evaluation while the rest of the
terminal screen changes.

## Run

```bash
swiftly run swift run --package-path equatable-demo EquatableDemo
```

Press `tick` or the spacebar. The counter changes, but the panel below does not.
The runtime reuses the panel on each tick.

## Demonstrates

- `View.equatable()` applies to a stable boundary view. SwiftTUI compares the
  view with `==` and reuses its rendered subtree.
- `DashboardPanel` satisfies the boundary requirement. Its body reads no
  `@State`, `@Observable`, or focus state.
- `==` is a correctness contract. A comparison that omits state can return a
  stale subtree.

## How it works

A `@State` counter named `ticks` changes after each `tick` press. This change
invalidates the root. A large, static `DashboardPanel` is below the counter.
`DashboardPanel` conforms to `Equatable` and uses `.equatable()`. SwiftTUI
compares it with `==` and reuses its rendered subtree. SwiftTUI calls `==`
before it reuses the panel. If `==` returns true, it does not evaluate all 48
cells again.

## Controls

| Key | Action |
| --- | --- |
| `tick` / Space | Increment the counter and invalidate the root |

## Test

The package has no test target.

## See also

- [`SwiftTUI` DocC reference](https://swifttui.sh/docs/documentation/): the public API surface, including `View.equatable()`.
