import { expect, test } from "bun:test";
import { webkit } from "playwright";

import { serveBuiltWebExample } from "./built-app-server.ts";

// Safari-class coverage: JavaScriptCore executes wasm calls on the host
// thread's native stack and workers get a small fraction of the main-thread
// budget, so deep resolve descents that pass on Chromium (V8 keeps a
// separate wasm stack) overflow only on WebKit. This journey drives the
// same app the public site iframes — boot, Game of Life generations,
// scene switch, an animation press, scene re-entry, and a soak — and fails
// on the startup-error shell or any stack-overflow-class runtime error.

declare global {
  interface Window {
    __swiftTUIWebKitJourney?: JourneyProbe;
  }
}

interface JourneyProbe {
  frameCount: number;
  fullFrameCount: number;
  firstGeneration: number | undefined;
  lastGeneration: number | undefined;
  gridWidth: number;
  gridHeight: number;
  lastRows: WebHostSurfaceCell[][];
  lastFullRows: WebHostSurfaceCell[][];
}

type WebHostSurfaceCell = [
  column: number,
  text: string,
  span: number,
  style: number,
];

const soakMilliseconds = Number(
  process.env.WEBEXAMPLE_WEBKIT_SOAK_MS ?? "60000",
);

// Optional page-query override (e.g. `leanReuse=1` to exercise the
// stack-lean retained-reuse opt-in before it becomes an engine default) so
// acceptance runs can pin a profile without editing the spec. Empty keeps
// the deployed default shape.
const journeyQuery = process.env.WEBEXAMPLE_WEBKIT_QUERY ?? "";

