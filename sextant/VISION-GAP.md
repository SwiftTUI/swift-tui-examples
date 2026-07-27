# Vision gap

The implementation at HEAD is a bounded, read-only terminal inspector with
built-in and optional external previews, responsive navigation, configuration,
watching, filename search, persistence, and real-PTY lifecycle coverage.

Remaining product gaps are distribution work rather than a second application
architecture:

- chooser mode remains deferred because it needs a typed post-session result
  seam in the runner;
- signed/notarized dual-architecture artifacts and Homebrew installation are
  not available during examples-repo incubation;
- screenshots and release media are owned by the extraction/release cut;
- Linux is build evidence, not a v0.1 distribution promise.
