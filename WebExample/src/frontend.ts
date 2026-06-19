// frontend.ts
//
// The minimal embedding example: mounts a SwiftTUI WASI build into a
// browser canvas using the WebHost host, with a scene picker.
//
// This file is the reference for "how do I embed a SwiftTUI app in the browser?".
//
// Boot order:
//   1. mount WebHost against ../TerminalApp/dist/{scene-manifest.json, app.wasm}.
//   2. render the scene picker around a viewport-sized canvas.
//
// Cross-origin isolation (required for SharedArrayBuffer-backed stdin) is
// expected to come from the host's HTTP headers — see ../README.md and the
// COOP/COEP headers set by built-app-server.ts and the deploy host.

import {
  createWebHostApp,
  WebHostSceneRuntime,
  type WebHostAppController,
  type WebHostSceneRuntimeOptions,
  type WebHostTerminalStyle,
} from "@swifttui/web";
import "./index.css";
import {
  defaultStyle,
  fallbackManifest,
  marketingStyle,
  terminalAppManifestPath,
  terminalAppWasmPath,
} from "./app-data.ts";
import {
  createWasmSceneRuntimeFactory,
  type WasmSceneRuntimeHandle,
  type WasmSceneResizeEvent,
} from "@swifttui/web/wasi";

const terminalAppManifestUrl = new URL(terminalAppManifestPath, import.meta.url);
const terminalAppWasmUrl = new URL(terminalAppWasmPath, import.meta.url);
const backtabSequence = new TextEncoder().encode("[Z");
const isPassiveMarketingEmbed = new URLSearchParams(window.location.search).get("embed")
  === "marketing";
const activeStyle = isPassiveMarketingEmbed ? marketingStyle : defaultStyle;

// Responsive font sizing.
//
// The WebHost derives the terminal column count from `mountWidth / cellWidth`,
// and `cellWidth` scales with `fontSize`. At the default font size a narrow
// phone viewport only yields a few dozen columns — too few for this app's full
// control row, which then clips at the terminal's right edge. Shrink the font
// on narrow viewports so the terminal keeps enough columns for the layout,
// floored at a still-legible size. Wide viewports are unaffected.
const DEFAULT_FONT_SIZE = 15;
const MIN_FONT_SIZE = 8;
const TARGET_COLUMNS = 72;
// Approximate monospace advance width as a fraction of the font size; matches
// the WebHost's own fallback ratio in WebHostSceneRuntime.measureCells.
const CELL_WIDTH_RATIO = 0.62;

function viewportWidth(): number {
  return window.innerWidth || document.documentElement.clientWidth || 0;
}

function responsiveFontSize(baseFontSize: number): number {
  const width = viewportWidth();
  if (!width) return baseFontSize;
  const fit = Math.round(width / (TARGET_COLUMNS * CELL_WIDTH_RATIO));
  return Math.max(MIN_FONT_SIZE, Math.min(baseFontSize, fit));
}

function withResponsiveFontSize(style: WebHostTerminalStyle): WebHostTerminalStyle {
  return { ...style, fontSize: responsiveFontSize(style.fontSize ?? DEFAULT_FONT_SIZE) };
}

function installResponsiveFontSize(
  controller: WebHostAppController,
  baseStyle: WebHostTerminalStyle,
): void {
  const baseFontSize = baseStyle.fontSize ?? DEFAULT_FONT_SIZE;
  let current = responsiveFontSize(baseFontSize);
  let pending = 0;
  window.addEventListener("resize", () => {
    if (pending) cancelAnimationFrame(pending);
    pending = requestAnimationFrame(() => {
      pending = 0;
      const next = responsiveFontSize(baseFontSize);
      if (next !== current) {
        current = next;
        controller.setStyle({ fontSize: next });
      }
    });
  });
}

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
  // eslint-disable-next-line no-console
  console.error("Failed to start WebExample:", error);
}

// ---------------------------------------------------------------------------
// Bootstrap

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
  for (const [k, v] of Object.entries(init?.attrs ?? {})) node.setAttribute(k, v);
  for (const [k, v] of Object.entries(init?.dataset ?? {})) node.dataset[k] = v;
  for (const child of init?.children ?? []) node.append(child);
  return node;
}

function renderStartupError(error: unknown): void {
  const root = document.querySelector<HTMLDivElement>("#root");
  if (!root) return;
  root.replaceChildren();

  const message = error instanceof Error ? error.message : String(error);
  const stack = error instanceof Error && error.stack ? `\n\n${error.stack}` : "";

  const codeBlock = el("pre", {
    class: "example-code-block",
    children: [el("code", { text: `${message}${stack}` })],
  });

  root.append(
    el("div", {
      class: "example-shell example-shell--error",
      children: [
        el("main", {
          class: "example-error",
          children: [
            el("p", { class: "example-eyebrow", text: "Startup error" }),
            el("h1", { text: "Could not boot the embedded SwiftTUI app." }),
            el("p", {
              text:
                "The browser runtime did not start. The error is below; reload to retry.",
            }),
            codeBlock,
          ],
        }),
      ],
    }),
  );
}

