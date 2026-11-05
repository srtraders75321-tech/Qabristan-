#!/usr/bin/env python3
"""Mutation harness for the reconciliation checks.

Breaks each check on a scratch COPY of supabase/ (the repository is never modified) and confirms
the database test suite notices. A mutation is 'killed' when the suite reports at least one FAIL
or aborts. A 'survived' mutation means a check is not really being tested.

Usage:  python3 tools/mutation/reconciliation_mutations.py [name-filter ...]
Needs a reachable PostgreSQL 16 server (same as supabase/tests/run_local.sh). Takes several minutes.
"""
import os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

REPO = str(Path(__file__).resolve().parents[2])
SCRATCH = tempfile.mkdtemp(prefix="kabristan_mutation_")
M4 = "supabase/migrations/20261105000004_reconciliation.sql"
M5 = "supabase/migrations/20261105000005_function_privileges.sql"

SIG = "returns table (check_id text, severity text, record_type text, record_id text, detail text)"

def silence(fn):
    """Append an override that makes check function `fn` always return nothing."""
    def f(files):
        files[M4] += f"\ncreate or replace function public.{fn}() {SIG} language sql stable as $$ select null::text, null::text, null::text, null::text, null::text where false $$;\n"
    return f

def sub(old, new, path=M4, count=1):
    def f(files):
        assert old in files[path], f"mutation anchor not found: {old[:70]!r}"
        files[path] = files[path].replace(old, new, count)
    return f

def drop_file(path):
    def f(files):
        files[path] = "-- migration omitted by mutation\nselect 1;\n"
    return f

MUTATIONS = []
for n, fn in [("C1", "_recon_c1"), ("C2", "_recon_c2"), ("C3", "_recon_c3"), ("C4", "_recon_c4"),
              ("C5", "_recon_c5"), ("C6", "_recon_c6"), ("C7", "_recon_c7"), ("C8", "_recon_c8"),
              ("C9", "_recon_c9"), ("C10", "_recon_c10"), ("C11", "_recon_c11"), ("C11A", "_recon_c11a"),
              ("C13", "_recon_c13"), ("C14", "_recon_c14"), ("C16", "_recon_c16"), ("C17", "_recon_c17")]:
    MUTATIONS.append((f"{n} silenced (returns nothing)", silence(fn)))

MUTATIONS += [
    ("C1 ignores the reversal amount", sub("when r.amount_paisa <> -o.amount_paisa", "when false")),
    ("C2 allows more than one receipt", sub("where p.n <> 1", "where p.n < 1")),
    ("C3 stops detecting numbering gaps", sub("where y.n <> y.mx", "where false")),
    ("C4 ignores verification after reversal", sub("r.created_at <= v.verified_at", "false")),
    ("C7 misses overlap at the edge month", sub("and a.period_start <= b.period_end\n               and b.period_start <= a.period_end",
                                                "and a.period_start < b.period_end\n               and b.period_start < a.period_end")),
    ("C9 stops checking the burial kind", sub("when b.kind <> 'non_member' then 'linked burial is not a non-member burial'", "when false then 'x'")),
    ("C11 stops comparing against the audit record", sub("where not (i.new_data @> s.k)", "where false")),
    ("C13 ignores disabled triggers", sub("where a.trg is null or a.tgenabled <> 'O'", "where a.trg is null")),
    ("C14 ignores INSERT grants to clients", sub("'INSERT,UPDATE,DELETE,TRUNCATE'", "'TRUNCATE'")),
    ("C17 ignores the anon role", sub("has_function_privilege('anon', f.oid, 'EXECUTE')", "false")),
    ("A check is declared VOLATILE (read-only guarantee)", sub("create function public._recon_c7()\nreturns table (check_id text, severity text, record_type text, record_id text, detail text)\nlanguage sql stable",
                                                               "create function public._recon_c7()\nreturns table (check_id text, severity text, record_type text, record_id text, detail text)\nlanguage sql volatile")),
    ("A check tries to write data", sub("create function public._recon_c10()\nreturns table (check_id text, severity text, record_type text, record_id text, detail text)\nlanguage sql stable security definer set search_path = public, pg_temp\nas $$\n",
                                         "create function public._recon_c10()\nreturns table (check_id text, severity text, record_type text, record_id text, detail text)\nlanguage sql stable security definer set search_path = public, pg_temp\nas $$\n  with w as (insert into public.audit_log (action, table_name) values ('X','mutation') returning 1)\n")),
    ("ORIGINAL DEFECT: migration 5 (function privileges) omitted", drop_file(M5)),
]

def run(name, mutate):
    work = os.path.join(SCRATCH, "w")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    shutil.copytree(os.path.join(REPO, "supabase"), os.path.join(work, "supabase"))
    files = {}
    for p in (M4, M5):
        files[p] = open(os.path.join(work, p)).read()
    mutate(files)
    for p, c in files.items():
        open(os.path.join(work, p), "w").write(c)
    r = subprocess.run(["bash", os.path.join(work, "supabase/tests/run_local.sh")],
                       capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    fails = [l for l in out.splitlines() if l.startswith("FAIL")]
    summary = [l for l in out.splitlines() if re.search(r"\d+/\d+ passed", l)]
    errored = [l for l in out.splitlines() if "ERROR" in l and "NOTICE" not in l]
    killed = bool(fails) or r.returncode != 0
    return killed, fails, summary, errored

def main():
    only = sys.argv[1:]  # optional substring filters
    results = []
    os.makedirs(SCRATCH, exist_ok=True)
    for name, m in MUTATIONS:
        if only and not any(o.lower() in name.lower() for o in only):
            continue
        killed, fails, summary, errored = run(name, m)
        status = "KILLED " if killed else "SURVIVED"
        s = summary[-1].strip() if summary else (errored[0][:90] if errored else "run aborted")
        print(f"{status}  {name}  [{s}]", flush=True)
        for l in fails[:2]:
            print("          ", l[:150], flush=True)
        results.append((name, killed))
    shutil.rmtree(SCRATCH, ignore_errors=True)
    k = sum(1 for _, x in results if x)
    print(f"\nMUTATIONS: {len(results)} run, {k} killed, {len(results) - k} survived", flush=True)
    sys.exit(0 if k == len(results) else 1)

main()
