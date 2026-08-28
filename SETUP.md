# Setup — first run at a new site

About 30 minutes, most of it waiting for exports to save. Everything here is
**read-only against your database**; nothing in this file changes data.

Work through it in order. Steps 1–4 are required before you write your first
query; step 5 is optional.

---

## Before you start

| You need | Why |
| --- | --- |
| SSMS or another T-SQL client | to run the four export queries |
| A SQL login with `VIEW DEFINITION` on the Horizon database | to read the catalog views |
| `VIEW DATABASE STATE` as well | for export query 4 only (row counts) |
| Windows PowerShell 5.1 | the tooling; ships with Windows, nothing to install |
| Git | to keep your site's exports and profile under version control |

No write permission is needed for any of setup. The delete tooling in step 5
needs considerably more, and says so.

---

## Step 1 — Fork or clone, and make it yours

```powershell
git clone <this-repo> horizon-dba-toolkit
cd horizon-dba-toolkit
```

Your exports, your site profile, and any solutions you write are **your site's
data**. Keep them in your own repository — a fork you never push, or a private
copy — and pull from upstream for updates to the docs and tooling.

---

## Step 2 — Export your schema

Open [`docs/schema/README.md`](docs/schema/README.md#building-the-exports) and run
the four queries. For each: **Results to Grid** → right-click the grid →
**Save Results As…** → CSV, saved into `horizon-schema/` under the name the
query's heading gives.

| Query | Save as |
| --- | --- |
| 1 | `horizon-schema/all_tables_all_views.csv` |
| 2 | `horizon-schema/indexes_and_keys.csv` |
| 3 | `horizon-schema/foreign_keys.csv` |
| 4 | `horizon-schema/table_origin_and_rowcounts.csv` *(optional)* |

**Save with no header row** — that is SSMS's default for "Save Results As", and
the generator depends on it. If your client writes headers, delete the first line.

Sanity check: `all_tables_all_views.csv` should have several thousand rows. If it
has a few dozen, your login lacks `VIEW DEFINITION` and you are seeing only what
you own.

---

## Step 3 — Generate the orientation pages

```powershell
powershell -ExecutionPolicy Bypass -File tools\Generate-SchemaDocs.ps1
```

Writes `docs/schema/index/`:

| Page | What it answers |
| --- | --- |
| `all-objects.md` | what exists, and the **grain** of each object |
| `no-unique-index.md` | which objects have no stated grain — fan-out risks |
| `date-columns.md` | every integer date column |
| `joins.md` | the declared foreign keys |

These are generated. Never hand-edit them; re-run the script instead.

---

## Step 4 — Profile your site  ← the one people skip

```powershell
powershell -ExecutionPolicy Bypass -File tools\Get-SiteProfile.ps1 `
    -Server ILSSERVER -Database ILSDB
```

Read-only. Writes [`docs/schema/site-profile.md`](docs/schema/site-profile.md).
It records **no** server, database, login or location name, so the page is safe
to commit even in a public fork.

**Why this matters more than it looks.** The documentation in this repository
states only what is true of Horizon everywhere. Everything else varies between
sites, and this script measures it rather than asserting it:

- your **compatibility level**, and which T-SQL functions actually work — probed
  by running them, not inferred from a version number
- your **collation**, and therefore whether `LIKE 'DDA'` matches `dda`
- your **recovery model**, which decides whether `SELECT ... INTO` is cheap
- how many primary keys are genuinely **declared**, versus how many indexes are
  merely *named* like one
- **the epoch your integer date columns count from**

That last one is the reason the script exists.

> ### Read the epoch verdict before writing any dated query
>
> Horizon stores dates as `smallint` day counts from a fixed anchor. Every
> example in this repository uses `1970-01-01`, which is what the reference site
> measured. **If your anchor differs by even one day, every dated query you write
> is wrong by a day and nothing will tell you.**
>
> A `MAX(create_date)` check cannot catch it: "newest record is today" and
> "newest record is yesterday" both look fine. So the script uses the weekend
> instead — cataloguing stops on Saturday and Sunday, and only the correct anchor
> puts the quiet days there. It scores every candidate from −3 to +3 days and
> reports whether the winner is unambiguous.
>
> The console output says `VERIFIED` or it does not. If it does not, read the
> Epoch section of the profile and settle it by hand using the procedure in
> [`conventions.md`](docs/schema/conventions.md#the-epoch--verify-it-never-assume-it)
> before going any further.

Commit the profile. It is the page the rest of the documentation links to.

---

## Step 5 — Optional: the batch-delete tooling

Only if you intend to delete records in batch with Horizon's `killbib` utility.
Skip it otherwise; nothing else depends on it.

1. Read [`docs/killbib.md`](docs/killbib.md) **first**, in full. It documents
   five behaviours that are not in the vendor's `/?` output and that each cost
   somebody an afternoon — including that there is **no dry-run mode**.
2. Locate the executable:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\Find-KillBib.ps1
   ```

3. Confirm your Horizon staff account has the bib-delete permission, and note
   your **Horizon User ID** (`/r`) and **location code** (`/l`). The Horizon User
   ID is *not* the SQL login — they are different identities and the tool needs
   both.
4. Work through [`tools/README.md`](tools/README.md) before your first run.

---

## Step 6 — Protect your site's identifiers

If your fork will ever be public, or shared with the vendor, create the denylist
now:

```powershell
Set-Content -Path tools\.redaction-denylist.txt -Encoding utf8 -Value @(
    'your-real-server-name'
    'your-real-database-name'
    'your-real-sql-login'
    'YOURHZUSERID'
    'YOURLOCCODE'
    'a-staff-username'
)
```

That file is **gitignored**, so the real values never enter the repository. The
test suite reads it and fails if any listed value appears in a tracked file:

```powershell
powershell -ExecutionPolicy Bypass -File tools\Test-Tools.ps1
```

Use the placeholders in [`CLAUDE.md`](CLAUDE.md#never-publish-real-site-identifiers)
in documentation instead. Add a value to the denylist the moment you learn it.

---

## You are set up when

```powershell
powershell -ExecutionPolicy Bypass -File tools\Test-Tools.ps1
```

...passes, and all four of these exist:

- [ ] `horizon-schema/*.csv` — your exports
- [ ] `docs/schema/index/*.md` — generated orientation pages
- [ ] `docs/schema/site-profile.md` — with an epoch verdict you have read
- [ ] `tools/.redaction-denylist.txt` — if the fork will be shared

Then read [`docs/schema/AGENTS.md`](docs/schema/AGENTS.md) and write your first
query. To scaffold a new solution:

```powershell
powershell -ExecutionPolicy Bypass -File tools\New-Solution.ps1 `
    -Name 245-missing-subfield-a -Type Report `
    -Summary "Bibs whose 245 has no subfield a."
```

---

## Re-run setup after

| Event | Re-run |
| --- | --- |
| Horizon upgrade | steps 2, 3, 4 |
| Compatibility-level change | step 4 |
| Restore from another site's backup | steps 2, 3, 4 — **especially the epoch check** |
| Adding or dropping tables | steps 2, 3 |
| Scratch-table cleanup | steps 2, 3, 4 |
