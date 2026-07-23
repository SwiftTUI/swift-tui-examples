import { expect, test } from "bun:test";
import { chromium } from "playwright";

import { serveBuiltWebExample } from "./built-app-server.ts";

interface DamageSample {
  hasDamage: boolean;
  dirtyRows: number;
  count: number | undefined;
}

declare global {
  interface Window {
    __swiftTUIDamageSamples?: DamageSample[];
  }
}

test("Counter activation emits raster damage for the changed frame", async () => {
  const server = serveBuiltWebExample();
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: 1280, height: 900 },
  });

  await page.addInitScript(() => {
    const originalParse = JSON.parse;
    const samples: DamageSample[] = [];
    let rows: WebHostSurfaceCell[][] = [];
    Object.defineProperty(window, "__swiftTUIDamageSamples", {
      configurable: true,
      value: samples,
    });

    JSON.parse = function patchedJSONParse(
      text: string,
      reviver?: Parameters<typeof JSON.parse>[1],
    ) {
      const value = originalParse.call(this, text, reviver);
      const frame = value as {
        width?: unknown;
        height?: unknown;
        rows?: WebHostSurfaceCell[][];
        deltaRows?: [number, WebHostSurfaceCell[]][];
        encoding?: unknown;
        damage?: { textRows?: unknown[] };
      };
      if (
        frame &&
        typeof frame === "object" &&
        typeof frame.width === "number" &&
        typeof frame.height === "number"
      ) {
        if (Array.isArray(frame.rows)) rows = frame.rows.slice();
        else if (frame.encoding === "delta" && Array.isArray(frame.deltaRows)) {
          for (const [index, row] of frame.deltaRows) rows[index] = row;
        }
        const match = rows.map(rowText).join("\n").match(/\bCount:\s*(\d+)/);
        samples.push({
          hasDamage:
            frame.encoding === "delta" ||
            Boolean(frame.damage),
          dirtyRows:
            frame.encoding === "delta" && Array.isArray(frame.deltaRows)
              ? frame.deltaRows.length
              : Array.isArray(frame.damage?.textRows)
                ? frame.damage.textRows.length
                : 0,
          count: match ? Number(match[1]) : undefined,
        });
      }
      return value;
    };

    function rowText(row: WebHostSurfaceCell[]): string {
      let output = "";
      let cursor = 0;
      for (const [column, cellText, span] of row ?? []) {
        if (column > cursor) output += " ".repeat(column - cursor);
        output += cellText;
        cursor = column + Math.max(1, span);
      }
      return output;
    }
  });

  try {
    await page.goto(server.url.href, { waitUntil: "domcontentloaded" });
    await page.waitForSelector('[role="button"][data-focused="true"]', {
      state: "attached",
      timeout: 30_000,
    });
    await page.waitForFunction(
      () => window.__swiftTUIDamageSamples?.some((sample) => sample.count === 0),
      undefined,
      { polling: 100, timeout: 30_000 },
    );
    const baseline = await page.evaluate(
      () => window.__swiftTUIDamageSamples?.length ?? 0,
    );

    await page.locator('[role="button"][data-focused="true"]').press("Enter");
    await page.waitForFunction(
      () => window.__swiftTUIDamageSamples?.some((sample) => sample.count === 1),
      undefined,
      { polling: 100, timeout: 30_000 },
    );

    const changedSamples = await page.evaluate(
      (start) => (window.__swiftTUIDamageSamples ?? []).slice(start),
      baseline,
    );
    expect(changedSamples.some((sample) => sample.count === 1)).toBe(true);
    expect(
      changedSamples.some((sample) => sample.hasDamage && sample.dirtyRows > 0),
    ).toBe(true);
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
