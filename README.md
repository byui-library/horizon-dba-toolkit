# Horizon DBA Toolkit

Documentation, T-SQL and PowerShell for doing database work against a
**SirsiDynix Horizon** ILS on SQL Server without breaking anything.

Horizon's schema is old, irregular, and misleading in specific, repeatable ways.
Two tables that look joinable produce a Cartesian product. Indexes named `PK_*`
are not primary keys. Dates are integers counting from an anchor you have to
prove. A column called `creator` does not exist; the one you want is
`create_user`. None of that is written down anywhere official, and every site
rediscovers it separately.

This toolkit is what one library's rediscovery looked like, packaged so the next
site does not have to repeat it.

> **Not a SirsiDynix product.** Independent, community-contributed, MIT-licensed.
> See [NOTICE.md](./NOTICE.md).

---

## Start here

**New site? → [SETUP.md](./SETUP.md).** About 30 minutes, entirely read-only.

| If you want to… | Go to |
| --- | --- |
| Set this up against your database | **[SETUP.md](./SETUP.md)** |
| Write a query safely | **[docs/schema/AGENTS.md](./docs/schema/AGENTS.md)** |
| Look up a fact about *your* site | [docs/schema/site-profile.md](./docs/schema/site-profile.md) *(generated)* |
| Delete records in batch | [docs/killbib.md](./docs/killbib.md) + [tools/README.md](./tools/README.md) |
| Write a new solution | [docs/authoring-solution-docs.md](./docs/authoring-solution-docs.md) |

---

## The idea

**Ship the method, not one site's data.**

Every fact in this repository is one of two kinds, and they are kept rigorously
apart:

| | Where it lives | Who produces it |
| --- | --- | --- |
| **True of Horizon everywhere** | hand-written prose | written once, shipped to you |
| **True of *your* installation** | `docs/schema/site-profile.md`, `docs/schema/index/`, `horizon-schema/*.csv` | **generated from your database** during setup |

So the repository arrives with no schema in it. You run four export queries and
two scripts, and it fills itself in with facts about the database you actually
have. Where a generated page disagrees with the prose, the generated page wins —
it was measured; the prose was written.

That distinction is not pedantry. Consider the worst case it prevents:

> Horizon stores dates as `smallint` day counts from a fixed anchor. Get that
> anchor wrong by **one day** and every dated query at your site is wrong by one
> day. Nothing errors. Nothing looks odd. The numbers are simply not the ones you
> asked for.
>
> `tools/Get-SiteProfile.ps1` proves the anchor rather than assuming it, using
> the fact that cataloguing stops at weekends: only the correct anchor puts the
> quiet days on Saturday and Sunday. It scores every candidate from −3 to +3 days
> and tells you whether the winner is unambiguous. A `MAX(create_date)` sanity
> check — the obvious thing to do — cannot detect this error at all.

---

## Two rules that hold everything else up

### 1. Never guess a name

A guessed column name either fails loudly in front of a DBA or, much worse,
silently returns a different row set than intended. Every name in every script
here was looked up in a schema export, not recalled.

This one is not a style preference. The audit/update contract below is only
meaningful if the audit and the update touch the same rows, and a guessed name
breaks that guarantee invisibly.

### 2. Audit before you change

Every repair ships a `SELECT` that lists exactly the rows the `UPDATE` will
change — current value beside proposed new value — and the `UPDATE` reuses
**identical** `FROM`/`JOIN` clauses, so the affected set provably matches what
was reviewed. Run the audit, record the row count, take a backup, wrap the update
in a transaction, check the count, then commit.

A read-only report has no such split and says so.

---

## What is in here

```text
SETUP.md          first run at a new site — start here
docs/
  schema/         the Horizon schema: rules, conventions, per-table pages
    AGENTS.md       rules for writing correct SQL   ← the important one
    conventions.md  the schema-wide patterns, explained
    site-profile.md GENERATED — your database's own numbers
    core/           per-table pages
    index/          GENERATED — orientation over your export
  killbib.md      Horizon's batch-delete utility: flags, limits, failure modes
  authoring-solution-docs.md
horizon-schema/   YOUR CSV schema exports — the source of truth for names
solutions/        one directory per solution — the deliverables
tools/            PowerShell: profiler, doc generators, delete-run scripts, tests
```

### Tools

