import { expect, test } from "bun:test";
import { webkit } from "playwright";

import { serveBuiltWebExample } from "./built-app-server.ts";

declare global {
  interface Window {
    __swiftTUIWebKitCounter?: {
      frameCount: number;
      count: number | undefined;
    };
  }
}

const soakMilliseconds = Number(
  process.env.WEBEXAMPLE_WEBKIT_SOAK_MS ?? "3000",
);
const journeyQuery = process.env.WEBEXAMPLE_WEBKIT_QUERY ?? "";

test("WebExample counter survives the WebKit WASI journey", async () => {
  const server = serveBuiltWebExample();
  const browser = await webkit.launch();
  const page = await browser.newPage({
    viewport: { width: 1280, height: 900 },
  });
  const runtimeErrors: string[] = [];
  page.on("pageerror", (error) => runtimeErrors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") runtimeErrors.push(message.text());
  });

  await page.addInitScript(() => {
    const originalParse = JSON.parse;
    const probe = { frameCount: 0, count: undefined as number | undefined };
    let rows: WebHostSurfaceCell[][] = [];
    Object.defineProperty(window, "__swiftTUIWebKitCounter", {
      configurable: true,
      value: probe,
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
        probe.frameCount += 1;
        const match = rows.map(rowText).join("\n").match(/\bCount:\s*(\d+)/);
        probe.count = match ? Number(match[1]) : probe.count;
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

  const fatalPattern = /call stack|stack size|stack overflow|unreachable|out of memory/i;

  try {
    const url = journeyQuery ? `${server.url.href}?${journeyQuery}` : server.url.href;
    await page.goto(url, { waitUntil: "domcontentloaded" });
    await page.waitForFunction(
      () => globalThis.crossOriginIsolated === true,
      undefined,
      { timeout: 10_000 },
    );
    await page.waitForSelector('[role="button"][data-focused="true"]', {
      state: "attached",
      timeout: 60_000,
    });
    await page.waitForFunction(
      () => window.__swiftTUIWebKitCounter?.count === 0,
      undefined,
      { polling: 100, timeout: 60_000 },
    );

    const increment = page.locator('[role="button"][data-focused="true"]');
    for (let expected = 1; expected <= 20; expected += 1) {
      await increment.press("Enter");
      await page.waitForFunction(
        (count) => window.__swiftTUIWebKitCounter?.count === count,
        expected,
        { polling: 100, timeout: 60_000 },
      );
    }

    await page.setViewportSize({ width: 760, height: 560 });
    await page.waitForTimeout(soakMilliseconds);

    const result = await page.evaluate(() => ({
      probe: window.__swiftTUIWebKitCounter,
      hasStartupError: document.querySelector(".example-error") !== null,
    }));
    const fatalErrors = runtimeErrors.filter((message) => fatalPattern.test(message));
    expect(result.probe?.count).toBe(20);
    expect(result.probe?.frameCount ?? 0).toBeGreaterThanOrEqual(21);
    expect(result.hasStartupError).toBe(false);
    expect(fatalErrors).toEqual([]);
  } finally {
    await page.close();
    await browser.close();
    server.stop(true);
  }
}, soakMilliseconds + 120_000);

type WebHostSurfaceCell = [
  column: number,
  text: string,
  span: number,
  style: number,
];
