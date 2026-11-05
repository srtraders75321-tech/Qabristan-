import { test } from "node:test";
import assert from "node:assert/strict";
import { check } from "./guard.mjs";

const tracked = () => true;
const untracked = () => false;

const edit = (file_path) => ({ tool_name: "Edit", tool_input: { file_path } });
const bash = (command) => ({ tool_name: "Bash", tool_input: { command } });

test("blocks editing a committed migration", () => {
  assert.match(check(edit("supabase/migrations/0001_init.sql"), { isTracked: tracked }), /immutable/);
});

test("allows creating a new migration", () => {
  assert.equal(check(edit("supabase/migrations/0002_ledger.sql"), { isTracked: untracked }), null);
});

test("blocks secret and signing files", () => {
  for (const f of [".env", ".env.production", "app/android/upload.keystore", "app/android/key.properties", "certs/dist.p12"]) {
    assert.match(check(edit(f), { isTracked: untracked }), /secret/, f);
  }
});

test("allows .env.example", () => {
  assert.equal(check(edit(".env.example"), { isTracked: untracked }), null);
});

test("allows ordinary source edits", () => {
  assert.equal(check(edit("app/lib/main.dart"), { isTracked: tracked }), null);
  assert.equal(check(edit("docs/DECISIONS.md"), { isTracked: tracked }), null);
});

test("blocks destructive SQL in shell commands", () => {
  for (const c of [
    'psql -c "DROP TABLE ledger_entry"',
    'psql -c "truncate ledger_entry"',
    'psql -c "delete from family"',
  ]) {
    assert.match(check(bash(c)), /destructive SQL/, c);
  }
});

test("blocks hosted reset and force push", () => {
  assert.match(check(bash("supabase db reset --linked")), /hosted/);
  assert.match(check(bash("git push --force origin main")), /force/i);
  assert.match(check(bash("git push -f origin main")), /force/i);
});

test("allows local reset and normal commands", () => {
  assert.equal(check(bash("supabase db reset")), null);
  assert.equal(check(bash("git push -u origin claude/app-creation-du1gfk")), null);
  assert.equal(check(bash("flutter test")), null);
});
