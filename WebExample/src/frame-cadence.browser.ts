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
    // The WebHost wire carries two surface shapes: full frames (`version: 2`
    // with complete `rows`) and delta frames (`version: 3, encoding: "delta"`
    // with `deltaRows` row patches). Steady scenes present deltas, so the tap
    // keeps a patched header row — a rows-only tap goes blind after the
    // first frames.
    let headerRow: WebHostSurfaceCell[] = [];
    JSON.parse = function patchedJSONParse(
      text: string,
      reviver?: Parameters<typeof JSON.parse>[1]
    ) {
      const value = originalParse.call(this, text, reviver);
      const frame = value as {
        width?: unknown;
        height?: unknown;
        rows?: WebHostSurfaceCell[][];
        deltaRows?: [number, WebHostSurfaceCell[]][];
        encoding?: unknown;
      };
      if (frame && typeof frame === "object"
        && typeof frame.width === "number" && typeof frame.height === "number") {
        let sawSurfaceFrame = false;
        if (Array.isArray(frame.rows)) {
          headerRow = frame.rows[0] ?? [];
          sawSurfaceFrame = true;
        } else if (frame.encoding === "delta" && Array.isArray(frame.deltaRows)) {
          for (const patch of frame.deltaRows) {
            if (Array.isArray(patch) && patch[0] === 0) {
              headerRow = patch[1];
            }
          }
          sawSurfaceFrame = true;
        }
        if (sawSurfaceFrame) {
          const generation = generationFromHeader();
          if (generation !== undefined) {
            samples.push({
              timestamp: performance.now(),
              generation,
            });
          }
        }
      }
      return value;
    };

    function generationFromHeader(): number | undefined {
      const header = rowText(headerRow);
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
    // The Life auto-tick loop sleeps its authored 200ms interval between
    // generations, so the observable floor is interval + pipeline time. The
    // chunked WASI resolve (depth-capped drain-and-rerun fixpoint) adds a
    // few passes of resolve work per frame; 300ms keeps the assertion at
    // "ticks are not starved" without encoding pre-chunking timer slack.
    expect(millisecondsPerGeneration).toBeLessThanOrEqual(300);
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
