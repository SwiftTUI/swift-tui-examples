import { expect, test } from "bun:test";
import { chromium } from "playwright";

import { serveBuiltWebExample } from "./built-app-server.ts";

interface FrameSample {
  timestamp: number;
  hasDamage: boolean;
  dirtyRows: number;
}

declare global {
  interface Window {
    __swiftTUIDamageSamples?: FrameSample[];
  }
}

test("WebExample Game of Life emits raster damage on steady frames", async () => {
  const server = serveBuiltWebExample();
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: {
      width: 1280,
      height: 900,
    },
  });

  await page.addInitScript(() => {
    const originalParse = JSON.parse;
    const samples: FrameSample[] = [];
    Object.defineProperty(window, "__swiftTUIDamageSamples", {
      configurable: true,
      value: samples,
    });
    JSON.parse = function patchedJSONParse(
      text: string,
      reviver?: Parameters<typeof JSON.parse>[1]
    ) {
      const value = originalParse.call(this, text, reviver);
      if (isSurfaceFrame(value)) {
        const damage = (value as { damage?: { textRows?: unknown[] } }).damage;
        samples.push({
          timestamp: performance.now(),
          hasDamage: Boolean(damage),
          dirtyRows: Array.isArray(damage?.textRows) ? damage.textRows.length : 0,
        });
      }
      return value;
    };

    function isSurfaceFrame(value: unknown): boolean {
      if (!value || typeof value !== "object") {
        return false;
      }
      const frame = value as {
        width?: unknown;
        height?: unknown;
        rows?: unknown;
      };
      return typeof frame.width === "number"
        && typeof frame.height === "number"
        && Array.isArray(frame.rows);
    }
  });

  try {
    await page.goto(server.url.href, { waitUntil: "domcontentloaded" });
    await page.waitForFunction(() => globalThis.crossOriginIsolated === true, undefined, {
      timeout: 10_000,
    });
    await page.waitForSelector(".webhost-scene__surface", {
      state: "attached",
      timeout: 30_000,
    });
    await page.waitForFunction(
      () => (window.__swiftTUIDamageSamples?.length ?? 0) >= 40,
      undefined,
      { polling: 100, timeout: 30_000 }
    );

    const samples = await page.evaluate(() => window.__swiftTUIDamageSamples ?? []);
    const steadySamples = samples.slice(8);
    const damagedFrames = steadySamples.filter((sample) => sample.hasDamage);

    expect(steadySamples.length).toBeGreaterThanOrEqual(24);
    expect(damagedFrames.length).toBeGreaterThanOrEqual(Math.floor(steadySamples.length * 0.8));
    expect(damagedFrames.some((sample) => sample.dirtyRows > 0)).toBe(true);
  } finally {
    await page.close();
    await browser.close();
    server.stop(true);
  }
}, 120_000);
