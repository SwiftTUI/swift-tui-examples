import { expect, test } from "bun:test";
import { chromium } from "playwright";

import { serveBuiltWebExample } from "./built-app-server.ts";

interface FrameDiagnosticRow {
  frame?: unknown;
  total_ms?: unknown;
  [key: string]: unknown;
}

declare global {
  interface Window {
    __swiftTUIFrameDiagnostics?: FrameDiagnosticRow[];
  }
}

const expectFrameDiagnostics = process.env.WEBEXAMPLE_EXPECT_FRAME_DIAGNOSTICS === "1";

test("WebExample renders WASI surface frames into a nonblank canvas", async () => {
  const server = serveBuiltWebExample();
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: {
      width: 1280,
      height: 900,
    },
  });
  const runtimeErrors: string[] = [];

  page.on("pageerror", (error) => {
    runtimeErrors.push(error.message);
  });
  page.on("console", (message) => {
    if (message.type() === "error") {
      runtimeErrors.push(message.text());
    }
  });

  if (expectFrameDiagnostics) {
    await page.addInitScript(() => {
      const diagnostics: FrameDiagnosticRow[] = [];
      Object.defineProperty(window, "__swiftTUIFrameDiagnostics", {
        configurable: true,
        value: diagnostics,
      });

      const originalDebug = console.debug.bind(console);
      console.debug = (...args: unknown[]) => {
        if (args[0] === "SwiftTUI frame") {
          const row = args[1];
          diagnostics.push(row && typeof row === "object"
            ? row as FrameDiagnosticRow
            : { value: row });
          return;
        }
        originalDebug(...args);
      };
    });
  }

  try {
    const initialUrl = new URL(server.url.href);
    if (expectFrameDiagnostics) {
      initialUrl.searchParams.set("frameDiagnostics", "1");
    }

    await page.goto(initialUrl.href, { waitUntil: "domcontentloaded" });
    await page.waitForFunction(() => globalThis.crossOriginIsolated === true, undefined, {
      timeout: 10_000,
    });
    await page.waitForSelector(".webhost-scene__surface", {
      state: "attached",
      timeout: 30_000,
    });
    const initialLayout = await page.evaluate(() => {
      const root = document.querySelector<HTMLElement>("#root");
      const frame = document.querySelector<HTMLElement>(".terminal-frame");
      const canvas = document.querySelector<HTMLCanvasElement>(".webhost-scene__surface");
      if (!root || !frame || !canvas) {
        throw new Error("missing WebExample layout elements");
      }

      const rootRect = root.getBoundingClientRect();
      const frameRect = frame.getBoundingClientRect();
      const canvasRect = canvas.getBoundingClientRect();
      return {
        hasResizeHandle: document.querySelector("[data-resize-handle]") !== null,
        rootWidth: rootRect.width,
        rootHeight: rootRect.height,
        frameWidth: frameRect.width,
        frameHeight: frameRect.height,
        canvasWidth: canvasRect.width,
        canvasHeight: canvasRect.height,
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight,
      };
    });
    expect(initialLayout.hasResizeHandle).toBe(false);
    expect(initialLayout.rootWidth).toBe(initialLayout.viewportWidth);
    expect(initialLayout.rootHeight).toBe(initialLayout.viewportHeight);
    expect(initialLayout.frameWidth).toBeGreaterThan(1_200);
    expect(initialLayout.frameHeight).toBeGreaterThan(780);
    expect(initialLayout.canvasWidth).toBeGreaterThan(1_200);
    expect(initialLayout.canvasHeight).toBeGreaterThan(760);

    const canvasState = await page.waitForFunction(() => {
      const canvas = document.querySelector(".webhost-scene__surface");
      if (!(canvas instanceof HTMLCanvasElement)) {
        return false;
      }
      if (canvas.width <= 0 || canvas.height <= 0) {
        return false;
      }

      const context = canvas.getContext("2d", { willReadFrequently: true });
      if (!context) {
        return false;
      }

      const width = Math.min(canvas.width, 240);
      const height = Math.min(canvas.height, 180);
      const pixels = context.getImageData(0, 0, width, height).data;
      let firstPixel: string | undefined;
      let opaqueSamples = 0;
      let differingSamples = 0;

      for (let index = 0; index < pixels.length; index += 16) {
        const red = pixels[index] ?? 0;
        const green = pixels[index + 1] ?? 0;
        const blue = pixels[index + 2] ?? 0;
        const alpha = pixels[index + 3] ?? 0;
        if (alpha === 0) {
          continue;
        }

        opaqueSamples += 1;
        const pixel = `${red}:${green}:${blue}:${alpha}`;
        if (firstPixel === undefined) {
          firstPixel = pixel;
        } else if (pixel !== firstPixel) {
          differingSamples += 1;
        }

        if (opaqueSamples > 12 && differingSamples > 2) {
          return {
            width: canvas.width,
            height: canvas.height,
            opaqueSamples,
            differingSamples,
          };
        }
      }

      return false;
    }, undefined, {
      polling: 250,
      timeout: 60_000,
    });

    expect(await canvasState.jsonValue()).toMatchObject({
      opaqueSamples: expect.any(Number),
      differingSamples: expect.any(Number),
    });

    if (expectFrameDiagnostics) {
      await page.waitForFunction(
        () => (window.__swiftTUIFrameDiagnostics?.length ?? 0) > 0,
        undefined,
        { polling: 100, timeout: 30_000 }
      );

      const [row] = await page.evaluate(() => window.__swiftTUIFrameDiagnostics ?? []);

      expect(row).toEqual(expect.any(Object));
      expect(row).toHaveProperty("frame");
      expect(row).toHaveProperty("total_ms");
      expect(String(row?.frame)).not.toBe("");
      expect(String(row?.total_ms)).not.toBe("");
    }

    await page.click(".scene-select-trigger");
    await page.click('.scene-select-option[data-scene-id="animations"]');
    const initialResizeState = await page.waitForFunction(() => {
      const activeScene = document.querySelector(".webhost-scene:not([hidden])");
      const host = document.querySelector<HTMLElement>(".terminal-host");
      const canvas = activeScene?.querySelector<HTMLCanvasElement>(".webhost-scene__surface");
      const size = host?.dataset.size;
      if (activeScene?.getAttribute("data-scene-id") !== "animations" || !size || !canvas) {
        return false;
      }

      const rect = canvas.getBoundingClientRect();
      return {
        size,
        canvasWidth: rect.width,
        canvasHeight: rect.height,
      };
    }, undefined, {
      polling: 250,
      timeout: 30_000,
    });

    const initialResizeStateValue = await initialResizeState.jsonValue() as {
      size: string;
      canvasWidth: number;
      canvasHeight: number;
    };

    await page.setViewportSize({ width: 900, height: 620 });
    const resizedState = await page.waitForFunction((initial) => {
      const activeScene = document.querySelector(".webhost-scene:not([hidden])");
      const host = document.querySelector<HTMLElement>(".terminal-host");
      const canvas = activeScene?.querySelector<HTMLCanvasElement>(".webhost-scene__surface");
      const size = host?.dataset.size;
      if (activeScene?.getAttribute("data-scene-id") !== "animations" || !size || !canvas) {
        return false;
      }

      const rect = canvas.getBoundingClientRect();
      const current = {
        size,
        canvasWidth: rect.width,
        canvasHeight: rect.height,
      };
      return current.size !== initial.size &&
        current.canvasWidth < initial.canvasWidth &&
        current.canvasHeight < initial.canvasHeight
        ? current
        : false;
    }, initialResizeStateValue, {
      polling: 250,
      timeout: 30_000,
    });
    expect(await resizedState.jsonValue()).toMatchObject({
      size: expect.any(String),
      canvasWidth: expect.any(Number),
      canvasHeight: expect.any(Number),
    });

    expect(runtimeErrors).toEqual([]);
  } finally {
    await page.close();
    await browser.close();
    server.stop(true);
  }
}, 120_000);
