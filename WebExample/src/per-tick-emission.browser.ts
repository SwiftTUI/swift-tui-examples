import { expect, test } from "bun:test";
import { chromium } from "playwright";

import { serveBuiltWebExample } from "./built-app-server.ts";

// Per-tick frame emission under reuse — the durable regression gate for the
// 0.1.9 live coalescing incident (61 Life generations → 16 wire frames on
// non-lean chromium). The suppression mechanism is completed-frame DISPOSAL,
// not transport publication: under `renderMode=async` a completed visual-only
// frame is dropped whenever a newer intent is pending at completion
// (`dropped_completed` / `drop_visual_only`, bounded by
// `maxConsecutiveVisualOnlyDrops = 2`), which saturates at one present per
// three completed frames. `renderMode=async-no-cancel` forces ordered commits
// and removes the drop and pre-start-cancel arms entirely.
//
// The defect reproduces on the locally served build with NO CPU throttling
// (measured 2026-07-20: control 0.98 wire-frames/s at 0.23 distinct-gen
// coverage vs fix 3.78 f/s at 0.86 — the same regime as the deployed site).
// Thresholds below are calibrated from those runs with margin for CI load;
// per-profile bands are deliberate — the lean profile's healthy baseline is
// its G1 intent-merge band (~0.67 coverage), NOT the non-lean fix band.
//
// Suppression fingerprint assertions live ONLY on the pre-fix control lane
// (`renderMode=async`), where they are falsifiable — under async-no-cancel a
// zero-drop assertion is tautological (the mode removes the mechanism), so
// the fix lanes assert delivered frame cadence instead.

declare global {
  interface Window {
    __perTickTap?: PerTickTap;
  }
}

interface PerTickTap {
  samples: FrameSample[];
  diagRows: DiagnosticRow[];
  sampleMark: number;
  diagMark: number;
}

interface FrameSample {
  timestamp: number;
  generation: number;
}

type DiagnosticRow = Record<string, string>;

interface SteadyWindowCapture {
  samples: FrameSample[];
  diagRows: DiagnosticRow[];
}

const steadyWindowMilliseconds = 30_000;

// One browser + one server for every lane, a fresh isolated context per lane:
// repeated chromium.launch() calls inside a single bun test process stall
// intermittently (observed 2026-07-20 — every second in-process relaunch hung
// while the same lane passed in isolation), and per-context isolation keeps
// the fresh-profile semantics the lanes need.
test("per-tick frame emission bands across profiles and render modes", async () => {
  const server = serveBuiltWebExample();
  const browser = await chromium.launch();
  try {
    const control = await captureSteadyWindow(
      server.url.href,
      browser,
      "leanProfile=0&renderMode=async",
    );

    // Red-first witness: the harness must be able to SEE the suppression. If
    // this lane stops producing drop records, the control environment drifted
    // (or disposal policy changed underneath) and the gate lost its meaning.
    expect(countTailState(control.diagRows, "dropped_completed")).toBeGreaterThanOrEqual(10);
    const controlCoverage = distinctGenerationCoverage(control.samples);
    expect(controlCoverage.generationDelta).toBeGreaterThanOrEqual(24);
    // Measured 0.23 under the 2-drop saturation floor. Anything near the fix
    // band would mean the control lane no longer reproduces the defect.
    expect(controlCoverage.coverage).toBeLessThanOrEqual(0.5);

    const fixWorker = await captureSteadyWindow(
      server.url.href,
      browser,
      "leanProfile=0&renderMode=async-no-cancel",
    );
    expectPerTickCadence(fixWorker);

    const fixMainThread = await captureSteadyWindow(
      server.url.href,
      browser,
      "leanProfile=0&renderMode=async-no-cancel&executionMode=main-thread",
    );
    expectPerTickCadence(fixMainThread);

    const lean = await captureSteadyWindow(server.url.href, browser, "");

    // Bounded, never zero-required: a single legitimate cancel+replay is not a
    // regression. What must NOT appear on lean is the non-lean drop cascade.
    expect(countTailState(lean.diagRows, "dropped_completed")).toBeLessThanOrEqual(2);
    expect(countTailState(lean.diagRows, "cancelled_before_start")).toBeLessThanOrEqual(3);
    const leanCoverage = distinctGenerationCoverage(lean.samples);
    expect(leanCoverage.generationDelta).toBeGreaterThanOrEqual(24);
    // Lean's healthy baseline is G1 merging only (~0.67 measured); below 0.5
    // means a disposal cascade reached the lean profile.
    expect(leanCoverage.coverage).toBeGreaterThanOrEqual(0.5);
  } finally {
    await browser.close();
    server.stop(true);
  }
}, 400_000);

