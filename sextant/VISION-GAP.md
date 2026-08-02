# Vision gap

At HEAD, the implementation is a bounded, read-only terminal inspector. It has
built-in and optional external previews, responsive navigation, and
configuration. It also has directory watches, filename search, persistence,
and real-PTY lifecycle tests.

Remaining product gaps are distribution work rather than a second application
architecture:

- Chooser mode is not available because the runner needs a typed post-session
  result interface.
- The examples repository does not provide signed and notarized
  dual-architecture artifacts or Homebrew installation.
- The repository extraction and release process owns screenshots and release
  media.
- Linux builds provide evidence, not a v0.1 distribution promise.
