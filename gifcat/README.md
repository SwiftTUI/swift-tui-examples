# GIF Cat

> Plays animated GIFs straight in your terminal — decoded, frame-timed, and tiled — so you can `cat` a GIF the way you `cat` a file. Runs in the terminal.

## Run

```bash
swiftly run swift run --package-path gifcat gifcat nyan.gif
```

Pass several paths to tile them side by side in argument order:

```bash
swiftly run swift run --package-path gifcat gifcat first.gif second.gif third.gif
```

`Ctrl+D` exits.

## Demonstrates

- `SwiftTUIAnimatedImage` — which means GIFs are decoded and animated using their source frame delays, no manual frame loop.
- Rendering image attachments through the standard SwiftTUI image surface — image content composites like any other view.
- Argument-order-preserving, row-major tiling of multiple animated inputs at their decoded size, with one terminal cell of spacing between images.

## App layout

A tiny app/library split: `GifCat` owns the view and `GifCatApp` owns the executable, so the rendering view is importable and testable apart from the CLI entry point.

## Test

```bash
swiftly run swift test --package-path gifcat
```

The tests cover input path normalization, row-major tiling, image attachment placement, animated frame advancement, missing-file diagnostics, and empty-invocation usage text.

## See also

- The gallery's **Images** tab — the same animated-image surface inside the full SwiftTUI showcase.
- [`SwiftTUIAnimatedImage` DocC reference](https://swifttui.sh/docs/documentation/) — the decoding and frame-timing API this example drives.
