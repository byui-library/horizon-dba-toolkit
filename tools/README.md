# Tools

PowerShell scripts for this repository. Three groups: **setup** (run these
first), **documentation generators** (safe, run them freely) and **delete-run
tooling** (one of them is irreversible).

All are Windows PowerShell 5.1 compatible and use `System.Data.SqlClient`
directly, so no `SqlServer` module is needed. Nothing has to be installed.

| Script | Group | Touches the catalog? |
| --- | --- | --- |
| [`Invoke-ReadOnlyQuery.ps1`](#invoke-readonlyqueryps1) | query | no (read-only, enforced) |
| [`Get-SiteProfile.ps1`](#get-siteprofileps1) | setup | no (read-only) |
| [`Generate-SchemaDocs.ps1`](#generate-schemadocsps1) | setup | no |
| [`Test-Tools.ps1`](#test-toolsps1) | — | no (no database at all) |
| [`Build-SolutionDocs.ps1`](#build-solutiondocsps1) | docs | no |
| [`New-Solution.ps1`](#new-solutionps1) | docs | no |
| [`Find-KillBib.ps1`](#find-killbibps1) | delete | no |
| [`Test-DeleteListPreflight.ps1`](#test-deletelistpreflightps1) | delete | no (read-only) |
| [`Invoke-KillBib.ps1`](#invoke-killbibps1) | delete | **YES — irreversible** |
| [`Invoke-DeleteListRun.ps1`](#invoke-deletelistrunps1) | delete | **YES — irreversible** |

> **New site?** Work through [SETUP.md](../SETUP.md) first. Until
> `Get-SiteProfile.ps1` has run, nothing in this repository knows what date your
> integer date columns count from — and every dated query depends on it.

> **Run scripts by absolute path**, or from the repository root. A relative
> `tools\...` path fails if your prompt is somewhere else, and one of these
> scripts deliberately changes directory while it runs.

---

# The batch delete — one command

`Invoke-DeleteListRun.ps1` runs the entire sequence for a "delete every record
created by `<user>` on `<date>` whose `<tag>` mentions `<term>`" job: verify,
build the list, grant, pre-flight, delete, verify again. One typed confirmation
before the irreversible step.

```powershell
& "C:\path\to\repo\tools\Invoke-DeleteListRun.ps1" -Table PQ_CAT_20260825_DeleteList -CreateUser CATALOGER -CreateDate 2026-08-25 -ExpectedRows 6790 -NoteTag 590 -NoteTerm ProQuest -StaffPrincipal staff_readers -Brutal
```

It prompts for what it doesn't have:

```text
Server:        ILSSERVER
Database:      ILSDB
HorizonUserId: HZUSER      <- KillBib /r, your Horizon client login
Location:      LOC         <- KillBib /l, validated against the location table
```

…then a standard credential dialog for the **SQL** login (`/u` and `/p`).

> **`-NoteTag` and `-NoteTerm` default to `590` / `ProQuest`** — the job this was
> first written for. Pass them explicitly for anything else. They are not
> validated against your data beyond the count gate in step 2, so a term that
> matches nothing produces a count of 0 and an abort rather than a silent
> no-op — but a term that matches *too much* is caught only by that count. Review
> the audit query in a solution README before trusting a new filter.

## What the ten steps do

| Step | Action | Catalog touched |
| ---: | --- | --- |
| 1 | Connect; validate the `/l` location code against the `location` table | no |
| 2 | Count the selection — must equal `-ExpectedRows` or it aborts | no |
| 3 | Discriminator check: has the note filter ever excluded anything? | no |
| 4 | Create the delete-list table, `PRIMARY KEY CLUSTERED ([bib#])` | no |
| 5 | Populate it, count-checked | no |
| 6 | `GRANT SELECT` to the staff principal | no |
| 7 | Pre-flight: orphaned codes, row count, audit file | no |
| 8 | **Typed confirmation** — enter the row count | — |
| 9 | KillBib | **yes, irreversible** |
| 10 | Post-verify: listed bibs gone, item rows gone | no |

Steps 1–7 change nothing in the catalog. A failure in any of them aborts before
step 9. Steps 4–6 create and populate a scratch table only — if something is
wrong, drop it and start over.

**Step 3 deserves a word.** It asks whether your note filter has *ever* excluded
a record from the same operator and period. If it never has, the filter is doing
no work and you are really deleting "everything that operator created", which may
or may not be what you meant. At the reference site the filter looked redundant
on the target day — it excluded nothing — but was load-bearing across the wider
window, because the cataloguer batch-loaded most days and also hand-created the
occasional record without recording it. Run the check; do not assume.

## Start with `-WhatIfOnly`

```powershell
& "...\tools\Invoke-DeleteListRun.ps1" -Table PQ_CAT_20260825_DeleteList -CreateUser CATALOGER -CreateDate 2026-08-25 -ExpectedRows 6790 -Brutal -WhatIfOnly
```

Runs steps 1–3 and stops, creating nothing. Since [KillBib has no dry-run of its
own](../docs/killbib.md#2-there-is-no-dry-run), this is the closest equivalent
available, and it answers the discriminator question before anything exists.

## Parameters

| Parameter | Maps to | Notes |
| --- | --- | --- |
| `-Server` `-Database` | `/s` `/d` | prompted if omitted |
| `-HorizonUserId` | `/r` | **mandatory** — Horizon login, *not* the SQL login |
| `-Location` | `/l` | **mandatory** — validated against `location` in step 1 |
| `-Table` | `/t` | **max 30 chars** — KillBib truncates at 31 |
| `-CreateUser` `-CreateDate` | — | the selection: who created records, and when |
| `-ExpectedRows` | — | the reviewed count; a mismatch aborts the run |
| `-Brutal` | `/k` | also deletes items, copies, circ data |
| `-StaffPrincipal` | — | `GRANT SELECT` target; omit to skip step 6 |
| `-NoteTag` `-NoteTerm` | — | default `590` / `ProQuest` — **set these** |
| `-Epoch` | — | default `1970-01-01`; **check yours** in [`site-profile.md`](../docs/schema/site-profile.md#epoch) |
| `-DiscriminatorFrom` | — | default 6 months before `-CreateDate` |
| `-DiscriminatorTimeout` | — | default 90s |
| `-SkipDiscriminator` | — | skips step 3, flags the warning |
| `-Trial` | `/b`+`/e` | opt in to a single-bib trial delete first |
| `-Yes` | — | skip the typed confirmation |
| `-WhatIfOnly` | — | steps 1–3 only |
| `-ResumeFrom` | `/b` | restart a stopped run at this `bib#` |
| `-KillBibPath` | — | use a specific executable |

> **`-Epoch` is the one to check before your first run.** It defaults to
> `1970-01-01`, which is what the reference site measured. If your site differs,
> `-CreateDate` selects the wrong day's records — and the count gate will not
> save you, because a different day still returns *a* number.
> `Get-SiteProfile.ps1` settles it.

## Safety properties

- **The selection predicate is defined once** and reused for the count, the
  discriminator and the `INSERT`, so those three cannot drift apart — the same
  guarantee this repo's READMEs make by using an identical `WHERE` clause in the
  audit and the update.
- **Step 2 aborts on a count mismatch** rather than adapting. A mismatch means
  the data drifted since your review; re-review rather than changing
  `-ExpectedRows` to whatever it now returns.
- **Every parameter reaching SQL is validated** as a plain identifier or checked
  for quotes before any query is built.
- **The audit file is written before anything is deleted** —
  `killbib-audit\<table>-<timestamp>.csv` holds the exact `bib#` list. It is
  catalog data, so `.gitignore` keeps it out of the repository. Dropping the
  delete-list table afterwards therefore loses no audit trail.
- **No explicit transaction wraps the load.** An interrupted run would otherwise
  leave a transaction open, holding a lock on the list table and blocking the
  next attempt. This is a disposable scratch table: a wrong count is fixed by
  dropping and rebuilding, not by rollback.

## If it stops partway

Non-zero exit runs the orphaned-code diagnostic and prints the exact resume
command. **It never resumes automatically** — a partial delete that stopped for
an unexplained reason is a decision for a human holding the diagnostic. See
[`docs/killbib.md`](../docs/killbib.md#fk_stat_data_-failures).

---

# Script reference

## `Invoke-ReadOnlyQuery.ps1`

Runs one read-only batch against the database named in the gitignored
`tools\site.local.psd1` (copy [`site.local.example.psd1`](site.local.example.psd1)),
using Windows authentication. It prints the result and can save the first result
set as a fully quoted UTF-8 CSV. This is the only route an AI assistant uses
into the live catalog; see the root [`AGENTS.md`](../AGENTS.md).

```powershell
powershell -ExecutionPolicy Bypass -File tools\Invoke-ReadOnlyQuery.ps1 -Sql "SELECT COUNT(*) AS n FROM bib_control"
powershell -ExecutionPolicy Bypass -File tools\Invoke-ReadOnlyQuery.ps1 -File solutions\<name>\sql\01-....sql -OutCsv "excel reports\<name>.csv"
```

Read-only in four layers. The first is enforced by SQL Server itself; the
others give friendlier errors and a second line of defence:

1. **Runs as the database user `ro_query`.** Right after connecting with the
   caller's Windows login, the tool runs
   `EXECUTE AS USER = 'ro_query' WITH NO REVERT`. From then on, SQL Server
   checks every statement against `ro_query`, which holds only `db_datareader`,
   so any write fails with *permission denied*, even when the caller's own
   login is `sysadmin`. `NO REVERT` stops the batch from switching back, and
   the connection is never pooled. **If the switch fails, nothing runs.**
2. **Refused before sending** if the batch contains a write (`INSERT`,
   `UPDATE`, `DELETE`, `MERGE`, DDL, `GRANT`, `EXEC`, `SELECT ... INTO`, ...),
   anything that could end the transaction (`COMMIT`, `ROLLBACK`), a lock hint
   or `WAITFOR` that would hold locks until the rollback, an external data
   source, a `GO`, or does not start with `SELECT`, `WITH`, `DECLARE` or `SET`.
   Strings, comments and `[identifiers]` are blanked in one lexer pass
   (`ConvertTo-BareSql` in `HorizonSql.ps1`, also used for the runbook chips),
   and the check fails closed.
3. **Always rolled back:** the batch runs inside a transaction that is rolled
   back whatever happens.
4. **Effective permissions, checked every run.** After the switch the tool
   asks the database what the current identity could change, and prints
   `Access: read-only: ... <login> as ro_query`. Unless that check confirms
   `ro_query` with no write permission of any kind, the tool **stops** with
   exit 5 before running the batch. `-CheckAccess` prints the detail and stops.

The tool takes no login or password parameter and connects with Windows
authentication only, so a SQL login, such as the one KillBib uses, can never
reach it. `Test-Tools.ps1` covers the refusal check, the access verdict and
those constraints.

**Exit codes**, so an assistant can tell what happened without parsing text:

| Code | Meaning | Anything run? |
| ---: | --- | --- |
| 0 | Success (for `-CheckAccess`: confirmed read-only) | yes, rolled back |
| 1 | `-CheckAccess` did not confirm a read-only identity | no |
| 2 | `REFUSED`: write-shaped SQL or an unedited placeholder | no |
| 3 | Ran, but the rollback did not happen. Tell the maintainer. | yes |
| 4 | `SQL ERROR`: SQL Server rejected the query. Any partial CSV is deleted. | rolled back |
| 5 | `STOPPED`: could not switch to `ro_query`, or the access check did not confirm read-only | no |
| 6 | Could not connect to the server | no |

**The one thing this does not cover:** a connection that does not go through
this tool runs with the caller's own login. That is why `AGENTS.md` forbids
every other route to the database.

`ro_query`, like any database user, can still *read* the parts of `msdb` and
`tempdb` that SQL Server opens to every user (backup history, for example).
That is standard behaviour and read-only.

### One-time setup: the `ro_query` user

A maintainer with `sysadmin` (or `db_owner` plus `ALTER ANY USER`) runs this
once per database, in SSMS. It creates a database user with **no login and no
password**: nobody can sign in as it, and it exists only so the tool can switch
to it. Replace `ILSDB`, and `staff_readers` with the Windows group (or user)
your staff connect through. Logins that are already `sysadmin` need no grant.

```sql
-- 1. Check it is not there already (expect no rows).
USE ILSDB;
SELECT name, type_desc FROM sys.database_principals WHERE name = 'ro_query';

-- 2. Create it: read-only, no login.
CREATE USER ro_query WITHOUT LOGIN;
ALTER ROLE db_datareader ADD MEMBER ro_query;
GRANT IMPERSONATE ON USER::ro_query TO [staff_readers];
```

Prove it before relying on it. The `UPDATE` matches no rows, but SQL Server
checks permission first, so it must fail with *"The UPDATE permission was
denied on the object 'bib'"*:

```sql
USE ILSDB;
EXECUTE AS USER = 'ro_query';
SELECT USER_NAME() AS acting_as,                                   -- ro_query
       HAS_PERMS_BY_NAME('dbo.bib', 'OBJECT', 'UPDATE') AS can_update; -- 0
UPDATE bib SET tag = tag WHERE 1 = 0;                              -- must fail: permission denied
REVERT;
SELECT USER_NAME() AS back_to;                                     -- you again
```

To undo it: `DROP USER ro_query;`. The tool then stops with a message until
the user is recreated; it never falls back to the caller's own login.

## `Get-SiteProfile.ps1`

Measures the facts that vary between Horizon sites and writes
[`docs/schema/site-profile.md`](../docs/schema/site-profile.md). Read-only; every
query reads a `sys` catalog view or `COUNT`s `bib_control`.

```powershell
powershell -ExecutionPolicy Bypass -File tools\Get-SiteProfile.ps1 `
    -Server ILSSERVER -Database ILSDB
```

It records: SQL Server version, **compatibility level**, **collation**, recovery
model, object counts, the **declared** primary keys (versus the many indexes
merely *named* like one), integer date-column counts, the user-defined-type
catalogue, object-creation clusters, and **which T-SQL functions actually work**
— probed by running each one, not inferred from a version number.

The headline output is the **epoch verdict**. It scores every candidate anchor
from −3 to +3 days against a daily histogram of `bib_control` and reports which
one puts cataloguing on weekdays rather than weekends. A one-day error there
shifts every dated query at your site, and a `MAX(create_date)` check cannot
detect it. The console says `VERIFIED` or it does not; if it does not, settle it
by hand before writing anything dated.

**No server, database, login or location name is written to the page**, so it is
safe to commit even in a public fork. Re-run it after an upgrade, a
compatibility-level change, or a restore.

## `Invoke-DeleteListRun.ps1`

The orchestrator described above. Prefer it over calling the pieces separately.

## `Invoke-KillBib.ps1`

Wraps KillBib alone, against a delete-list table that already exists. Discovers
the executable, runs pre-flight, optionally performs a single-bib trial, then the
full run. Used by the orchestrator; call it directly to resume a stopped run:

```powershell
& "...\tools\Invoke-KillBib.ps1" -Table PQ_CAT_20260825_DeleteList -ExpectedRows 6790 -ResumeFrom 5384912 -SkipTrial -Force -Brutal
```

Two behaviours worth knowing:

- **It runs KillBib from the executable's own directory**, because KillBib dies
  silently otherwise (exit code `2147483647`, no message).
- **It does not capture KillBib's output.** Capturing it — via `$x = ...` or a
  pipe into `Tee-Object` — swallows every line the tool prints and starves any
  prompt it writes. Output goes straight to your console, unbuffered, with stdin
  attached. Do not "improve" this by adding logging.

## `Test-DeleteListPreflight.ps1`

Four read-only checks against a delete-list table. Returns `$true`/`$false`.

1. Connectivity using the same SQL login KillBib will use
2. Table exists and holds exactly the expected row count
3. **Orphaned `location`/`collection`/`itype` codes** — the documented KillBib
   killer
4. Writes the `bib#` audit file

```powershell
& "...\tools\Test-DeleteListPreflight.ps1" -Server ILSSERVER -Database ILSDB -Table PQ_CAT_20260825_DeleteList -ExpectedRows 6790
```

## `Find-KillBib.ps1`

Resolves `KillBib.exe` from known SirsiDynix/Horizon install roots. Returns the
full path.

**If it finds more than one copy it refuses to choose.** Sites commonly have
several Horizon client installs side by side of differing versions —
`Horizon\` and `Horizon_2\` next to each other is a normal sight — and running a
delete utility from the wrong build against a live database is not a guess worth
automating. Pass `-Path` to name one, or `-All` to list every copy.

## `Build-SolutionDocs.ps1`

Generates `sql/NN-<slug>.sql` files and `runbook.html` from each solution's
`README.md`. The README is the source of truth; both outputs are derived and
carry a header saying so.

```powershell
powershell -ExecutionPolicy Bypass -File tools\Build-SolutionDocs.ps1
powershell -ExecutionPolicy Bypass -File tools\Build-SolutionDocs.ps1 -Solution db-scratch-table-cleanup
```

Scans `solutions/`. Queries that write are marked as such in the generated page,
by a classifier that **fails closed** — anything it cannot prove read-only is
labelled a write. Full conventions in
[`docs/authoring-solution-docs.md`](../docs/authoring-solution-docs.md).

## `Generate-SchemaDocs.ps1`

Rebuilds the generated pages under `docs/schema/index/` from the CSV exports in
`horizon-schema/`. Run after refreshing those exports.

```powershell
powershell -ExecutionPolicy Bypass -File tools\Generate-SchemaDocs.ps1
```

Hand-written pages (`AGENTS.md`, `conventions.md`, `core/*.md`) are never
touched, and neither is `site-profile.md` — that one belongs to
`Get-SiteProfile.ps1`.

## `New-Solution.ps1`

Scaffolds a new solution directory with a README skeleton in the required
structure, and adds its line to the top-level README index.

```powershell
powershell -ExecutionPolicy Bypass -File tools\New-Solution.ps1 -Name 245-missing-subfield-a -Type Report -Summary "Bibs whose 245 has no subfield a."
```

`-Type Report` produces the read-only single-section variant; `-Type Fix`
produces the Audit/Update pair. See
[`docs/authoring-solution-docs.md`](../docs/authoring-solution-docs.md).

## `Test-Tools.ps1`

The test suite. **No database connection**, so it is safe to run anywhere and
fast enough to run before every commit.

```powershell
powershell -ExecutionPolicy Bypass -File tools\Test-Tools.ps1
```

It covers the validation and parsing logic in the scripts above, plus two
PowerShell traps that caused real failures and would silently return:
`return $dt` unrolling a `DataTable` into `DataRow`s, and `SET LOCK_TIMEOUT`
leaking beyond the batch that set it.

It also runs the **redaction guard**: it reads `tools/.redaction-denylist.txt`
(gitignored, so your real values never enter the repository) and fails if any
listed value appears in a tracked file. Treat a failure there as blocking if your
fork is public. See [SETUP.md](../SETUP.md#step-6--protect-your-sites-identifiers).

---

## Before writing any query

Read [`docs/schema/AGENTS.md`](../docs/schema/AGENTS.md). Never infer a table or
column name — export your own schema into
[`horizon-schema/`](../horizon-schema/README.md) and look it up there.
