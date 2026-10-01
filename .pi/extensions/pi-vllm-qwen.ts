import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Project provider extension: registers the local vLLM OpenAI-compatible
 * endpoint (see docker-compose.yml, port 8000, host networking) as provider
 * "vllm". Model IDs are read from the repo root models.json so this stays in
 * sync with the compose profiles.
 */

const BASE_URL = "http://localhost:8000/v1";

// Per-model context limits from docker-compose.yml (--max-model-len).
const CONTEXT_WINDOWS: Record<string, number> = {
  "nvidia/Qwen3.6-27B-NVFP4": 262144,
  "nvidia/Qwen3.6-35B-A3B-NVFP4": 262144,
  "nvidia/Qwen3.8-27B-NVFP4": 262144,
  "unsloth/Qwen3.8-27B-NVFP4": 1048576,
};
const DEFAULT_CONTEXT_WINDOW = 262144;
const MAX_TOKENS = 32768;

interface RepoModelEntry {
  id: string;
}

function loadModelIds(): string[] {
  let dir: string;
  try {
    dir = new URL("..", import.meta.url).pathname; // .pi/extensions -> .pi/
  } catch {
    dir = join(process.cwd(), ".pi", "extensions");
  }
  const modelsFile = join(dir, "..", "models.json");
  const data = JSON.parse(readFileSync(modelsFile, "utf8")) as RepoModelEntry[];
  return data.map((m) => m.id);
}

export default function (pi: ExtensionAPI) {
  pi.registerProvider("vllm-qwen", {
    name: "vLLM Qwen 3.x (local)",
    baseUrl: BASE_URL,
    apiKey: "vllm", // dummy key; vLLM does not authenticate
    api: "openai-completions",
    models: loadModelIds().map((id) => ({
      id,
      name: id,
      input: ["text", "image"] as ("text" | "image")[],
      reasoning: true,
      contextWindow: CONTEXT_WINDOWS[id] ?? DEFAULT_CONTEXT_WINDOW,
      maxTokens: MAX_TOKENS,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    })),
  });
}
