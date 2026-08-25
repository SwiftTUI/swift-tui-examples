# Suite partition for the packages whose tests split across the two lanes.
#
# The framework-seam gate (Scripts/check_examples.sh) runs the suites that
# exercise SwiftTUI behaviour on every push; the app-logic lane
# (Scripts/check_examples_focused_tests.sh) runs everything else when the
# package changes and at tags. Both lanes read these regexes — one as
# `--filter`, the other as `--skip` — so they partition each package exactly
# and a new suite cannot fall between them (it lands in app-logic by default).
# `swift test --filter` matches the regex against `Module.Suite/test`.
#
# Sourced by both gate scripts; keep it POSIX sh.

# mrkdwn: view contracts, viewer model and shell, terminal input lease,
# performance envelope, and the real-terminal PTY journeys are framework
# behaviour. Compiler, links/resources, theme, file watcher, manifest
# contract, and smoke are the app's own logic.
mrkdwn_framework_suites='MrkdwnTests\.(ViewContractTests|ViewerModelAndRenderTests|TerminalInputLeaseTests|PerformanceEnvelopeTests|MrkdwnRealTerminalJourneyTests)'
# The seam gate runs those suites as THREE invocations, not one. Measured on
# 2026-08-25 at the 0.9.9 tag (macOS arm64, and the Linux lane's 75-minute
# cap at the same pin): a process hosting ViewContractTests or
# ViewerModelAndRenderTests parks before its first test event (5/5 runs,
# alone or with company), while the terminal-lease/performance pair and the
# PTY journeys complete in seconds when hosted alone (E3/F3, 5/5). Splitting
# them means the healthy suites still deliver a verdict and only the
# parking pair pays the watchdog's bound. Root cause: open thread
# (swift-tui-org report 2026-08-25-001 §3.4).
mrkdwn_lease_perf_suites='MrkdwnTests\.(TerminalInputLeaseTests|PerformanceEnvelopeTests)'
mrkdwn_journey_suites='MrkdwnTests\.MrkdwnRealTerminalJourneyTests'
mrkdwn_view_suites='MrkdwnTests\.(ViewContractTests|ViewerModelAndRenderTests)'

# csvui: the view contracts and the real-terminal journeys are framework
# behaviour. Document core, model, lifecycle, watcher, and theme are CSV logic.
csvui_framework_suites='CSVUITests\.(CSVViewContractTests|CSVUIRealTerminalJourneyTests)'
