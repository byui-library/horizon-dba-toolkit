# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository. It applies equally to any other assistant; the
tool-neutral schema rules live in
[`docs/schema/AGENTS.md`](docs/schema/AGENTS.md).

## What this repository is

A documentation-first toolkit for auditing and repairing data-integrity issues in
a **SirsiDynix Horizon** ILS database on SQL Server. There is **no build, test,
lint, or run tooling for the SQL** — it is not executed here; it is delivered as
documentation to be run by a DBA against a live ILS database. "Running tests"
means a human reviewing the SQL logic and running the audit query.

The PowerShell tooling in `tools/` *is* testable and has its own suite:

```powershell
powershell -ExecutionPolicy Bypass -File tools\Test-Tools.ps1
```

## Repository layout

```text
SETUP.md          first run at a new site
solutions/        one directory per solution — the deliverables
docs/schema/      schema rules, conventions, per-table pages, site profile
docs/killbib.md   Horizon's batch-delete utility: flags, limits, failure modes
horizon-schema/   raw CSV schema exports — the source of truth for names
tools/            PowerShell: profiler, doc generators, delete-run scripts, tests
```

## This toolkit is shipped to other sites

It is designed to be forked and used against a database that is not the one it
was written against. Two consequences bear on everything you write here.

### Separate universals from site facts

**Prose states only what is true of Horizon everywhere.** Anything that varies
between installations goes in a *generated* file, never in hand-written text:

| Fact | Where it belongs |
| --- | --- |
| `bib` fans out per MARC tag; `item` per copy | prose — universal |
| `bib.text` uses `CHAR(31)`/`CHAR(30)` | prose — universal |
| Indexes named `PK_*` are usually not primary keys | prose — universal |
| Object counts, declared PK list, collation, compatibility level | `docs/schema/site-profile.md` — **generated** |
| **The epoch the integer date columns count from** | `docs/schema/site-profile.md` — **generated** |
| Every table and column name | `horizon-schema/*.csv` — **exported** |

If you catch yourself about to write a number into prose, ask whether you
measured it here or somewhere else. If somewhere else, link to the profile
instead. A number in prose is an assertion about every site that reads it.

The two generators:

```powershell
powershell -ExecutionPolicy Bypass -File tools\Generate-SchemaDocs.ps1
powershell -ExecutionPolicy Bypass -File tools\Get-SiteProfile.ps1 -Server ILSSERVER -Database ILSDB
```

### Write to the lowest common denominator

The next site to receive a query may be running an older compatibility level
than yours. Use `CASE` not `IIF`, `+` not `CONCAT`, `TOP` not `OFFSET/FETCH`,
and no `STRING_AGG`. `docs/schema/site-profile.md` records what *your* engine
allows, but portability is the default.

## Never publish real site identifiers

Server names, database names, logins, Horizon user IDs, location codes and staff
usernames must never appear in a tracked file. Use these placeholders, which are
deliberately bracket-free so they can be pasted into PowerShell without breaking
(`<` is a reserved redirection operator):

| Real thing | Placeholder |
| --- | --- |
| SQL Server instance | `ILSSERVER` |
| Database | `ILSDB` |
| SQL login (`/u`) | `ils_svc` |
| Horizon User ID (`/r`) | `HZUSER` |
| Location code (`/l`) | `LOC` |
| Staff DB principal | `staff_readers` |
| Staff username | `CATALOGER`, `OTHERUSER` |

Angle-bracket placeholders (`<server>`) are fine in prose and tables, never in a
block someone will paste.

`tools\Test-Tools.ps1` enforces this: it reads `tools/.redaction-denylist.txt`
(gitignored, so the real values never enter the repo) and fails if any listed
value appears in a tracked file. Add a value to that denylist the moment you
learn it.

Bib numbers are kept — they are public catalogue identifiers and they make
findings reproducible. Patron data is never committed; `.gitignore` blocks
`*.csv`/`*.xlsx` for that reason, with a narrow exception only for
`horizon-schema/*.csv`, which is schema metadata containing no records.

If a schema export reveals a staff username in a *table name*, fix it by renaming
the table, not by editing the export. A doctored export silently disagrees with
the database, which is the exact class of error this repository guards against.

## Structure convention

Each solution is a self-contained directory **under `solutions/`** whose
`README.md` is the deliverable. The top-level `README.md` is an index — when
adding a solution, link it from that index.

**Scaffold a new one rather than copying by hand:**

```powershell
powershell -ExecutionPolicy Bypass -File tools\New-Solution.ps1 `
    -Name 245-missing-subfield-a -Type Report -Summary "One line for the index."
