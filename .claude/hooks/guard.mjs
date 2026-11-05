// PreToolUse guard for the Kabristan project.
// Blocks (exit code 2) edits and commands that would break the project's data-safety rules.
// Hook input arrives as JSON on stdin: { tool_name, tool_input: { file_path?, command? }, ... }

import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const MIGRATION_RE = /(^|[\\/])supabase[\\/]migrations[\\/][^\\/]+\.sql$/i;
const SECRET_FILE_RE =
  /(^|[\\/])(\.env(\.(?!example$)[^\\/]+)?|[^\\/]+\.(keystore|jks|p12|pem|mobileprovision)|key\.properties)$/i;
const DESTRUCTIVE_SQL_RE = /\b(drop\s+(table|schema|database)|truncate(\s+table)?|delete\s+from)\b/i;
const RESET_LINKED_RE = /\bsupabase\s+db\s+reset\b[^\n]*--linked/i;
const FORCE_PUSH_RE = /\bgit\s+push\b[^\n]*(\s--force\b|\s--force-with-lease\b|\s-f\b)/i;

export function isTrackedInGit(filePath, cwd = process.cwd()) {
  try {
    execFileSync("git", ["ls-files", "--error-unmatch", "--", filePath], {
      cwd,
      stdio: "ignore",
    });
    return true;
  } catch {
    return false;
  }
}

// Returns null when allowed, or a string reason when the call must be blocked.
export function check(input, { isTracked = isTrackedInGit } = {}) {
  const tool = input?.tool_name ?? "";
  const args = input?.tool_input ?? {};

  if (["Edit", "Write", "MultiEdit", "NotebookEdit"].includes(tool)) {
    const path = String(args.file_path ?? args.notebook_path ?? "");
    if (SECRET_FILE_RE.test(path)) {
      return `Blocked: "${path}" is a secret or signing file. Secrets never go in the repo (CLAUDE.md rule 8). Use an ignored .env file or the CI secret store.`;
    }
    if (MIGRATION_RE.test(path) && isTracked(path)) {
      return `Blocked: "${path}" is an already-committed migration. Applied migrations are immutable (CLAUDE.md rule 9). Add a new migration instead.`;
    }
    return null;
  }

  if (tool === "Bash") {
    const cmd = String(args.command ?? "");
    if (DESTRUCTIVE_SQL_RE.test(cmd)) {
      return "Blocked: destructive SQL (DROP / TRUNCATE / DELETE FROM) in a shell command. Data changes go through reviewed migrations or audited functions, and nothing is deleted (CLAUDE.md rules 2-3).";
    }
    if (RESET_LINKED_RE.test(cmd)) {
      return "Blocked: `supabase db reset --linked` would wipe a hosted database. Reset only the local stack.";
    }
    if (FORCE_PUSH_RE.test(cmd)) {
      return "Blocked: force-pushing can destroy history. Ask the owner first.";
    }
  }

  return null;
}

async function main() {
  let raw = "";
  for await (const chunk of process.stdin) raw += chunk;
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    process.exit(0); // Unreadable input: do not block.
  }
  const reason = check(input);
  if (reason) {
    process.stderr.write(reason + "\n");
    process.exit(2);
  }
  process.exit(0);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