| Script | Purpose |
| --- | --- |
| `Get-SiteProfile.ps1` | measures what varies between sites, writes `site-profile.md` |
| `Generate-SchemaDocs.ps1` | CSV exports → `docs/schema/index/` |
| `New-Solution.ps1` | scaffolds a new solution in the required structure |
| `Build-SolutionDocs.ps1` | README → runnable `sql/*.sql` + `runbook.html` |
| `Invoke-DeleteListRun.ps1` | the whole batch-delete sequence, one command, ten steps |
| `Test-DeleteListPreflight.ps1` | four read-only checks before a delete |
| `Invoke-KillBib.ps1` | wraps the vendor binary |
| `Find-KillBib.ps1` | locates the executable; refuses to choose between installs |
| `HorizonSql.ps1` | shared SQL and validation helpers (dot-sourced) |
| `Test-Tools.ps1` | the test suite — no database needed |

Full documentation: [tools/README.md](./tools/README.md).

### Solutions

Two worked examples, one of each shape. They are real solutions that ran against
a live database, kept here because the shape is the point — copy the structure,
not the specifics.

* **[590-ebk-purchase-dda-report](./solutions/590-ebk-purchase-dda-report)** —
  a **read-only report**: the purchase and DDA `590` note tags on ebook bib
  records. Shows how to collapse the `bib`/`item` fan-out with `EXISTS`, and why
  a case-insensitive `%DDA%` produces false positives.
* **[049-duplicate-cleanup](./solutions/049-duplicate-cleanup)** —
  an **audit/update fix**: redundant `049` tags where several collections exist
  on the item side but are not represented in the bib record. Shows the identical-
  joins guarantee and the `tagord` idiom for targeting one of several same-`tag`
  rows.
* **[db-scratch-table-cleanup](./solutions/db-scratch-table-cleanup)** —
  identifies local scratch and backup tables Horizon did not ship, checks nothing
  depends on them, and generates a reviewed `DROP` list. Useful at any site; it
  is also what keeps a schema export honest.

Add your own with the scaffold rather than by hand:

```powershell
powershell -ExecutionPolicy Bypass -File tools\New-Solution.ps1 `
    -Name 245-missing-subfield-a -Type Report `
    -Summary "Bibs whose 245 has no subfield a."
```

`-Type Fix` produces the audit/update variant instead.

#### Generated alongside each README

Never edit these directly — edit the `README.md` and re-run
`tools/Build-SolutionDocs.ps1`:

* `sql/NN-<slug>.sql` — each query as a runnable file. Open in SSMS and press F5.
* `runbook.html` — a copy-ready page with a copy button per query. Open it in a
  browser; GitHub shows `.html` as source rather than rendering it. See
  [docs/authoring-solution-docs.md](./docs/authoring-solution-docs.md).

---

## Batch deletion

Horizon ships `killbib`, a command-line utility that permanently deletes bib
records from a table of `bib#` you supply. [docs/killbib.md](./docs/killbib.md)
documents what it actually does, including five behaviours absent from its own
`/?` output — most importantly that **there is no dry-run mode**.

`tools/Invoke-DeleteListRun.ps1` wraps the whole sequence: build the list,
pre-flight it, count-gate it, write a timestamped audit CSV, require a typed
confirmation, run the delete, verify. The wrapper is the point — running
`killbib` by hand is strictly worse, which is why the tooling ships here rather
than being left out as too dangerous.

Read [docs/killbib.md](./docs/killbib.md) before your first run. All of it.

---

## Prerequisites

- **T-SQL (SQL Server).** Everything here is written to a low common denominator
  — no `STRING_AGG`, `CONCAT`, `IIF` or `FORMAT` — because Horizon databases
  often sit at a compatibility level that rejects them. Yours is probed during
  setup.
- **Permissions:** `VIEW DEFINITION` for setup and reports; update permission for
  repairs; considerably more for the delete tooling.
- **Windows PowerShell 5.1** for the tooling. Ships with Windows; nothing to
  install.

There is no build step. The SQL is not executed from this repository — it is
documentation for a DBA to run.

---

## Licence and attribution

MIT — see [LICENSE](./LICENSE). You may copy, modify, redistribute and bundle
this freely, including commercially; no permission needs to be sought.

**Not a SirsiDynix product.** Not produced, endorsed or supported by SirsiDynix.
*Horizon* and *SirsiDynix* are their trademarks, used here only to identify the
software this is written for. Details, and the warranty disclaimer that matters
for the destructive scripts, in [NOTICE.md](./NOTICE.md).
