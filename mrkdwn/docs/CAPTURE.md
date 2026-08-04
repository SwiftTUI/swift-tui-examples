# Capturing mrkdwn for screenshots and recordings

Production notes for comparable mrkdwn captures (website and README assets).
Commands run from the repository root.

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
