# Writing SQL against a Horizon database — agent instructions

Tool-neutral instructions for any AI assistant (Claude Code, Copilot, Cursor,
Codex, Gemini) or any person writing a query in this repository. `CLAUDE.md` at
the repo root points here; this file is the single source of truth for schema
rules.

SirsiDynix Horizon on SQL Server has a schema that is old, irregular, and
actively misleading in places. Every rule below exists because it has already
cost somebody a wrong answer.

> ## Two kinds of fact, and how to tell them apart
>
> **This page states only what is true of Horizon everywhere.** Anything that
> varies between sites — object counts, how many primary keys were actually
> declared, which T-SQL functions your compatibility level allows, your
> collation, and **the epoch the integer date columns count from** — lives in
> [`site-profile.md`](site-profile.md), measured against *your* database by
> `tools/Get-SiteProfile.ps1`.
>
> If that page disagrees with anything here, **it wins.** It was measured; this
> was written.
>
> If it does not exist yet, work through [SETUP.md](../../SETUP.md) first.

---

## Rule 1 — Never guess a name

**Look up every table and column before you use it.** Do not infer a name from
Horizon convention, from another site's schema, from a similar column elsewhere
in the same database, or from what the name "should" be.

This was learned the expensive way: a report was written against
`bib_control.creator`. The real column is **`create_user`**. The query was
plausible, readable, and wrong.

These scripts run against a live production ILS and are handed to a DBA to
execute. A wrong name either errors in front of that DBA or — much worse —
silently returns a different row set than intended. This repo's entire safety
model rests on the audit `SELECT` provably matching the `UPDATE`; a guessed name
breaks that guarantee invisibly.

Horizon sites also differ from one another. Local customisation, add-on modules
and version drift all change what exists. A name that is correct in one site's
documentation is a hypothesis about yours, not a fact.

If a lookup does not answer the question, **ask the user**. They can run
`sp_help <table>` and paste the result. Asking costs one message. Guessing costs
credibility and possibly data.

## Rule 2 — Look it up like this

The authoritative source is the CSV exports in [`horizon-schema/`](../../horizon-schema/),
produced from *your* database by the queries in [README.md](README.md). They have
**no header row**; field order is fixed and documented there.

`all_tables_all_views.csv` fields, in order:

```
1 schema   2 object   3 object_type   4 ord      5 column    6 declared_type
7 base_type   8 len_bytes   9 prec    10 scale   11 nullable 12 is_identity
13 is_computed   14 collation   15 pk   16 pk_ord   17 default_definition
```

**Every column of one table** — the most common lookup:

```bash
grep -E '^dbo,bib_control,' "horizon-schema/all_tables_all_views.csv"
```

```powershell
Import-Csv "horizon-schema\all_tables_all_views.csv" -Header schema,object,object_type,ord,column,declared_type,base_type,len_bytes,prec,scale,nullable,is_identity,is_computed,collation,pk,pk_ord,default_definition |
  Where-Object { $_.object -eq 'bib_control' } |
  Format-Table ord, column, declared_type, base_type, nullable, collation
```

**Which tables contain a given column** — for finding join partners:

```bash
awk -F, '$5=="ibarcode" {print $2}' "horizon-schema/all_tables_all_views.csv"
```

**Does this table/column exist at all?** If `grep` returns nothing, the answer is
no. Do not proceed on the assumption that the export is incomplete — it covers
every table and view in the database it was taken from.

Markdown pages under [`index/`](index/) are for **orientation** (what exists,
what its grain is). The CSVs are for **lookup** (exact names and types). Use the
right one for the question; do not read a 14,000-row CSV to get oriented, and do
not trust a summary page for an exact column name.

## Rule 3 — Establish grain before writing a join

**Grain** = the column set that is provably one row. It is the single most
important fact about a table here, because getting it wrong silently multiplies
your result set.

Look up both sides in [`index/all-objects.md`](index/all-objects.md) before
joining. Worked example — the classic trap this repo was built around:

| Object | Grain | Meaning |
| --- | --- | --- |
| `bib` | `bib#, tag, tagord` | one row **per MARC tag occurrence** |
| `item` | `item#` | one row **per physical copy** |
| `bib_control` | `bib#` | one row per record |
| `title` | `bib#` | one row per record |

