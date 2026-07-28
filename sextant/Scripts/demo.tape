Output docs/assets/sextant-journey.gif

Require .build/release/sextant

Set Shell "zsh"
Set FontFamily "SF Mono"
Set FontSize 18
Set Width 1400
Set Height 560
Set Padding 20
Set Margin 24
Set MarginFill "#0A0D12"
Set BorderRadius 10
Set WindowBar Rings
Set TypingSpeed 25ms
Set Framerate 24

Hide
Type "mkdir -p /tmp/swifttui-sextant-demo-v0.1/Sources /tmp/swifttui-sextant-demo-v0.1/Tests /tmp/swifttui-sextant-demo-v0.1/docs; cp README.md /tmp/swifttui-sextant-demo-v0.1/README.md; touch /tmp/swifttui-sextant-demo-v0.1/CHANGELOG.md /tmp/swifttui-sextant-demo-v0.1/LICENSE"
Enter
Type "./.build/release/sextant /tmp/swifttui-sextant-demo-v0.1/README.md --preview built-in"
Enter
Sleep 2s
Show
Sleep 3s

Enter
Sleep 3s
Escape
Sleep 1s
Type "?"
Sleep 3s
Escape
Sleep 1s
Type ":"
Sleep 3s
Escape
Sleep 1s
Ctrl+D
Sleep 2s
Hide
Type "rm -rf /tmp/swifttui-sextant-demo-v0.1"
Enter
