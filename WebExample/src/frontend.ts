// frontend.ts
//
// The reference embedding path for a single SwiftTUI scene. The Swift app is
// the same CounterApp used by the terminal and native SwiftUI hosts.

import {
  createWebHostApp,
  type WebHostAppController,
  type WebHostSceneRuntimeOptions,
} from "@swifttui/web";
import {
  createWasmSceneRuntimeFactory,
  type WasmSceneRuntimeHandle,
  type WasmSceneResizeEvent,
} from "@swifttui/web/wasi";
import {
  defaultStyle,
  marketingStyle,
  terminalAppManifestPath,
  terminalAppWasmPath,
} from "./app-data.ts";
import "./index.css";

const terminalAppManifestUrl = new URL(terminalAppManifestPath, import.meta.url);
const terminalAppWasmUrl = new URL(terminalAppWasmPath, import.meta.url);
const backtabSequence = new TextEncoder().encode("[Z");
const isMarketingEmbed =
  new URLSearchParams(window.location.search).get("embed") === "marketing";
const activeStyle = isMarketingEmbed ? marketingStyle : defaultStyle;

document.documentElement.classList.toggle("is-marketing-embed", isMarketingEmbed);

interface WebHostFrameDiagnosticRecord {
  format: "swift-tui-frame-diagnostics-v1";
  header: string[];
  fields: string[];
}

type WebExampleSceneRuntimeOptions = WebHostSceneRuntimeOptions & {
  onFrameDiagnostic?: (diagnostic: WebHostFrameDiagnosticRecord) => void;
};

try {
  await bootstrap();
} catch (error: unknown) {
  renderStartupError(error);
  console.error("Failed to start WebExample:", error);
}

function rootEl(): HTMLDivElement {
  const root = document.querySelector<HTMLDivElement>("#root");
  if (!root) throw new Error("missing root element");
  return root;
}

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  init?: {
    class?: string;
    text?: string;
    attrs?: Record<string, string>;
    dataset?: Record<string, string>;
    children?: ReadonlyArray<Node>;
  },
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (init?.class) node.className = init.class;
  if (init?.text !== undefined) node.textContent = init.text;
  for (const [key, value] of Object.entries(init?.attrs ?? {})) {
    node.setAttribute(key, value);
  }
  for (const [key, value] of Object.entries(init?.dataset ?? {})) {
    node.dataset[key] = value;
  }
  for (const child of init?.children ?? []) node.append(child);
  return node;
}

function renderStartupError(error: unknown): void {
  const root = document.querySelector<HTMLDivElement>("#root");
  if (!root) return;
  root.replaceChildren();

  const message = error instanceof Error ? error.message : String(error);
  const retry = el("button", {
    class: "example-action",
    text: "Retry",
    attrs: { type: "button" },
  });
  retry.addEventListener("click", () => window.location.reload());

  root.append(
    el("main", {
      class: "example-error",
      attrs: { "aria-live": "assertive" },
      children: [
        el("p", { class: "example-kicker", text: "SwiftTUIWASI" }),
        el("h1", { text: "The counter could not start." }),
        el("p", {
          text: "Reload the runtime or inspect the browser embedding source.",
        }),
        el("pre", {
          class: "example-code-block",
          children: [el("code", { text: message })],
        }),
        el("div", {
          class: "example-error-actions",
          children: [
            retry,
            el("a", {
              class: "example-action example-action--quiet",
              text: "View source",
              attrs: {
                href:
                  "https://github.com/SwiftTUI/swift-tui-examples/tree/main/WebExample",
                target: "_blank",
                rel: "noreferrer noopener",
              },
            }),
          ],
        }),
      ],
    }),
  );
}

