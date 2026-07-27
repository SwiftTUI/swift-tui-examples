# Security Policy

Sextant is pre-1.0 software. Only the latest tagged release and current `main`
branch are supported for security triage.

Report vulnerabilities through GitHub private vulnerability reporting for
`SwiftTUI/sextant`. If that is unavailable, contact `security@swifttui.sh`
privately before opening a public issue.

Sextant does not mutate files. External preview and editor commands are passed
as argv arrays without a shell. Preview templates require `{path}` as a
standalone argv element and reject inline shell-source execution, so selected
paths are never interpolated into shell source. Preview tools still receive read
access to the selected path, so install and configure only tools you trust.