function expectPerTickCadence(capture: SteadyWindowCapture): void {
  const coverage = distinctGenerationCoverage(capture.samples);
  expect(coverage.generationDelta).toBeGreaterThanOrEqual(24);

  // Measured 0.86 (worker) / 0.88 (main thread); the residual gap to 1.0 is
  // legitimate G1 intent merging when a wake spans two ticks. 0.72 keeps CI
  // margin while staying above the lean band (0.67) and far above the
  // disposal-saturated control (0.23).
  expect(coverage.coverage).toBeGreaterThanOrEqual(0.72);

  // Wire frames should track generations: fewer means merging or disposal,
  // more means duplicate presents per generation beyond animation slack.
  const sampleRatio = capture.samples.length / coverage.generationDelta;
  expect(sampleRatio).toBeGreaterThanOrEqual(0.7);
  expect(sampleRatio).toBeLessThanOrEqual(1.5);

  // Frame-count blindness guard: most consecutive wire frames must advance
  // at most one generation (measured 83-85%; control measures 0%).
  expect(consecutiveSingleStepShare(capture.samples)).toBeGreaterThanOrEqual(0.7);
}

function countTailState(diagRows: DiagnosticRow[], state: string): number {
  return diagRows.filter((row) => row.tail_job_state === state).length;
}

function distinctGenerationCoverage(samples: FrameSample[]): {
  generationDelta: number;
  coverage: number;
} {
  const generations = samples
    .map((sample) => sample.generation)
    .filter((generation) => generation > 0);
  if (generations.length < 2) {
    return { generationDelta: 0, coverage: 0 };
  }
  const generationDelta = generations[generations.length - 1]! - generations[0]!;
  const distinct = new Set(generations).size;
  return {
    generationDelta,
    coverage: generationDelta > 0 ? distinct / generationDelta : 0,
  };
}

function consecutiveSingleStepShare(samples: FrameSample[]): number {
  const generations = samples
    .map((sample) => sample.generation)
    .filter((generation) => generation > 0);
  if (generations.length < 2) {
    return 0;
  }
  let singleSteps = 0;
  for (let index = 1; index < generations.length; index += 1) {
    if (generations[index]! - generations[index - 1]! <= 1) {
      singleSteps += 1;
    }
  }
  return singleSteps / (generations.length - 1);
}

async function captureSteadyWindow(
  serverURL: string,
  browser: import("playwright").Browser,
  query: string,
): Promise<SteadyWindowCapture> {
  const context = await browser.newContext({
    viewport: {
      width: 1280,
      height: 900,
    },
  });
  const page = await context.newPage();

  await page.addInitScript(() => {
    const tap: {
      samples: { timestamp: number; generation: number }[];
      diagRows: Record<string, string>[];
      sampleMark: number;
      diagMark: number;
    } = { samples: [], diagRows: [], sampleMark: 0, diagMark: 0 };
    Object.defineProperty(window, "__perTickTap", {
      configurable: true,
      value: tap,
    });

    // Diagnostics tap: the example's `collectFrameDiagnostic` logs every
    // frameDiagnostic wire record (presented AND suppressed outcomes) as
    // `console.debug("SwiftTUI frame", row)` on the main thread.
    const originalDebug = console.debug;
    console.debug = function patchedDebug(...args: unknown[]) {
      if (args[0] === "SwiftTUI frame" && args[1] && typeof args[1] === "object") {
        tap.diagRows.push(args[1] as Record<string, string>);
      }
      return originalDebug.apply(this, args as []);
    };

    // Surface tap: same mechanism as frame-cadence.browser.ts — keep a
    // patched header row so delta frames stay attributable to a generation.
    let headerRow: WebHostSurfaceCell[] = [];
    const originalParse = JSON.parse;
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
            tap.samples.push({
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
    const pageURL = new URL(serverURL);
    pageURL.search = query ? `?frameDiagnostics=1&${query}` : "?frameDiagnostics=1";
    await page.goto(pageURL.href, { waitUntil: "domcontentloaded" });
    await page.waitForFunction(() => globalThis.crossOriginIsolated === true, undefined, {
      timeout: 10_000,
    });
    await page.waitForSelector(".webhost-scene__surface", {
      state: "attached",
      timeout: 30_000,
    });

    // Warmup: exclude startup frames from the steady window — wait until the
    // Life generation counter has advanced at least 5 from first sight.
    await page.waitForFunction(
      () => {
        const tap = window.__perTickTap;
        if (!tap) {
          return false;
        }
        const generations = tap.samples
          .map((sample) => sample.generation)
          .filter((generation) => generation > 0);
        return generations.length > 0
          && generations[generations.length - 1]! - generations[0]! >= 5;
      },
      undefined,
      { polling: 200, timeout: 60_000 }
    );

    await page.evaluate(() => {
      const tap = window.__perTickTap!;
      tap.sampleMark = tap.samples.length;
      tap.diagMark = tap.diagRows.length;
    });
    await page.waitForTimeout(steadyWindowMilliseconds);

    return await page.evaluate(() => {
      const tap = window.__perTickTap!;
      return {
        samples: tap.samples.slice(tap.sampleMark),
        diagRows: tap.diagRows.slice(tap.diagMark),
      };
    });
  } finally {
    await context.close();
  }
}

type WebHostSurfaceCell = [
  column: number,
  text: string,
  span: number,
  style: number,
];