async function bootstrap(): Promise<void> {
  const root = rootEl();
  root.replaceChildren();

  const terminalHost = el("div", {
    class: "terminal-host",
    dataset: { terminalHost: "true" },
  });
  const terminalLabel = el("span", {
    class: "terminal-label",
    text: "Counter",
  });
  const terminalStatus = el("span", {
    class: "terminal-status",
    text: "Starting SwiftTUIWASI",
    attrs: { "aria-live": "polite" },
  });
  const shell = el("main", {
    class: "terminal-shell",
    dataset: { state: "loading" },
    children: [
      el("div", {
        class: "terminal-topline",
        children: [
          el("div", {
            children: [
              terminalLabel,
              el("span", {
                class: "terminal-caption",
                text: "The same CounterApp, hosted in the browser",
              }),
            ],
          }),
          terminalStatus,
        ],
      }),
      el("div", {
        class: "terminal-frame",
        dataset: { terminalFrame: "true" },
        children: [terminalHost],
      }),
    ],
  });
  root.append(shell);

  const sceneRuntimes = new Map<string, WasmSceneRuntimeHandle>();
  let controller: WebHostAppController | undefined;
  let lastResizeEvent: WasmSceneResizeEvent | undefined;
  const updateMetadata = (event?: WasmSceneResizeEvent) => {
    if (!controller) return;
    const activeScene = controller.scenes.find(
      (scene) => scene.id === controller?.selectedSceneId,
    );
    terminalHost.dataset.sceneId = controller.selectedSceneId;
    terminalHost.dataset.sceneTitle =
      activeScene?.title ?? activeScene?.id ?? controller.selectedSceneId;
    if (event) terminalHost.dataset.size = `${event.columns}x${event.rows}`;
  };

  controller = await createController(
    terminalHost,
    (event) => {
      lastResizeEvent = event;
      updateMetadata(event);
    },
    (runtime) => sceneRuntimes.set(runtime.descriptor.id, runtime),
  );
  installShiftTabPassthrough(terminalHost, () => controller, sceneRuntimes);

  const defaultScene =
    controller.scenes.find((scene) => scene.isDefault)?.id ??
    controller.scenes[0]?.id ??
    "counter";
  await controller.switchScene(defaultScene);
  updateMetadata(lastResizeEvent);

  await waitForCommittedFrame(terminalHost);
  shell.dataset.state = "ready";
  terminalStatus.textContent = "Ready";
  window.parent.postMessage(
    { type: "swifttui-demo-ready", sceneId: controller.selectedSceneId },
    window.location.origin,
  );
}

async function createController(
  mount: HTMLElement,
  onSceneResize: (event: WasmSceneResizeEvent) => void,
  onRuntimeCreated: (runtime: WasmSceneRuntimeHandle) => void,
): Promise<WebHostAppController> {
  const wasmRuntimeFactory = createWasmSceneRuntimeFactory(terminalAppWasmUrl, {
    onSceneResize,
    onRuntimeCreated,
    workerModuleURL: new URL("./wasm-scene-worker.js", import.meta.url),
    executionMode: executionModeFromQuery(),
  });

  return await createWebHostApp({
    mount,
    manifestUrl: terminalAppManifestUrl,
    style: activeStyle,
    initialSceneId: "counter",
    environment: {
      TUIGUI_APP_NAME: "SwiftTUI Counter",
      ...(frameDiagnosticsEnabled() ? { TUIGUI_FRAME_DIAGNOSTICS: "1" } : {}),
      ...resolveProfileOverridesFromQuery(),
    },
    sceneRuntimeFactory: (options) =>
      wasmRuntimeFactory(webExampleRuntimeOptions(options)),
  });
}

function waitForCommittedFrame(
  terminalHost: HTMLElement,
  timeoutMilliseconds = 20_000,
): Promise<void> {
  const startedAt = performance.now();

  return new Promise((resolve, reject) => {
    const inspect = () => {
      const canvas = terminalHost.querySelector<HTMLCanvasElement>(
        "canvas.webhost-scene__surface",
      );
      if (canvas && canvas.width > 0 && canvas.height > 0 && canvasHasContent(canvas)) {
        resolve();
        return;
      }
      if (performance.now() - startedAt >= timeoutMilliseconds) {
        reject(new Error("The runtime started, but no committed frame arrived."));
        return;
      }
      window.setTimeout(inspect, 100);
    };
    inspect();
  });
}