A bib with 2 `590` tags and 3 items produces **6 rows** from a naive
`bib JOIN item`. Neither table is "wrong" — they are simply both children of
`bib#` with no key linking a specific tag row to a specific item row. This holds
on every Horizon installation.

**Joining `bib_control` to `bib` is safe in one direction only.** `bib_control`
is one row per `bib#`, so it never multiplies. But `bib` fans out per tag, so
`bib_control JOIN bib` still yields one row per tag. Collapse it:

```sql
-- WRONG: one row per matching 590; a record with two vendor notes appears twice
SELECT bc.[bib#] FROM bib_control bc
JOIN bib b ON b.[bib#] = bc.[bib#] AND b.tag = '590'
WHERE b.text LIKE '%ProQuest%';

-- RIGHT: EXISTS collapses the tag side to a boolean — one row per bib, always
SELECT bc.[bib#] FROM bib_control bc
WHERE EXISTS (SELECT 1 FROM bib b
              WHERE b.[bib#] = bc.[bib#] AND b.tag = '590'
                AND b.text LIKE '%ProQuest%');
```

Use `EXISTS` to **test** a child condition, `DISTINCT`/aggregation to **collapse**
one, and a plain join only when you genuinely want the fan-out (a detail report,
one row per tag).

**You cannot aggregate an `EXISTS` directly.** This is the most common way the
idiom above breaks — SQL Server rejects a subquery inside an aggregate:

```sql
-- FAILS: Msg 130 — "Cannot perform an aggregate function on an expression
--        containing an aggregate or a subquery."
SELECT COUNT(*) AS total,
       SUM(CASE WHEN EXISTS (SELECT 1 FROM bib p WHERE p.[bib#] = bc.[bib#]
                               AND p.tag = '590' AND p.text LIKE '%ProQuest%')
                THEN 1 ELSE 0 END) AS matching
FROM bib_control bc WHERE bc.create_user = 'CATALOGER';
```

Compute the flag in a derived table (or CTE), then aggregate the flag:

```sql
-- WORKS
SELECT COUNT(*) AS total, SUM(d.is_match) AS matching
FROM (
    SELECT CASE WHEN EXISTS (SELECT 1 FROM bib p WHERE p.[bib#] = bc.[bib#]
                               AND p.tag = '590' AND p.text LIKE '%ProQuest%')
                THEN 1 ELSE 0 END AS is_match
    FROM bib_control bc WHERE bc.create_user = 'CATALOGER'
) d;
```

This comes up constantly when counting "how many records match" alongside "how
many exist" — exactly the shape of a report's summary line.

`(none)` in the grain column means **no unique index exists** — nothing
constrains that object to one row per key. Treat every join to it as a fan-out
risk. See [`index/no-unique-index.md`](index/no-unique-index.md).

## Rule 4 — Do not trust the `PK_` prefix

Horizon names hundreds of *unique indexes* like primary keys — `PK_location`,
`PK_BIB_STATUS`, `PKborrower_barcode` — and they are **not** primary keys. Every
one reports `is_primary_key = no`.

Consequence: **grain comes from unique indexes, not primary keys.** A query or
tool that looks for declared PKs to find join keys will find almost nothing and
conclude, wrongly, that the tables are unkeyed. The generated `index/` pages
already resolve grain from unique indexes — use them.