async function bootstrap(): Promise<void> {
  const root = rootEl();
  root.replaceChildren();

  // Static shell. A host page that adopts this pattern can render whatever
  // chrome it wants around the .terminal-shell element — only the
  // .terminal-shell + its data-* hooks are load-bearing.
  const scenes = el("div", {
    class: "scene-select",
    attrs: { "aria-label": "Scene selector" },
    dataset: { scenes: "true" },
  });
  const terminalHost = el("div", {
    class: "terminal-host",
    dataset: { terminalHost: "true" },
  });
  const terminalFrame = el("div", {
    class: "terminal-frame",
    dataset: { terminalFrame: "true" },
    children: [terminalHost],
  });
  const terminalLabel = el("span", { class: "terminal-label" });
  const terminalCaption = el("span", {
    class: "terminal-caption",
    text: "A SwiftTUI app. Running in the Platforms/Web host.",
  });

  const shell = el("div", {
    class: "example-shell",
    children: [
      el("main", {
        class: "example-main",
        children: [
          el("div", {
            class: "terminal-shell",
            children: [
              el("div", {
                class: "terminal-topline",
                children: [
                  el("div", {
                    class: "terminal-topline-copy",
                    children: [terminalLabel, terminalCaption],
                  }),
                  scenes,
                ],
              }),
              el("div", {
                class: "terminal-frame-shell",
                children: [terminalFrame],
              }),
            ],
          }),
        ],
      }),
    ],
  });
  root.append(shell);

  const sceneSizes = new Map<string, string>();
  const sceneRuntimes = new Map<string, WasmSceneRuntimeHandle>();
  let controller: WebHostAppController | undefined;
  const updateHostMetadata = () => {
    if (!controller) return;
    const activeScene = controller.scenes.find(
      (scene) => scene.id === controller?.selectedSceneId,
    );
    const activeLabel = activeScene?.title ?? activeScene?.id ?? controller.selectedSceneId;
    const sizeLabel = sceneSizes.get(controller.selectedSceneId);
    terminalHost.dataset.sceneId = controller.selectedSceneId;
    terminalHost.dataset.sceneTitle = activeLabel;
    terminalHost.dataset.size = sizeLabel ?? "";
    terminalLabel.textContent = activeLabel;
  };

  controller = await createController(
    terminalHost,
    (event) => {
      sceneSizes.set(event.sceneId, `${event.columns}x${event.rows}`);
      updateHostMetadata();
    },
    (runtime) => {
      sceneRuntimes.set(runtime.descriptor.id, runtime);
    },
  );
  installShiftTabPassthrough(terminalHost, () => controller, sceneRuntimes);
  installResponsiveFontSize(controller, activeStyle);
  const defaultScene =
    controller.scenes.find((scene) => scene.isDefault)?.id ?? controller.selectedSceneId;
  await controller.switchScene(defaultScene);
  renderSceneButtons(controller, scenes, () => {
    updateHostMetadata();
  });
  updateHostMetadata();
}

// ---------------------------------------------------------------------------
// Controller wiring

