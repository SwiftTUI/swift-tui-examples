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
    // The WebHost wire carries two surface shapes: full frames (`version: 2`
    // with complete `rows`) and delta frames (`version: 3, encoding: "delta"`
    // with `deltaRows` row patches). Steady scenes present deltas — a delta
    // IS a damage frame, its patched rows are the dirty set.
    JSON.parse = function patchedJSONParse(
      text: string,
      reviver?: Parameters<typeof JSON.parse>[1]
    ) {
      const value = originalParse.call(this, text, reviver);
      if (value && typeof value === "object") {
        const frame = value as {
          width?: unknown;
          height?: unknown;
          rows?: unknown;
          deltaRows?: unknown[];
          encoding?: unknown;
          damage?: { textRows?: unknown[] };
        };
        if (typeof frame.width === "number" && typeof frame.height === "number") {
          if (Array.isArray(frame.rows)) {
            samples.push({
              timestamp: performance.now(),
              hasDamage: Boolean(frame.damage),
              dirtyRows: Array.isArray(frame.damage?.textRows)
                ? frame.damage.textRows.length
                : 0,
            });
          } else if (frame.encoding === "delta" && Array.isArray(frame.deltaRows)) {
            samples.push({
              timestamp: performance.now(),
              hasDamage: true,
              dirtyRows: frame.deltaRows.length,
            });
          }
        }
      }
      return value;
    };
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
