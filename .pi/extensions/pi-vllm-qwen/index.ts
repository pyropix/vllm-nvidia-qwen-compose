import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Project provider extension: registers the local vLLM OpenAI-compatible
 * endpoint (see docker-compose.yml, port 8000, host networking) as provider
 * "vllm". Model IDs and context windows are read from the repo root models.json so
 * this stays in sync with the compose profiles.
 */

const BASE_URL = "http://localhost:8000/v1";

const MAX_TOKENS = 32768;

interface RepoModelEntry {
  id: string;
  context: number;
}

function repoRoot(): string {
  let dir: string;
  try {
    // Directory of this file: <root>/.pi/extensions/pi-vllm-qwen
    dir = new URL(".", import.meta.url).pathname;
  } catch {
    dir = join(process.cwd(), ".pi", "extensions", "pi-vllm-qwen");
  }
  // pi-vllm-qwen -> extensions -> .pi -> <root>
  return join(dir, "..", "..", "..");
}

function loadModels(): RepoModelEntry[] {
  const modelsFile = join(repoRoot(), "models.json");
  const data = JSON.parse(readFileSync(modelsFile, "utf8")) as RepoModelEntry[];
  return data;
}

export default function (pi: ExtensionAPI) {
  pi.registerProvider("vllm-qwen", {
    name: "vLLM Qwen 3.x (local)",
    baseUrl: BASE_URL,
    apiKey: "vllm", // dummy key; vLLM does not authenticate
    api: "openai-completions",
    models: loadModels().map(({ id, context }) => ({
      id,
      name: id,
      input: ["text", "image"] as ("text" | "image")[],
      reasoning: true,
      contextWindow: context,
      maxTokens: MAX_TOKENS,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    })),
  });
}
