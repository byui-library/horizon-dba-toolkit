# Handoff: ProQuest EBC batch removal

**State as of 2026-11-25.** Handed from the maintainer to the cataloger mid-job.
Placeholders follow [`CLAUDE.md`](../../CLAUDE.md#never-publish-real-site-identifiers):
`CATALOGER` is the account that created the batch, `HZUSER` your Horizon login,
`LOC` the location code, and `ILSSERVER`/`ILSDB` the database. **The real
values are in the private handoff file** sent with your `site.local.psd1`.

Read [`README.md`](README.md) in this folder first. This note only records
where the job stands.

---

## The request

Remove the batch of records created on **2026-10-26** that have **ProQuest in
a 590** (about 2,470). Then produce a CSV of every **remaining** ProQuest Ebook
Central record: `bib#`, the EBC number from the `035`, and the `590`s.

## Done

| Step | Result |
| --- | --- |
| 1a: who created the batch | One account, `CATALOGER`: 2,470 records that day, **all** with a ProQuest 590. Another account created 17 records that day, none with ProQuest, so they are untouched. |
| 1b / 1c: the list and count gate | **2,470** bibs; 2,470 have an EBC 035; 0 do not; **2,470 items** (one per bib). |
| 1d: cataloger review list | 2,470 rows with title, EBC number and 590. Sent for review on 2026-11-25. **Awaiting sign-off.** |
| 4a: baseline before the delete | EBC 035 + ProQuest 590: **256,688** · EBC 035 only: **1** · ProQuest 590 but no EBC: **49,472** |
| Dry run (`-WhatIfOnly`) | Passed: location valid, count matched 2,470. The step-3 warning is explained below. |
| Reference copies | `PQ_EBC_20261026_bak_bib` (94,009 rows), `_bak_bibctl`, `_bak_title`, `_bak_item` (2,470 each). Created 2026-11-25 15:12. |
| Long-field check | No record in the batch has its ProQuest 590 only in `bib_longtext`, so the selection misses nothing. The queries now read long fields too. |

**The step-3 warning ("filter has never excluded anything")** is expected. The
creating account is a replacement account, first used in September 2026, and
has been used only for ProQuest loads: 3,189 records on one day in September,
4,452 across three days in October. Every one has a ProQuest 590, so the filter
has nothing to exclude. The delete is still exactly what was asked for.

## Open questions for the requester

1. **The account's other loads.** About 5,170 ProQuest records were loaded by the
   same account on three other days (one in September, two in October). This
   job removes only 26 October. Should any of the others go too? That would be
   a separate run with a different `-CreateDate`.
2. **49,472 records have a ProQuest 590 but no EBC number in the 035.** The
   final report is built from the EBC 035, as requested, so it leaves them out.
   Do they want those listed separately?

## Next steps

### 1. Cataloger sign-off on the review list

If any records must be kept, **stop**. The delete list is built from the
operator, date and note, so removing individual bibs needs a different approach.
Take it back to the maintainer.

### 2. Trial delete, then the rest: run by you, not Codex

Note the clock time first. Then, in a PowerShell terminal at the toolkit root:

```text
& ".\tools\Invoke-DeleteListRun.ps1" -Server ILSSERVER -Database ILSDB -Table PQ_EBC_20261026_DeleteList -CreateUser CATALOGER -CreateDate 2026-10-26 -ExpectedRows 2470 -NoteTag 590 -NoteTerm ProQuest -Epoch 1970-01-01 -Brutal -Trial
```

It asks for your Horizon User ID (`/r`) and location (`/l`), then the KillBib
SQL login. You type `2470`, then the trial bib number. It deletes **one** bib
and stops, reporting "2469 of 2470 still present". That is expected. Check the
trial bib is gone in the Horizon client, then:

```text
& ".\tools\Invoke-KillBib.ps1" -Server ILSSERVER -Database ILSDB -Table PQ_EBC_20261026_DeleteList -ExpectedRows 2470 -HorizonUserId HZUSER -Location LOC -Brutal -SkipTrial -Force
```

Do **not** re-run the first command for the rest: it would find 2,469 records,
not 2,470, and abort.

Both commands record their start and finish times, by the server's clock and
yours, in `killbib-audit\PQ_EBC_20261026_DeleteList-runs.log`. The server's
start time is the restore point if the delete ever has to be undone. The
database runs in full recovery with hourly log backups, so a point-in-time
restore to a side copy is possible.

### 3. Verify (Codex can do this)

- README **Step 3**: both counts against the list table must be **0**.
- Re-run **1c**: `bibs` must be **0**.
- Re-run **4a** and compare with the baseline:

| | Before | Expected after |
| --- | ---: | ---: |
| EBC 035 + ProQuest 590 | 256,688 | **254,218** |
| EBC 035 only | 1 | **1** |
| ProQuest 590, no EBC | 49,472 | **49,472** |

Any other change means something else touched the catalog during the job. Find
out what before sending the report.

### 4. The final report (Codex can do this)

Run README **4b** and save the CSV:

```text
powershell -ExecutionPolicy Bypass -File tools\Invoke-ReadOnlyQuery.ps1 -File solutions\590-proquest-ebc-batch-removal\sql\07-4b-the-report.sql -OutCsv "excel reports\ebc-remaining-records.csv"
```

Expect **254,219** rows. One row per bib: `bib#`, `EBC_035`, `590_fields`.

### 5. Clean-up (maintainer)

After the requester signs off, the maintainer drops `PQ_EBC_20261026_DeleteList`
and the four `PQ_EBC_20261026_bak_*` tables. Your access is read-only, so you
cannot drop them.
