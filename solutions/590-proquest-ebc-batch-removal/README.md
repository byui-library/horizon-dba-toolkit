# ProQuest EBC Batch Removal and Remaining-Records Report

## The Problem

A batch of ProQuest ebook records was loaded into the catalog on one day and has
to come out again, as part of a de-duplication against ProQuest Ebook Central
(EBC). The request identifies the batch by two facts only:

- **date created `2026-10-26`**, and
- **"ProQuest" somewhere in a `590`** (local note),

with an expected size of **about 2,470 records**. Once those are gone, the
requester wants a CSV of every **remaining** Ebook Central record holding
exactly three things: the Horizon `bib#`, the EBC number from the MARC `035`, and
the record's `590` fields.

So this is two jobs in order: a delete, then a read-only report.

| Step | What | Changes data? |
| --- | --- | --- |
| 1 | Audit: who created the batch, list it, count it | no |
| 2 | Delete it with `tools\Invoke-DeleteListRun.ps1` (KillBib) | **yes, irreversible** |
| 3 | Verify the delete | no |
| 4 | The Report: remaining EBC records → CSV | no |

### Why "date + 590" is not yet a complete selection

The delete tooling selects on **operator + date + note**:
`Invoke-DeleteListRun.ps1` requires `-CreateUser`, and the request does not name
one. Query 1a finds it from the data rather than guessing. If more than one
operator created ProQuest-590 records that day, **stop and go back to the
requester**: either the batch was loaded by more than one account, or something
else matches the filter and should not be deleted.

