import type { WebHostTerminalStyle } from "@swifttui/web";

export const defaultStyle: WebHostTerminalStyle = {
  fontSize: 16,
  fontFamily:
    '"SFMono-Regular", "SF Mono", "Menlo", "Monaco", "Consolas", "Liberation Mono", monospace',
  cursorBlink: false,
  backgroundOpacity: 1,
};

// Palette tuned to the Quiet Engine marketing surface. Used only by the
// `?embed=marketing` iframe; the standalone route keeps the same geometry
// with a slightly quieter neutral palette.
export const marketingStyle: WebHostTerminalStyle = {
  ...defaultStyle,
  palette: {
    foreground: "#e8eee9",
    background: "#101512",
    cursor: "#62d6bf",
    selectionBackground: "#173a33",
    selectionForeground: "#f4f8f5",
    ansi: {
      black: "#101512",
      red: "#e88383",
      green: "#62d6bf",
      yellow: "#d6b66b",
      blue: "#86a8d6",
      magenta: "#bda2d6",
      cyan: "#70c7cf",
      white: "#d9e1db",
      brightBlack: "#6f7c73",
      brightRed: "#f09a9a",
      brightGreen: "#8be1cf",
      brightYellow: "#e4cb91",
      brightBlue: "#a4bddd",
      brightMagenta: "#cfb9df",
      brightCyan: "#98d9de",
      brightWhite: "#f4f8f5",
    },
  },
  theme: {
    foreground: "#e8eee9",
    background: "#101512",
    tint: "#62d6bf",
    separator: "#27302a",
    selection: "#173a33",
    placeholder: "#6f7c73",
    link: "#62d6bf",
    fill: "#18201b",
    windowBackground: "#101512",
    success: "#62d6bf",
    warning: "#d6b66b",
    danger: "#e88383",
    info: "#a8b4ac",
    muted: "#6f7c73",
  },
};

export const terminalAppManifestPath = "./TerminalApp/dist/scene-manifest.json";
export const terminalAppWasmPath = "./TerminalApp/dist/assets/app.wasm";