async function createController(
  mount: HTMLElement,
  onSceneResize: (event: WasmSceneResizeEvent) => void,
  onRuntimeCreated: (runtime: WasmSceneRuntimeHandle) => void,
): Promise<WebHostAppController> {
  try {
    const wasmRuntimeFactory = createWasmSceneRuntimeFactory(terminalAppWasmUrl, {
      onSceneResize,
      onRuntimeCreated,
      workerModuleURL: new URL("./wasm-scene-worker.js", import.meta.url),
    });

    return await createWebHostApp({
      mount,
      manifestUrl: terminalAppManifestUrl,
      style: withResponsiveFontSize(activeStyle),
      initialSceneId: "main",
      environment: {
        TUIGUI_APP_NAME: "WebExample",
        ...(frameDiagnosticsEnabled() ? { TUIGUI_FRAME_DIAGNOSTICS: "1" } : {}),
      },
      sceneRuntimeFactory: (options) => wasmRuntimeFactory(webExampleRuntimeOptions(options)),
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("Falling back to the local preview manifest:", error);
    return await createWebHostApp({
      mount,
      manifest: fallbackManifest,
      style: withResponsiveFontSize(activeStyle),
      initialSceneId: fallbackManifest.defaultSceneId,
      sceneRuntimeFactory: (options) => new WebHostSceneRuntime(webExampleRuntimeOptions(options)),
    });
  }
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

function webExampleRuntimeOptions(
  options: WebHostSceneRuntimeOptions
): WebHostSceneRuntimeOptions {
  const runtimeOptions: WebExampleSceneRuntimeOptions = {
    ...passiveEmbedOptions(options),
    onFrameDiagnostic: collectFrameDiagnostic,
  };
  return runtimeOptions;
}

function passiveEmbedOptions(
  options: WebHostSceneRuntimeOptions
): WebHostSceneRuntimeOptions {
  if (!isPassiveMarketingEmbed) {
    return {
      ...options,
      // The standalone /webexample/ page is a full-screen app with no page to
      // scroll past, so it keeps the legacy "capture" behavior (the inner view
      // always handles the wheel). The library default is "chain", which only
      // matters for embeds like the marketing iframe below.
      wheelMode: "capture",
    };
  }

  return {
    ...options,
    synchronizeAccessibilityFocus: false,
    // Scroll-chaining: the embedded view captures the wheel only while a
    // scrollable region under the pointer can still scroll in that direction;
    // at its edge (or over non-scrollable content) the wheel falls through and
    // the host page scrolls. Scenes with no ScrollView stay fully passive.
    // This is also the library default now; set explicitly for clarity.
    wheelMode: "chain",
  };
}

function collectFrameDiagnostic(diagnostic: WebHostFrameDiagnosticRecord): void {
  const row = Object.fromEntries(
    diagnostic.header.map((key, index) => [key, diagnostic.fields[index] ?? ""]),
  );
  // eslint-disable-next-line no-console
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

      const path = typeof event.composedPath === "function" ? event.composedPath() : [];
      const eventOriginatedInTerminal =
        path.includes(terminalHost) ||
        (event.target instanceof Node && terminalHost.contains(event.target));
      if (!eventOriginatedInTerminal) return;

      const controller = getController();
      if (!controller) return;

      const runtime = sceneRuntimes.get(controller.selectedSceneId);
      if (!runtime) return;

      event.preventDefault();
      event.stopPropagation();
      runtime.sendInput(backtabSequence);
    },
    { capture: true },
  );
}

// ---------------------------------------------------------------------------
// Scene picker

function renderSceneButtons(
  controller: WebHostAppController,
  container: HTMLElement,
  onSelectionChanged: () => void,
): void {
  container.replaceChildren();
  if (controller.scenes.length === 0) return;

  const activeLabel = () => {
    const active = controller.scenes.find((s) => s.id === controller.selectedSceneId);
    return active?.title ?? active?.id ?? controller.selectedSceneId;
  };

  const sceneValueSpan = el("span", {
    text: activeLabel(),
    dataset: { sceneValue: "true" },
  });
  const trigger = el("button", {
    class: "scene-select-trigger",
    attrs: {
      type: "button",
      "aria-haspopup": "listbox",
      "aria-expanded": "false",
    },
    children: [
      el("span", { class: "scene-select-label", text: "Scene:" }),
      document.createTextNode(" "),
      sceneValueSpan,
      document.createTextNode(" "),
      el("span", { class: "scene-select-chevron" }),
    ],
  });

  const menu = el("div", {
    class: "scene-select-menu",
    attrs: { role: "listbox" },
    dataset: { open: "false" },
  });

  for (const scene of controller.scenes) {
    const option = el("button", {
      class: "scene-select-option",
      attrs: { type: "button", role: "option" },
      dataset: { sceneId: scene.id },
      text: scene.title ?? scene.id,
    });
    option.addEventListener("click", async () => {
      await controller.switchScene(scene.id);
      updateSceneSelection(controller, container);
      onSelectionChanged();
      closeMenu();
    });
    menu.append(option);
  }

  const closeMenu = () => {
    trigger.setAttribute("aria-expanded", "false");
    menu.dataset.open = "false";
  };

  trigger.addEventListener("click", () => {
    const isOpen = trigger.getAttribute("aria-expanded") === "true";
    trigger.setAttribute("aria-expanded", String(!isOpen));
    menu.dataset.open = String(!isOpen);
  });

  document.addEventListener("click", (event) => {
    if (!container.contains(event.target as Node)) closeMenu();
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && menu.dataset.open === "true") {
      closeMenu();
      trigger.focus();
    }
  });

  container.append(trigger, menu);
  updateSceneSelection(controller, container);
}

function updateSceneSelection(
  controller: WebHostAppController,
  container: HTMLElement,
): void {
  const valueEl = container.querySelector<HTMLElement>("[data-scene-value]");
  if (valueEl) {
    const active = controller.scenes.find((s) => s.id === controller.selectedSceneId);
    valueEl.textContent = active?.title ?? active?.id ?? controller.selectedSceneId;
  }

  for (const option of container.querySelectorAll<HTMLButtonElement>(".scene-select-option")) {
    const isActive = option.dataset.sceneId === controller.selectedSceneId;
    option.setAttribute("aria-selected", String(isActive));
  }
}