> **How many at your site:** [`site-profile.md`](site-profile.md#keys--and-the-pk_-trap)
> lists the declared primary keys in full, beside the count of indexes merely
> *named* like one. Expect the declared list to be very short and mostly
> circulation tables.

Never infer a constraint from an index name. Check `is_unique` in
`indexes_and_keys.csv`.

## Rule 5 — Dates are integers, not dates

The most pervasive convention in the schema. A Horizon date column is a
**`smallint` day count**, not a SQL `date`. Time of day, when kept at all, lives
in a **separate paired `_time` column** (`create_date` / `create_time`). Full
list for your database: [`index/date-columns.md`](index/date-columns.md).

```sql
-- RIGHT: exact, index-friendly, self-documenting
WHERE bc.create_date = DATEDIFF(day, '1970-01-01', '2026-08-25')

-- RIGHT: a range. BETWEEN is safe here precisely because there is no time part.
WHERE bc.create_date BETWEEN DATEDIFF(day, '1970-01-01', '2026-08-25')
                         AND DATEDIFF(day, '1970-01-01', '2026-08-31')

-- WRONG: it is not a datetime
WHERE bc.create_date >= '2026-08-25'
-- WRONG: cannot cast an integer day count to a date
WHERE CAST(bc.create_date AS DATE) = '2026-08-25'
```

Write `DATEDIFF(day, '<epoch>', '<date>')` rather than the bare day number: the
intent stays readable and the date changes in one place. To display one, use
`DATEADD(day, <col>, CAST('<epoch>' AS DATE))`.

Because the type is `smallint` (max 32,767), a 1970-anchored encoding runs out
in 2059.

> ### The epoch is site-specific. Check it before writing a dated query.
>
> **Every example in this repository anchors on `1970-01-01`.** That is what the
> reference site measured. It is not a guarantee about yours.
>
> [`site-profile.md`](site-profile.md#epoch) carries the verified answer for your
> database, with the evidence. `Get-SiteProfile.ps1` proves it from a daily
> histogram of `bib_control`: cataloguing stops at weekends, so the correct epoch
> is the one that puts the quiet days on Saturday and Sunday.
>
> **A `MAX(create_date)` sanity check cannot detect a one-day error** — "newest
> record is today" and "newest record is yesterday" are both ordinary. That is
> exactly the error worth catching, because it silently shifts *every* dated
> query by a day and nothing looks broken.
>
> Re-verify after a restore, an upgrade, or on any database you have not profiled.

## Rule 6 — Read the type, not just the name

Horizon leans heavily on user-defined types. The export gives both the declared
type and its base type; you need both. The declared type tells you the column's
*role*; the base type tells you how it *behaves*.

| Declared | Base | Read it as |
| --- | --- | --- |
| `name_string` | `varchar(30)` | operator logins, user names |
| `code_type` | `varchar(7)` | a code that joins to a lookup table |
| `tag_type` | `varchar(5)` | MARC tag |
| `zero_bit` | `bit` | flag defaulting to 0 |
| `zero_int` | `int` | counter defaulting to 0 |

`code_type` columns are the giveaway for a lookup join: `item.collection`
(`code_type`) joins to `collection.collection`, `item.location` to
`location.location`. Your database's full UDT catalogue, with use counts, is in
[`site-profile.md`](site-profile.md#user-defined-types).

**Collation matters for correctness.** Horizon databases are typically
case-insensitive (`_CI_`), so `=` and `LIKE` ignore case — usually desirable.
Confirm yours in [`site-profile.md`](site-profile.md#engine). When you need exact
case, say so explicitly with `COLLATE Latin1_General_CS_AS` — and know why:

> A case-insensitive `%DDA%` also matched the `dDa` sequence formed where a `$d`
> subfield code abuts content beginning `Da…`, producing false positives. Short
> uppercase acronyms need the case-sensitive collation. Long distinctive literals
> like `ProQuest` do not.

## Rule 7 — Know the engine's limits

Horizon databases commonly run at a **low compatibility level**, which gates
T-SQL functions independently of the SQL Server version installed. At the
reference site these were all unavailable:

- `STRING_AGG` — *"'STRING_AGG' is not a recognized built-in function name."*
  At a slightly higher level it exists but rejects `WITHIN GROUP`.
- `CONCAT`, `IIF`, `FORMAT`, `OFFSET/FETCH`.

`FOR XML PATH` is the usual pre-2017 substitute for string aggregation, but it
**fails on `bib.text`**, which embeds `CHAR(31)`/`CHAR(30)` control characters
that are illegal in XML. It is safe for clean identifiers.

> **What your engine actually allows** is probed and tabulated in
> [`site-profile.md`](site-profile.md#engine-features) — each feature was run,
> not inferred from a version number.

Everything shipped here is written to the lower common denominator — `CASE` for
`IIF`, `+` for `CONCAT`, `TOP` for `OFFSET/FETCH` — so it runs regardless. Keep
it that way when you add a query: the next site to receive it may be older than
yours.

When you need per-record note text, ship a **second detail query** (one row per
tag) rather than aggregating into one cell.

## Rule 8 — MARC text is not plain text

`bib.text` is `varchar(255)` and stores MARC subfields delimited by control
characters, **not** literal pipes:

- `CHAR(31)` = subfield delimiter (`$a` is `CHAR(31)+'a'`)
- `CHAR(30)` = field terminator

Build values as `CHAR(31)+'a'+@value+CHAR(30)`. Use a readable `'|a'+value`
column **only** for display in audit output, never for what gets written.

Because the column is 255 characters, Horizon **splits long fields across
multiple rows**, incrementing `tagord`. A `245` or `520` may be spread over
several rows; reassembling them means ordering by `tagord`. The `245$a` parser
reused across this repo's reports takes the lowest-`tagord` segment only, which
truncates the rare long title — a deliberate, documented trade.

To target one of several same-`tag` rows, isolate it by `tagord` (e.g.
`MAX(tagord)` for the later duplicate). `HAVING COUNT(*) = N AND MIN(text) =
MAX(text)` is the established idiom for "N identical tags".

## Rule 9 — Respect the repo's audit/update contract

From `CLAUDE.md`, restated because it interacts with everything above:

- Ship the audit `SELECT` **first**; its row count must be recorded before any
  `UPDATE` runs.
- The `UPDATE`'s `FROM`/`JOIN` clauses must be **identical** to the audit's, so
  the affected rows provably match what was reviewed. Diverging them defeats the
  point.
- State that a table or full-database backup is required, and wrap the `UPDATE`
  in a transaction so the row count can be checked before commit.
- A read-only report has no audit/update split — it uses a single
  **The Report (Read-Only)** section and says no backup or transaction is needed.

## Rule 10 — Some tables are not Horizon's

Alongside Horizon's own tables sit local scratch and backup tables: working sets
from past projects, pre-change copies, `tmp*`/`del*`/`*_bak` leftovers. They can
look authoritative and hold arbitrarily stale data. `ITEM_JUV` is not `item`;
`borrower_bak` is not `borrower`.

**Names are suggestive, not authoritative — in both directions.** Horizon itself
ships tables with `tmp`, `del` and `bak` in the name, so a name-based rule
eventually drops a vendor table. Equally, a vendor table rebuilt during an
upgrade carries a recent `create_date` and looks local.

No list of them can be maintained here: it would be specific to one site and
stale after any cleanup. Derive it live instead —
[`solutions/db-scratch-table-cleanup`](../../solutions/db-scratch-table-cleanup/README.md)
classifies by creation-time clustering plus structural signals (column count,
declared PK, user-defined-type columns), which is what actually separates the
two.

Before querying an unfamiliar table, check
[`index/all-objects.md`](index/all-objects.md) and prefer the documented core
tables in [`core/`](core/). If a table's role is unclear, **ask** rather than
assuming it is current.

---

## Before you ship a query — checklist

1. Every table and column name **looked up**, not recalled or inferred.
2. Grain of every joined object checked; fan-out either intended or collapsed
   with `EXISTS`/`DISTINCT`/aggregation.
3. Date predicates use integer day counts against **the epoch in
   [`site-profile.md`](site-profile.md#epoch)**, not date literals or casts.
4. Case sensitivity considered — explicit `COLLATE` where exact case matters.
5. Only T-SQL your engine allows — check
   [`site-profile.md`](site-profile.md#engine-features), and prefer the lower
   common denominator so the query travels.
6. For an `UPDATE`: audit `SELECT` shipped first, identical joins, backup and
   transaction stated.
7. Assumptions you could not verify are **stated in the README**, not left
   silent.

## When the schema changes

Re-run the four export queries in [README.md](README.md), overwrite the CSVs in
`horizon-schema/`, then regenerate both derived layers:

```powershell
powershell -ExecutionPolicy Bypass -File tools\Generate-SchemaDocs.ps1
powershell -ExecutionPolicy Bypass -File tools\Get-SiteProfile.ps1 -Server ILSSERVER -Database ILSDB
```

The first rewrites everything under `index/`; the second rewrites
`site-profile.md`. Hand-written pages (this file, `conventions.md`, `core/*.md`)
are never touched by either and need manual review.
