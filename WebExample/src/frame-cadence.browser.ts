import { expect, test } from "bun:test";
import { chromium } from "playwright";

import { serveBuiltWebExample } from "./built-app-server.ts";

declare global {
  interface Window {
    __swiftTUIFrameSamples?: FrameSample[];
  }
}

interface FrameSample {
  timestamp: number;
  generation: number;
}

test("WebExample Game of Life keeps the authored WASI frame cadence", async () => {
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
    Object.defineProperty(window, "__swiftTUIFrameSamples", {
      configurable: true,
      value: samples,
    });
    JSON.parse = function patchedJSONParse(
      text: string,
      reviver?: Parameters<typeof JSON.parse>[1]
    ) {
      const value = originalParse.call(this, text, reviver);
      if (isSurfaceFrame(value)) {
        const generation = generationFromFrame(value);
        if (generation !== undefined) {
          samples.push({
            timestamp: performance.now(),
            generation,
          });
        }
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

    function generationFromFrame(value: unknown): number | undefined {
      const rows = (value as { rows?: WebHostSurfaceCell[][] }).rows;
      const header = rowText(rows?.[0] ?? []);
      const match = header.match(/\bgen\s*(\d+)/);
      return match ? Number(match[1]) : undefined;
    }

    function rowText(row: WebHostSurfaceCell[]): string {
      let text = "";
      let cursor = 0;
      for (const [column, cellText, span] of row) {
        if (column > cursor) {
          text += " ".repeat(column - cursor);
        }
        text += cellText;
        cursor = column + Math.max(1, span);
      }
      return text;
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
      () => {
        const samples = window.__swiftTUIFrameSamples ?? [];
        const first = samples.find((sample) => sample.generation > 0);
        const last = samples[samples.length - 1];
        return first !== undefined && last !== undefined
          && last.generation - first.generation >= 24;
      },
      undefined,
      { polling: 100, timeout: 30_000 }
    );

    const samples = await page.evaluate(() => window.__swiftTUIFrameSamples ?? []);
    const steady = samples.filter((sample) => sample.generation > 0);
    const first = steady[0]!;
    const last = steady[steady.length - 1]!;
    const generationDelta = last.generation - first.generation;
    const elapsedMilliseconds = last.timestamp - first.timestamp;
    const millisecondsPerGeneration = elapsedMilliseconds / generationDelta;

    expect(generationDelta).toBeGreaterThanOrEqual(24);
    expect(millisecondsPerGeneration).toBeLessThanOrEqual(150);
  } finally {
    await page.close();
    await browser.close();
    server.stop(true);
  }
}, 120_000);

type WebHostSurfaceCell = [
  column: number,
  text: string,
  span: number,
  style: number,
];