test("WebExample survives the WebKit journey (Safari-class wasm stack budget)", async () => {
  const server = serveBuiltWebExample();
  const browser = await webkit.launch();
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

  await page.addInitScript(() => {
    const originalParse = JSON.parse;
    const probe: JourneyProbe = {
      frameCount: 0,
      fullFrameCount: 0,
      firstGeneration: undefined,
      lastGeneration: undefined,
      gridWidth: 0,
      gridHeight: 0,
      lastRows: [],
      lastFullRows: [],
    };
    Object.defineProperty(window, "__swiftTUIWebKitJourney", {
      configurable: true,
      value: probe,
    });
    JSON.parse = function patchedJSONParse(
      text: string,
      reviver?: Parameters<typeof JSON.parse>[1],
    ) {
      const value = originalParse.call(this, text, reviver);
      // The WebHost wire carries two surface shapes: full frames
      // (`version: 2` with complete `rows`) and delta frames
      // (`version: 3, encoding: "delta"` with `deltaRows` row patches).
      // Steady scenes present deltas, so the probe keeps a patched row
      // cache — a rows-only tap goes blind after the first frames.
      const frame = value as {
        width?: unknown;
        height?: unknown;
        rows?: WebHostSurfaceCell[][];
        deltaRows?: [number, WebHostSurfaceCell[]][];
        encoding?: unknown;
      };
      if (frame && typeof frame === "object"
        && typeof frame.width === "number" && typeof frame.height === "number") {
        if (Array.isArray(frame.rows)) {
          probe.frameCount += 1;
          probe.fullFrameCount += 1;
          probe.gridWidth = frame.width;
          probe.gridHeight = frame.height;
          probe.lastRows = frame.rows.slice();
          probe.lastFullRows = frame.rows.slice();
          updateGeneration();
        } else if (frame.encoding === "delta" && Array.isArray(frame.deltaRows)) {
          probe.frameCount += 1;
          probe.gridWidth = frame.width;
          probe.gridHeight = frame.height;
          for (const patch of frame.deltaRows) {
            if (Array.isArray(patch) && typeof patch[0] === "number") {
              probe.lastRows[patch[0]] = patch[1];
            }
          }
          updateGeneration();
        }
      }
      return value;
    };

    function updateGeneration(): void {
      const header = rowText(probe.lastRows[0] ?? []);
      const match = header.match(/\bgen\s*(\d+)/);
      if (!match) {
        return;
      }
      const generation = Number(match[1]);
      probe.lastGeneration = generation;
      if (probe.firstGeneration === undefined && generation > 0) {
        probe.firstGeneration = generation;
      }
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

  const fatalPattern = /call stack|stack size|stack overflow|unreachable|out of memory/i;
  const assertHealthy = async (stage: string) => {
    const bootErrorVisible = await page.evaluate(
      () => document.querySelector(".example-shell--error") !== null,
    );
    const fatal = runtimeErrors.filter((message) => fatalPattern.test(message));
    if (bootErrorVisible || fatal.length > 0) {
      throw new Error(
        `WebKit journey failed at ${stage}: bootError=${bootErrorVisible} `
          + `fatal=${JSON.stringify(fatal)} allErrors=${JSON.stringify(runtimeErrors)}`,
      );
    }
  };

  const switchScene = async (title: string) => {
    await page.click(".scene-select-trigger");
    await page.click(`.scene-select-option:text-is("${title}")`);
    await page.waitForFunction(
      (expected) => {
        const host = document.querySelector<HTMLElement>("[data-terminal-host]");
        return host?.dataset.sceneTitle === expected;
      },
      title,
      { timeout: 30_000 },
    );
  };

  const frameCount = () =>
    page.evaluate(() => window.__swiftTUIWebKitJourney?.frameCount ?? 0);

  const generationDelta = () =>
    page.evaluate(() => {
      const probe = window.__swiftTUIWebKitJourney;
      if (!probe || probe.firstGeneration === undefined
        || probe.lastGeneration === undefined) {
        return 0;
      }
      return probe.lastGeneration - probe.firstGeneration;
    });

  try {
    // 1. Boot: the Game of Life scene is the default.
    const journeyURL = journeyQuery
      ? `${server.url.href}?${journeyQuery}`
      : server.url.href;
    await page.goto(journeyURL, { waitUntil: "domcontentloaded" });
    await page.waitForFunction(() => globalThis.crossOriginIsolated === true, undefined, {
      timeout: 10_000,
    });
    await page.waitForSelector(".webhost-scene__surface", {
      state: "attached",
      timeout: 60_000,
    });
    await assertHealthy("boot");

    // 2. Life seeds and ticks: the header's generation counter advances.
    await page.waitForFunction(
      () => {
        const probe = window.__swiftTUIWebKitJourney;
        return probe !== undefined
          && probe.firstGeneration !== undefined
          && probe.lastGeneration !== undefined
          && probe.lastGeneration - probe.firstGeneration >= 24;
      },
      undefined,
      { polling: 100, timeout: 60_000 },
    );
    await assertHealthy("life-ticks");

    // 3. Scene switch: Animations boots its own runtime on demand. Its boot
    //    presents a FULL frame (the cached Life runtime keeps streaming
    //    deltas, so only a full-frame count isolates the new scene's boot).
    const fullFramesBeforeAnimations = await page.evaluate(
      () => window.__swiftTUIWebKitJourney?.fullFrameCount ?? 0,
    );
    await switchScene("Animations");
    await page.waitForFunction(
      (baseline) => (window.__swiftTUIWebKitJourney?.fullFrameCount ?? 0) > baseline,
      fullFramesBeforeAnimations,
      { polling: 100, timeout: 60_000 },
    );
    await assertHealthy("animations-boot");

    // 4. Press the "spring" curve button (a canvas cell, not a DOM node) and
    //    require the animation to stream frames.
    const springTarget = await page.evaluate(() => {
      const probe = window.__swiftTUIWebKitJourney;
      const canvas = document.querySelector(".webhost-scene__surface");
      if (!probe || !(canvas instanceof HTMLCanvasElement)
        || probe.gridWidth <= 0 || probe.gridHeight <= 0) {
        return undefined;
      }
      // Cells carry single characters, so match against the joined row text
      // and map the match back to its grid column.
      for (let rowIndex = 0; rowIndex < probe.lastFullRows.length; rowIndex += 1) {
        let text = "";
        const columns: number[] = [];
        for (const [column, cellText, span] of probe.lastFullRows[rowIndex] ?? []) {
          for (let i = 0; i < cellText.length; i += 1) {
            text += cellText[i];
            columns.push(column + Math.min(i, Math.max(1, span) - 1));
          }
        }
        const offset = text.indexOf("spring");
        if (offset < 0) {
          continue;
        }
        const column = columns[offset + 3] ?? columns[offset];
        const rect = canvas.getBoundingClientRect();
        const cellWidth = rect.width / probe.gridWidth;
        const cellHeight = rect.height / probe.gridHeight;
        return {
          x: rect.left + (column + 0.5) * cellWidth,
          y: rect.top + (rowIndex + 0.5) * cellHeight,
        };
      }
      return undefined;
    });
    expect(springTarget).toBeDefined();
    const framesBeforeSpring = await frameCount();
    await page.mouse.click(springTarget!.x, springTarget!.y);
    await page.waitForFunction(
      (baseline) => (window.__swiftTUIWebKitJourney?.frameCount ?? 0) >= baseline + 8,
      framesBeforeSpring,
      { polling: 100, timeout: 60_000 },
    );
    await assertHealthy("animations-spring");

    // 5. Re-entry: the cached Life runtime keeps ticking after the round trip.
    const deltaBeforeReentry = await generationDelta();
    await switchScene("Game of Life");
    await page.waitForFunction(
      (baseline) => {
        const probe = window.__swiftTUIWebKitJourney;
        if (!probe || probe.firstGeneration === undefined
          || probe.lastGeneration === undefined) {
          return false;
        }
        return probe.lastGeneration - probe.firstGeneration >= baseline + 6;
      },
      deltaBeforeReentry,
      { polling: 100, timeout: 60_000 },
    );
    await assertHealthy("life-reentry");

    // 6. Soak: frames must keep flowing with no stack banner for the whole
    //    window (`WEBEXAMPLE_WEBKIT_SOAK_MS` extends this for acceptance runs).
    const soakStart = Date.now();
    let lastObservedFrameCount = await frameCount();
    while (Date.now() - soakStart < soakMilliseconds) {
      await new Promise((resolve) => setTimeout(resolve, 5_000));
      const observed = await frameCount();
      expect(observed).toBeGreaterThan(lastObservedFrameCount);
      lastObservedFrameCount = observed;
      await assertHealthy(`soak+${Math.round((Date.now() - soakStart) / 1000)}s`);
    }
  } finally {
    await page.close();
    await browser.close();
    server.stop(true);
  }
}, soakMilliseconds + 360_000);
