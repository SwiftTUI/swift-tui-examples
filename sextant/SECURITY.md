# Security Policy

Sextant is pre-1.0 software. Only the latest tagged release and current `main`
branch are supported for security triage.

Report vulnerabilities through GitHub private vulnerability reporting for
`SwiftTUI/sextant`. If that service is unavailable, contact
`security@swifttui.sh` privately before you open a public issue.

Sextant does not mutate files. External preview and editor commands are passed
as argv arrays without a shell. Preview templates require `{path}` as a
standalone argv element and reject inline shell-source execution, so selected
paths do not enter shell source. Preview tools still receive read access to the
selected path. Install and configure only tools that you trust.
