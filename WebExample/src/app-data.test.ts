import { expect, test } from "bun:test";

import { defaultStyle, marketingStyle } from "./app-data.ts";

test("frontend wires opt-in frame diagnostics without importing unreleased web types", async () => {
  const source = await Bun.file(new URL("./frontend.ts", import.meta.url)).text();

  expect(source).toContain("function frameDiagnosticsEnabled(");
  expect(source).toContain('searchParams.get("frameDiagnostics") === "1"');
  expect(source).toContain('searchParams.get("diagnostics") === "1"');
  expect(source).toContain('localStorage.swiftTUIFrameDiagnostics === "1"');
  expect(source).toContain('TUIGUI_FRAME_DIAGNOSTICS: "1"');
  expect(source).toContain("onFrameDiagnostic");
  expect(source).toContain('console.debug("SwiftTUI frame", row)');
  expect(source).not.toContain("type WebHostFrameDiagnostic");
});

test("default style keeps a readable terminal baseline", () => {
  expect(defaultStyle.fontSize).toBe(16);
  expect(defaultStyle.cursorBlink).toBe(false);
  expect(defaultStyle.backgroundOpacity).toBe(1);
});

test("marketing style matches the website palette", () => {
  // Background and foreground match Website/src/styles/site.css --bg / --ink
  expect(marketingStyle.palette?.background).toBe("#101512");
  expect(marketingStyle.palette?.foreground).toBe("#e8eee9");
  expect(marketingStyle.theme?.background).toBe("#101512");
  expect(marketingStyle.theme?.foreground).toBe("#e8eee9");

  // Tint / success / cursor use the brighter terminal expression of the site teal.
  expect(marketingStyle.theme?.tint).toBe("#62d6bf");
  expect(marketingStyle.theme?.success).toBe("#62d6bf");
  expect(marketingStyle.palette?.cursor).toBe("#62d6bf");
  expect(marketingStyle.palette?.ansi?.green).toBe("#62d6bf");

  expect(marketingStyle.theme?.warning).toBe("#d6b66b");

  // Marketing embed paints opaque to seam cleanly into the chrome bg.
  expect(marketingStyle.backgroundOpacity).toBe(1);

  // Inherits the readable baseline from defaultStyle.
  expect(marketingStyle.fontSize).toBe(defaultStyle.fontSize);
  expect(marketingStyle.fontFamily).toBe(defaultStyle.fontFamily);
});
