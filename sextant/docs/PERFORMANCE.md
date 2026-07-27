# Performance baseline

This is the accepted Sextant v0.1 baseline for the app-owned benchmark at
`HEAD`.

- Machine: Mac17,7, Apple M5 Max
- OS: macOS 27.0 (26A5388g)
- Swift: 6.3.3 release toolchain, arm64-apple-macosx
- Build: SwiftPM debug test build
- Fixture: 10,000 flat in-memory file entries with stable inode identities
- Interaction samples: 100 selection moves and one exact local-filter update
- Render: committed SwiftTUI frames at 100×30 cells
- Preview: deterministic in-process terminal-session adapter

Run:

```sh
swiftly run swift test --filter SextantPerformanceTests
```

The gate asserts:

| Slice | Maximum |
| --- | ---: |
| Chrome-to-first-frame | 50 ms |
| Warm selection-to-committed-frame p95 | 50 ms |
| Local filter-to-committed-frame | 50 ms |
| 10,000-entry directory read/store | 250 ms |
| Preview selection-to-ready | 250 ms |
| Replacement-to-old-child termination | 900 ms |

The test prints the observed values for every run. These limits are behavioral
acceptance budgets, not claims that debug-build microbenchmarks compare across
machines.

Accepted 2026-07-27 reference-machine run:

| Slice | Result |
| --- | ---: |
| Chrome-to-first-frame | 10.663 ms |
| Warm selection-to-committed-frame p95 | 32.194 ms |
| Local filter-to-committed-frame | 22.436 ms |
| 10,000-entry directory read/store | 26.687 ms |
| Preview selection-to-ready | 126.838 ms |
| Replacement-to-old-child termination | 5.551 ms |

Large directories retain their complete model snapshot while `FileColumn`
authors 48 rows for ordinary terminal heights and grows only to the viewport
height plus eight overscan rows for taller terminals. Height-preserving prefix
and suffix spacers retain absolute scroll geometry without making committed
frame work proportional to the entry count.
