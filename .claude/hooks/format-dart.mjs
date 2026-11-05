// PostToolUse: format an edited .dart file with `dart format`.
// Silent no-op when Dart is not installed or the file is not Dart.

import { spawnSync } from "node:child_process";

let raw = "";
for await (const chunk of process.stdin) raw += chunk;

try {
  const input = JSON.parse(raw);
  const file = String(input?.tool_input?.file_path ?? "");
  if (file.endsWith(".dart")) {
    spawnSync("dart", ["format", file], { stdio: "ignore", shell: process.platform === "win32" });
  }
} catch {
  // Never fail the edit because formatting failed.
}
process.exit(0);