`create_date` is a `smallint` day count, not a date — see
[`AGENTS.md` Rule 5](../../docs/schema/AGENTS.md#rule-5--dates-are-integers-not-dates).
Every query below uses the `1970-01-01` epoch, which is what
[`site-profile.md`](../../docs/schema/site-profile.md#epoch) records as verified
for this site. **If you run this at a different site, check your own epoch
first** — an epoch that is one day out selects the wrong day's records, and the
count still looks plausible.

### The "Cartesian Product" Challenge

`bib` is one row **per MARC tag occurrence**. A record with two `590`s (a vendor
note and a package note, say) or two `035`s has two rows of each. Joining
`bib_control` to `bib` on `590` would list that record twice, inflate the count,
and break the count gate in Step 2.

Every query here therefore starts from `bib_control` (one row per `bib#`) and
tests the tag side with `EXISTS`, or collapses it inside a correlated
subquery. `item` (one row per copy) is only ever counted inside a scalar
subquery, never joined.

### A backup is required before Step 2

KillBib **has no dry-run and no undo** (see
[`docs/killbib.md`](../../docs/killbib.md#2-there-is-no-dry-run)). Take a full
database backup, or at minimum a backup of `bib`, `bib_control` and `item`,
before Step 2. Run **Query 4a before the delete as well as after** — the
before-and-after difference is the reconciliation for the whole job.

---

## Step 1: The Audit

All three queries are read-only. **Run them first and record the counts.**

### 1a. Who created the batch

One row per operator who created any record on `2026-10-26`. It shows how many
of each operator's records that day carry a ProQuest `590`.

```sql
-- One row per create_user active on the target day.
-- has_pq590 is computed in a derived table because an EXISTS cannot be
-- aggregated directly (Msg 130 - AGENTS.md Rule 3).
SELECT
    d.create_user,
    COUNT(*)         AS [created_that_day],
    SUM(d.has_pq590) AS [with_proquest_590]
FROM (
    SELECT
        bc.create_user,
        CASE WHEN EXISTS (
                SELECT 1 FROM bib p
                WHERE p.[bib#] = bc.[bib#]
                  AND p.tag = '590'
                  AND p.text LIKE '%ProQuest%')
             THEN 1 ELSE 0 END AS has_pq590
    FROM bib_control bc
    WHERE bc.create_date = DATEDIFF(day, '1970-01-01', '2026-10-26')
) d
GROUP BY d.create_user
ORDER BY SUM(d.has_pq590) DESC;
```

**What to expect:** one operator whose `with_proquest_590` is close to 2,470.
Substitute that operator for `CATALOGER` in 1b, 1c and Step 2.

- **Two or more operators** with non-zero `with_proquest_590`: stop, and ask
  the requester which of them belong to the batch.
- `created_that_day` **greater than** `with_proquest_590` for the batch operator:
  that operator also created records that day *without* a ProQuest `590`. The
  note filter is doing real work and those records will be kept. That is
  normal. Mention it to the requester.
- **Nothing near 2,470:** do not proceed. Re-check the date with the requester
  and the epoch in `site-profile.md`.

### 1b. The delete list, with the evidence

One row per `bib#` that Step 2 will delete. The `WHERE` clause is
**the same predicate `Invoke-DeleteListRun.ps1` builds** (its `$predicate`)
from `-CreateUser`, `-CreateDate`, `-NoteTag 590` and `-NoteTerm ProQuest`, so
this list is exactly what KillBib will be given.

```sql
SELECT
    bc.[bib#],
    bc.create_user,
    DATEADD(day, bc.create_date, CAST('1970-01-01' AS DATETIME)) AS [created],
    CASE WHEN EXISTS (
            SELECT 1 FROM bib e
            WHERE e.[bib#] = bc.[bib#]
              AND e.tag = '035'
              AND e.text COLLATE Latin1_General_CS_AS LIKE '%EBC[0-9]%')
         THEN 'Y' ELSE 'N' END                                  AS [has_ebc_035],
    (SELECT COUNT(*) FROM item i WHERE i.[bib#] = bc.[bib#])    AS [items_deleted_by_k]
FROM bib_control bc
WHERE bc.create_user = 'CATALOGER'
  AND bc.create_date = DATEDIFF(day, '1970-01-01', '2026-10-26')
  AND EXISTS (
        SELECT 1 FROM bib p
        WHERE p.[bib#] = bc.[bib#]
          AND p.tag = '590'
          AND p.text LIKE '%ProQuest%')
ORDER BY bc.[bib#];
```

Spot-check a handful of these in the Horizon client before going on. Save the
grid as the requester's record of what was removed.

### 1c. The count gate

The same predicate, summarised. **`bibs` is the number you pass to
`-ExpectedRows` in Step 2.** It must equal the row count of 1b.

```sql
SELECT
    COUNT(*)                AS [bibs],
    SUM(d.has_ebc)          AS [with_ebc_035],
    COUNT(*) - SUM(d.has_ebc) AS [without_ebc_035],
    SUM(d.items)            AS [items_deleted_by_k]
FROM (
    SELECT
        CASE WHEN EXISTS (
                SELECT 1 FROM bib e
                WHERE e.[bib#] = bc.[bib#]
                  AND e.tag = '035'
                  AND e.text COLLATE Latin1_General_CS_AS LIKE '%EBC[0-9]%')
             THEN 1 ELSE 0 END                               AS has_ebc,
        (SELECT COUNT(*) FROM item i WHERE i.[bib#] = bc.[bib#]) AS items
    FROM bib_control bc
    WHERE bc.create_user = 'CATALOGER'
      AND bc.create_date = DATEDIFF(day, '1970-01-01', '2026-10-26')
      AND EXISTS (
            SELECT 1 FROM bib p
            WHERE p.[bib#] = bc.[bib#]
              AND p.tag = '590'
              AND p.text LIKE '%ProQuest%')
) d;
```

How to read it:

- `bibs` should be close to 2,470. The request says "approx." — a difference of
  a few is plausible; hundreds is not.
- `without_ebc_035` greater than zero means part of the batch is ProQuest but
  carries no EBC number. The request is to remove **all** of the batch, so they
  stay on the list — but tell the requester the number, because those records
  will not show up in the Step 4 report's reconciliation either way.
- `items_deleted_by_k` is what `-Brutal` (`/k`) will also remove. For an ebook
  load expect it to be zero or one per bib. Anything bigger means print copies
  are attached, and you should stop and look.

### 1d. Cataloger review: title and ProQuest note

The same list as 1b, laid out for a cataloger to review before anything is
deleted. There is one row per `bib#`, with the `245` shown in subfield form.

| Column | Contents |
| --- | --- |
| `bib#` | Horizon record number |
| `title_245` | The `245` as catalogued, `\|a… :\|b… /\|c…` |
| `EBC_035` | The EBC number(s) from the `035` |
| `proquest_590` | Only the `590`s that mention ProQuest, ` ;; `-separated |

The title is the `245` itself, not `title.processed`. `processed` is normalised
for indexing, which strips punctuation and subfield boundaries, and the
`reconst` column beside it is not human-readable at all.

A field longer than 255 characters has `bib.text` NULL, with the whole field in
`bib_longtext` (see [Notes and edge cases](#notes-and-edge-cases) below).
Long titles are common, so the `245` and the `590`s are read through
`COALESCE(text, longtext)`. The join to `bib_longtext` is on its unique key
`bib#, tag, tagord`, so it cannot multiply rows.

A record usually carries the same EBC number in two `035`s (`EBC4876992` and
`(MiAaPQ)EBC4876992`). The `GROUP BY` lists each number once.

The `WHERE` is the 1b predicate unchanged.

```sql
SELECT
    bc.[bib#] AS [bib#],
    (SELECT TOP 1 REPLACE(REPLACE(COALESCE(t.text, CAST(tl.longtext AS varchar(8000))),
                                  CHAR(31), '|'), CHAR(30), '')
     FROM bib t
     LEFT JOIN bib_longtext tl
            ON tl.[bib#] = t.[bib#] AND tl.tag = t.tag AND tl.tagord = t.tagord
     WHERE t.[bib#] = bc.[bib#] AND t.tag = '245'
     ORDER BY t.tagord) AS [title_245],
    STUFF((
        SELECT ' ;; ' + x.ebc
        FROM (
            SELECT
                s.tagord,
                LEFT(s.frag, 2 + PATINDEX('%[^0-9]%', SUBSTRING(s.frag, 4, 255) + 'x')) AS ebc
            FROM (
                SELECT
                    e.tagord,
                    SUBSTRING(e.text,
                              PATINDEX('%EBC[0-9]%', e.text COLLATE Latin1_General_CS_AS),
                              255) AS frag
                FROM bib e
                WHERE e.[bib#] = bc.[bib#]
                  AND e.tag = '035'
                  AND e.text COLLATE Latin1_General_CS_AS LIKE '%EBC[0-9]%'
            ) s
        ) x
        GROUP BY x.ebc
        ORDER BY MIN(x.tagord)
        FOR XML PATH('')
    ), 1, 4, '') AS [EBC_035],
    REPLACE(REPLACE(REPLACE(STUFF((
        SELECT ' ;; ' + REPLACE(REPLACE(COALESCE(n.text, CAST(nl.longtext AS varchar(8000))),
                                        CHAR(31), '|'), CHAR(30), '')
        FROM bib n
        LEFT JOIN bib_longtext nl
               ON nl.[bib#] = n.[bib#] AND nl.tag = n.tag AND nl.tagord = n.tagord
        WHERE n.[bib#] = bc.[bib#]
          AND n.tag = '590'
          AND COALESCE(n.text, CAST(nl.longtext AS varchar(8000))) LIKE '%ProQuest%'
        ORDER BY n.tagord
        FOR XML PATH('')
    ), 1, 4, ''), '&lt;', '<'), '&gt;', '>'), '&amp;', '&') AS [proquest_590]
FROM bib_control bc
WHERE bc.create_user = 'CATALOGER'
  AND bc.create_date = DATEDIFF(day, '1970-01-01', '2026-10-26')
  AND EXISTS (
        SELECT 1 FROM bib p
        WHERE p.[bib#] = bc.[bib#]
          AND p.tag = '590'
          AND p.text LIKE '%ProQuest%')
ORDER BY bc.[bib#];
```

It must return the same row count as 1b. Save it as CSV with quoting switched on
(see [Saving it as CSV](#saving-it-as-csv)). Titles contain commas just as
`590`s do.

---

## Step 2: The Delete

This is the irreversible step. It uses the repository's wrapper rather than
KillBib directly. Read [`docs/killbib.md`](../../docs/killbib.md) in full first,
and [`tools/README.md`](../../tools/README.md#the-batch-delete--one-command) for
what each of the ten steps does.

The wrapper's selection predicate is **identical** to the `WHERE` in 1b and 1c.
That is this solution's version of the audit/update guarantee. If you change
the operator, date, tag or term in one place, change them in all three.

### 2a. Dry run

Runs the wrapper's steps 1–3 only: validate, count-gate, discriminator check.
It creates nothing and deletes nothing. Replace `CATALOGER` with the operator
from 1a, and `2470` with the `bibs` count from 1c. A mismatch makes it abort,
which is the point.

```text
& "C:\path\to\repo\tools\Invoke-DeleteListRun.ps1" -Table PQ_EBC_20261026_DeleteList -CreateUser CATALOGER -CreateDate 2026-10-26 -ExpectedRows 2470 -NoteTag 590 -NoteTerm ProQuest -Epoch 1970-01-01 -Brutal -WhatIfOnly
```

The table name is 26 characters, inside KillBib's 30-character limit
([why that matters](../../docs/killbib.md#1-the-t-table-name-is-truncated-at-31-characters)).

### 2b. The run

**Backup taken? Query 4a run and its counts recorded?** Then:

```text
& "C:\path\to\repo\tools\Invoke-DeleteListRun.ps1" -Table PQ_EBC_20261026_DeleteList -CreateUser CATALOGER -CreateDate 2026-10-26 -ExpectedRows 2470 -NoteTag 590 -NoteTerm ProQuest -Epoch 1970-01-01 -StaffPrincipal staff_readers -Brutal -Trial
```

The wrapper prompts for the Horizon User ID (`/r`) and location (`/l`), builds
and checks the list, writes the `bib#` list to `killbib-audit\`, and asks you to
type the row count. With `-Trial` it then deletes **one bib only and stops**.
Its step 10 will report 2,469 bibs still present; that is expected after a trial.
Check the trial bib is gone in the client, then delete the rest by calling
KillBib's wrapper directly against the list the first command built:

```text
& "C:\path\to\repo\tools\Invoke-KillBib.ps1" -Table PQ_EBC_20261026_DeleteList -ExpectedRows 2470 -Brutal -SkipTrial -Force
```

Do **not** re-run `Invoke-DeleteListRun.ps1` for the second part. Its count gate
would now find 2,469 rows, not 2,470, and abort. Rebuilding the list would also
discard the record of the trial bib.

Every KillBib invocation appends its start and finish time, by both the SQL
Server clock and the local clock, to
`killbib-audit\PQ_EBC_20261026_DeleteList-runs.log`. The server-clock `START`
time is the restore point for `RESTORE ... WITH STOPAT` if the delete ever has
to be undone.

`-Brutal` (`/k`) also removes the items, copies and circulation data attached to
these bibs — the count is `items_deleted_by_k` in 1c. Without it, KillBib still
deletes the bib records and their `bib_control` rows. The difference is only
whether attached items are left behind as orphans.

If it stops partway, **do not re-run from the top.** It prints the diagnostic and
the exact resume command — see
[`docs/killbib.md`](../../docs/killbib.md#resuming-a-stopped-run).

---

## Step 3: Verify the Delete

The wrapper runs these for you in its step 10. Run them again yourself before
reporting back.

```sql
SELECT COUNT(*) AS [bibs_left]
FROM bib_control bc
INNER JOIN dbo.PQ_EBC_20261026_DeleteList d ON d.[bib#] = bc.[bib#];   -- expect 0

SELECT COUNT(*) AS [items_left]
FROM item i
INNER JOIN dbo.PQ_EBC_20261026_DeleteList d ON d.[bib#] = i.[bib#];    -- expect 0
```

Then re-run **1c**: `bibs` must now be **0**.

Do not drop `PQ_EBC_20261026_DeleteList` until the requester has signed off.
The audit CSV in `killbib-audit\` holds the same list, but the table is easier to
join against if a question comes back.

---

## Step 4: The Report (Read-Only)

A `SELECT` only. No backup or transaction is needed. Run it **after** Step 3.

### Which records count as "ProQuest Ebook Central"

A record counts if it has **an `035` containing `EBC` followed by a digit** —
the Ebook Central control number, normally `(MiAaPQ)EBC1234567`. The match is
case-sensitive (`COLLATE Latin1_General_CS_AS`). The column's default collation
is case-insensitive, so without it `%EBC%` also matches lowercase text such as
the "ebc" inside "Debc…". See
[`AGENTS.md` Rule 6](../../docs/schema/AGENTS.md#rule-6--read-the-type-not-just-the-name).

The test is deliberately on the `035`, not on the `590`. The requester asked for
the EBC number, which a record without an EBC `035` does not have. 4a counts the
records each definition catches, so the requester can see what this choice
leaves out.

### 4a. Reconciliation counts

Run **before Step 2 and again after Step 3**. Afterwards,
`ebc_035_and_proquest_590` plus `ebc_035_only` is the row count the report below
must return.

```sql
SELECT
    SUM(CASE WHEN d.has_ebc = 1 AND d.has_pq = 1 THEN 1 ELSE 0 END) AS [ebc_035_and_proquest_590],
    SUM(CASE WHEN d.has_ebc = 1 AND d.has_pq = 0 THEN 1 ELSE 0 END) AS [ebc_035_only],
    SUM(CASE WHEN d.has_ebc = 0 AND d.has_pq = 1 THEN 1 ELSE 0 END) AS [proquest_590_only_not_in_report]
FROM (
    SELECT
        CASE WHEN EXISTS (
                SELECT 1 FROM bib e
                WHERE e.[bib#] = bc.[bib#]
                  AND e.tag = '035'
                  AND e.text COLLATE Latin1_General_CS_AS LIKE '%EBC[0-9]%')
             THEN 1 ELSE 0 END AS has_ebc,
        CASE WHEN EXISTS (
                SELECT 1 FROM bib p
                WHERE p.[bib#] = bc.[bib#]
                  AND p.tag = '590'
                  AND p.text LIKE '%ProQuest%')
             THEN 1 ELSE 0 END AS has_pq
    FROM bib_control bc
) d;
```

Between the before and after runs, the two EBC columns together should fall by
`with_ebc_035` from 1c, and `proquest_590_only_not_in_report` by
`without_ebc_035`. Any other change means records were added or deleted by
something else while the job ran. Find out what before sending the report.

### 4b. The report

One row per remaining EBC `bib#`, in exactly the three columns requested:

| Column | Contents |
| --- | --- |
| `bib#` | Horizon record number |
| `EBC_035` | The EBC number(s) from the `035`, e.g. `EBC1234567` |
| `590_fields` | Every `590` on the record, in `tagord` order |

A record can have several `590`s, and occasionally several EBC `035`s. These are
joined into one cell with ` ;; ` between them, so the CSV stays one row per
record. `STRING_AGG` is not available at a low compatibility level, so the
join uses `FOR XML PATH('')`. Two consequences:

- The `CHAR(31)`/`CHAR(30)` delimiters are replaced **before** aggregation, so
  they never reach the XML step and never come out entity-escaped. Subfields
  display as `|a…|b…`.
- `FOR XML` escapes `&`, `<` and `>` as entities. The outer `REPLACE`s convert
  them back, `&amp;` last so an escaped literal `&lt;` is not unescaped twice.

Long `590`s are read from `bib_longtext`, and each EBC number appears once,
exactly as in 1d.

```sql
SELECT
    r.[bib#] AS [bib#],
    STUFF((
        SELECT ' ;; ' + x.ebc
        FROM (
            SELECT
                s.tagord,
                LEFT(s.frag, 2 + PATINDEX('%[^0-9]%', SUBSTRING(s.frag, 4, 255) + 'x')) AS ebc
            FROM (
                SELECT
                    e.tagord,
                    SUBSTRING(e.text,
                              PATINDEX('%EBC[0-9]%', e.text COLLATE Latin1_General_CS_AS),
                              255) AS frag
                FROM bib e
                WHERE e.[bib#] = r.[bib#]
                  AND e.tag = '035'
                  AND e.text COLLATE Latin1_General_CS_AS LIKE '%EBC[0-9]%'
            ) s
        ) x
        GROUP BY x.ebc
        ORDER BY MIN(x.tagord)
        FOR XML PATH('')
    ), 1, 4, '') AS [EBC_035],
    REPLACE(REPLACE(REPLACE(STUFF((
        SELECT ' ;; ' + REPLACE(REPLACE(COALESCE(n.text, CAST(nl.longtext AS varchar(8000))),
                                        CHAR(31), '|'), CHAR(30), '')
        FROM bib n
        LEFT JOIN bib_longtext nl
               ON nl.[bib#] = n.[bib#] AND nl.tag = n.tag AND nl.tagord = n.tagord
        WHERE n.[bib#] = r.[bib#]
          AND n.tag = '590'
        ORDER BY n.tagord
        FOR XML PATH('')
    ), 1, 4, ''), '&lt;', '<'), '&gt;', '>'), '&amp;', '&') AS [590_fields]
FROM (
    SELECT DISTINCT b.[bib#]
    FROM bib b
    WHERE b.tag = '035'
      AND b.text COLLATE Latin1_General_CS_AS LIKE '%EBC[0-9]%'
) r
ORDER BY r.[bib#];
```

**Row count check:** it must equal `ebc_035_and_proquest_590 + ebc_035_only`
from the post-delete run of 4a. The `DISTINCT` derived table is what holds it
to one row per bib. Without it, a record with two EBC `035`s would appear twice.

### Saving it as CSV

In SSMS: right-click the results grid → **Save Results As…** → CSV.

> **Turn on quoting first, or the CSV will be wrong.** `590` text is full of
> commas, and by default SSMS writes them unquoted, which shifts every later
> column on that row. Set **Tools → Options → Query Results → SQL Server →
> Results to Grid → "Quote strings containing list separators when saving .csv
> results"**, then **open a new query window** (the setting applies to new
> windows only) and re-run before saving.

Also tick **"Include column headers when copying or saving the results"** on the
same page, so the requester gets the three column names. The result is catalog
data, not patron data, but it still does not belong in this repository.
`.gitignore` blocks `*.csv`.

---

## Notes and edge cases

- **`%ProQuest%` is case-insensitive** and deliberately so. It matches
  `PROQUEST` and `Proquest` too. A long distinctive literal cannot be forged at a
  subfield boundary the way a short acronym can
  ([`bib.md`](../../docs/schema/core/bib.md#case-sensitivity-when-matching-text)).
  It is the wrapper's default `-NoteTerm`, passed explicitly here anyway.
- **The ProQuest `590` test is not restricted to `|a`.** "ProQuest" anywhere in
  any `590` qualifies, matching the request's "ProQuest in a 590 field".
- **No collection or item-type filter** is applied to the delete. The request
  defines the batch by date and note alone. If 1b shows records that are not
  ebooks, stop.
- **EBC number extraction** takes `EBC` plus the run of digits after it, and
  stops at the first non-digit (a subfield delimiter, a space, a suffix). An
  `035` such as `(MiAaPQ)EBC1234567` yields `EBC1234567`.
- **Long fields live in `bib_longtext`.** Measured on 2026-11-25: when a field is longer than
  `bib.text`'s 255 characters, its `bib` row keeps `tag` and `tagord` but
  `text` is **NULL**, and the whole field is in `bib_longtext.longtext`
  (`text` type), keyed uniquely by `bib#, tag, tagord`. It is not split across
  `bib` rows. Two consequences:
  - **Display:** every query that shows field text here reads
    `COALESCE(text, longtext)`. Otherwise long titles and notes come out blank.
  - **Filtering:** the selection's `p.text LIKE '%ProQuest%'` cannot see a long
    `590`. That was checked before the delete. No record created that day has a
    ProQuest `590` only in `bib_longtext`, and across the catalog every record
    with a long ProQuest `590` also has a short one. So neither the delete nor
    4a's counts are affected. **Re-check this before reusing these queries for a
    different batch.** Long `035`s exist too, but they are OCLC numbers, and none
    held an EBC number.
- **The report includes records that have no `590`.** An EBC record with no
  local note still appears, with an empty `590_fields` — it is still a
  remaining EBC record, which is what was asked for.
- **Dates.** `create_date` is compared as an integer day count. Do not rewrite
  it as a date literal or a `CAST`; see
  [`AGENTS.md` Rule 5](../../docs/schema/AGENTS.md#rule-5--dates-are-integers-not-dates).