function canvasHasContent(canvas: HTMLCanvasElement): boolean {
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (!context) return false;
  const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
  const step = Math.max(4, Math.floor(pixels.length / 24_000 / 4) * 4);
  let baseline: string | undefined;
  let differences = 0;

  for (let index = 0; index < pixels.length; index += step) {
    const alpha = pixels[index + 3] ?? 0;
    if (alpha === 0) continue;
    const sample = `${pixels[index]}:${pixels[index + 1]}:${pixels[index + 2]}:${alpha}`;
    if (baseline === undefined) baseline = sample;
    else if (sample !== baseline && ++differences >= 4) return true;
  }
  return false;
}

function frameDiagnosticsEnabled(): boolean {
  const searchParams = new URLSearchParams(window.location.search);
  if (
    searchParams.get("frameDiagnostics") === "1" ||
    searchParams.get("diagnostics") === "1"
  ) {
    return true;
  }
  try {
    return localStorage.swiftTUIFrameDiagnostics === "1";
  } catch {
    return false;
  }
}

function executionModeFromQuery(): "worker" | "main-thread" | "auto" {
  const mode = new URLSearchParams(window.location.search).get("executionMode");
  return mode === "worker" || mode === "main-thread" ? mode : "auto";
}

function resolveProfileOverridesFromQuery(): Record<string, string> {
  const searchParams = new URLSearchParams(window.location.search);
  const overrides: Record<string, string> = {};
  const leanProfile = searchParams.get("leanProfile");
  if (leanProfile === "0" || leanProfile === "1") {
    overrides.SWIFTTUI_STACK_LEAN_PROFILE = leanProfile;
  }
  const depthLimit = searchParams.get("depthLimit");
  if (depthLimit !== null && /^\d+$/.test(depthLimit)) {
    overrides.SWIFTTUI_RESOLVE_DEPTH_LIMIT = depthLimit;
  }
  const leanReuse = searchParams.get("leanReuse");
  if (leanReuse === "0" || leanReuse === "1") {
    overrides.SWIFTTUI_LEAN_RETAINED_REUSE = leanReuse;
  }
  const renderMode = searchParams.get("renderMode");
  if (renderMode === "async" || renderMode === "async-no-cancel") {
    overrides.TERMUI_RENDER_MODE = renderMode;
  }
  const presentedProgressGuard = searchParams.get("presentedProgressGuard");
  if (presentedProgressGuard === "0" || presentedProgressGuard === "1") {
    overrides.SWIFTTUI_PRESENTED_PROGRESS_GUARD = presentedProgressGuard;
  }
  return overrides;
}

function webExampleRuntimeOptions(
  options: WebHostSceneRuntimeOptions,
): WebHostSceneRuntimeOptions {
  const runtimeOptions: WebExampleSceneRuntimeOptions = {
    ...options,
    synchronizeAccessibilityFocus: !isMarketingEmbed,
    wheelMode: isMarketingEmbed ? "chain" : "capture",
    onFrameDiagnostic: collectFrameDiagnostic,
  };
  return runtimeOptions;
}

function collectFrameDiagnostic(diagnostic: WebHostFrameDiagnosticRecord): void {
  const row = Object.fromEntries(
    diagnostic.header.map((key, index) => [key, diagnostic.fields[index] ?? ""]),
  );
  console.debug("SwiftTUI frame", row);
}

function installShiftTabPassthrough(
  terminalHost: HTMLElement,
  getController: () => WebHostAppController | undefined,
  sceneRuntimes: ReadonlyMap<string, WasmSceneRuntimeHandle>,
): void {
  terminalHost.addEventListener(
    "keydown",
    (event) => {
      if (
        event.key !== "Tab" ||
        !event.shiftKey ||
        event.altKey ||
        event.ctrlKey ||
        event.metaKey ||
        event.defaultPrevented
      ) {
        return;
      }
      const controller = getController();
      if (!controller || !terminalHost.contains(event.target as Node)) return;
      const runtime = sceneRuntimes.get(controller.selectedSceneId);
      if (!runtime) return;
      event.preventDefault();
      event.stopPropagation();
      runtime.sendInput(backtabSequence);
    },
    { capture: true },
  );
}