```

That creates `solutions/<name>/README.md` pre-filled with the required structure
and appends the index line. `-Type Fix` produces the Audit/Update variant.

### Each solution ships three files — one written, two generated

| File | Status |
| --- | --- |
| `README.md` | **written — source of truth** |
| `sql/NN-<slug>.sql` | generated: runnable files for SSMS |
| `runbook.html` | generated: copy-button page for local viewing |

**Never hand-edit the generated files.** Edit the README, then regenerate:

```powershell
powershell -ExecutionPolicy Bypass -File tools\Build-SolutionDocs.ps1
```

Run this after any change to a README's SQL, and commit the results alongside it.
Full conventions are in
[`docs/authoring-solution-docs.md`](docs/authoring-solution-docs.md). Note that
**GitHub does not render `.html` files**; the README must therefore carry the
complete story on its own.

Every solution README follows the same structure, in this order:

1. **The Problem** — including the schema reason it is hard (see Cartesian
   product below).
2. **Step 1: The Audit** — a `SELECT` that lists exactly the rows the update will
   change, showing current value beside proposed new value.
3. **Step 2: The Update** — an `UPDATE` whose `FROM`/`JOIN` clauses are identical
   to the audit query's, so the affected row set provably matches what was
   audited.

The audit `SELECT` and the update `UPDATE` must target the same rows via the same
joins/subqueries. Diverging them breaks the core safety guarantee of this repo.

**Read-only report exception:** a solution that only *reports* data (a `SELECT`
with no `UPDATE`) has no audit/update split. Such a README uses a single
**The Report (Read-Only)** section instead of the Audit/Update steps, and states
that no backup or transaction is required. See
`solutions/590-ebk-purchase-dda-report/`.

## Never guess a column or table name

**This is a deterministic program run against a live ILS. Column names are facts,
not conventions.** A guessed name either fails loudly or — worse — silently
returns the wrong rows.

> ### Read [`docs/schema/AGENTS.md`](docs/schema/AGENTS.md) before writing SQL
>
> It holds the full rules — lookup recipes, grain and join safety, the date
> convention, engine limits, and a pre-flight checklist. It is tool-neutral, so
> it applies whichever assistant or person is doing the work. Everything below is
> a summary of it.

- **Look up every name** in [`horizon-schema/`](horizon-schema/README.md) — this
  site's own export. Grep `all_tables_all_views.csv`, or read
  [`docs/schema/core/`](docs/schema/core/) for the documented tables. If `grep`
  finds nothing, the object does not exist here.
- Names correct at another Horizon site are a hypothesis about this one, not a
  fact. Local customisation and version drift both change what exists.
- If something is genuinely absent or ambiguous, **ask the user**, who can run
  `sp_help <table>` and paste the output. Then write it up in
  `docs/schema/core/<table>.md` so the next script does not re-derive it.
- Read the *types*, not just the names. They change what a correct predicate
  looks like — e.g. a `smallint` day-count column with a sibling `_time` column
  must be filtered with `=` on an integer, never a `datetime` range or a
  `CAST(... AS DATE)`.
- **Grain before joins.** Check both sides in
  [`docs/schema/index/all-objects.md`](docs/schema/index/all-objects.md). `bib`
  is one row per *tag*; `item` one row per *copy*. Neither collapses the other.

Traps already paid for:

- `bib_control`'s creating-operator column is **`create_user`**, not
  `creator`/`created_by`/`cataloger`.
- Indexes named `PK_*` are **not primary keys**. Grain comes from *unique
  indexes*. The declared list for this site is in
  [`docs/schema/site-profile.md`](docs/schema/site-profile.md).
- `ITEM_JUV`, `borrower_bak`, `tmp*`, `del*` and their local equivalents are
  scratch/backup tables, not Horizon's. They can look authoritative and hold
  stale data — and the reverse also happens, since Horizon ships some names that
  look local.

## Horizon schema knowledge required to write correct scripts

- `bib` and `item` are both children of `bib#` but have **no direct key linking a
  specific item row to a specific tag row**. Joining them is many-to-many and
  produces a Cartesian product (2 items × 2 tags = 4 rows). Scripts must collapse
  this with aggregation/`DISTINCT`/`EXISTS`, never a naive join.
- **You cannot aggregate an `EXISTS`** — Msg 130. Compute the flag in a derived
  table, then aggregate the flag. See `AGENTS.md` Rule 3.
- MARC subfield text stored in `bib.text` uses control characters, not literal
  pipes: `CHAR(31)` is the subfield delimiter, `CHAR(30)` is the field terminator.
  Write these as `CHAR(31)+'a'+value+CHAR(30)`; use a human-readable `'|a'+value`
  column only for display in audit output.
- To change one of several same-`tag` rows for a `bib#`, isolate it by `tagord`
  (e.g. `MAX(tagord)` to target the later duplicate while preserving the first).
  `HAVING COUNT(*) = N AND MIN(text) = MAX(text)` is the idiom for "N identical
  tags".
- **Dates are `smallint` day counts**, and the anchor is site-specific. Use the
  epoch verified in [`docs/schema/site-profile.md`](docs/schema/site-profile.md),
  and never a date literal or a `CAST(... AS DATE)`.

## Non-negotiable conventions for any UPDATE script

- Ship the audit `SELECT` first and state that it must be run and its row count
  recorded before the `UPDATE`.
- State explicitly that a `bib`/`item` table (or full DB) backup is required
  first.
- Where the engine allows, wrap the `UPDATE` in a transaction so the row count can
  be checked against the audit before commit.
