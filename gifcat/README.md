# GIF Cat

> Plays animated GIFs straight in your terminal — decoded, frame-timed, and tiled — so you can `cat` a GIF the way you `cat` a file. Runs in the terminal.

## Run

```bash
swiftly run swift run --package-path gifcat gifcat gifeditor/nyan.gif
```

Any GIF path works; `gifeditor/nyan.gif` is the checked-in sample (run from
the repository root).

Pass several paths to tile them side by side in argument order:

```bash
swiftly run swift run --package-path gifcat gifcat first.gif second.gif third.gif
```

`Ctrl+D` exits.

## Demonstrates

- `SwiftTUIAnimatedImage` decodes and animates GIFs with their source frame
  delays. The example has no manual frame loop.
- The standard SwiftTUI image surface renders image attachments. Image content
  combines with other views.
- The example preserves argument order when it tiles multiple animated inputs.
  It uses row-major order, decoded image sizes, and one terminal cell between
  images.

## App layout

The example has separate app and library targets. `GifCat` owns the view, and
`GifCatApp` owns the executable. Thus, tests can import the rendering view
without the CLI entry point.

## Test

```bash
swiftly run swift test --package-path gifcat
```

The tests cover input-path normalization, row-major tiling, and image placement.
They also cover frame advancement, missing-file diagnostics, and usage text for
an empty command.

## See also

- The gallery's **Images** tab — the same animated-image surface inside the full SwiftTUI showcase.
- [`SwiftTUIAnimatedImage` DocC reference](https://swifttui.sh/docs/documentation/) — the decoding and frame-timing API this example drives.
