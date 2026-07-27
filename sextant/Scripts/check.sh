#!/bin/sh
set -eu

swiftly run swift format lint --strict --recursive \
  --configuration .swift-format.json \
  Sources Tests
swiftly run swift test --skip SextantPerformanceTests
swiftly run swift test --filter SextantPerformanceTests
SEXTANT_REAL_PTY_TESTS=1 swiftly run swift test \
  --filter SextantRealTerminalJourneyTests
swiftly run swift build -c release
swiftly run swift run sextant --version
