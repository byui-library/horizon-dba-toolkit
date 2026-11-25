# AGENTS.md

Instructions for an AI coding agent (OpenAI Codex, or any assistant that reads
`AGENTS.md`) working in this repository on behalf of a **cataloger**. Claude
Code reads [`CLAUDE.md`](CLAUDE.md) instead. The rules are the same, and this
file adds the ones specific to the cataloger's role.

## Who you are working with

The person in front of you is an expert cataloger: they know MARC, Horizon's
client and the catalog far better than you do. They are **not** a SQL or
PowerShell user. So:

- **Before running a query, say in one or two plain sentences what it will
  look for** ("This counts records created on 26 October that have ProQuest in
  a 590"). Show the SQL too, but never make them read it to follow you.
- **After it runs, lead with the answer** in catalog terms (counts, examples,
  bib numbers), then the detail. Translate errors; do not paste a stack trace
  and stop.
- Use MARC vocabulary freely (tags, indicators, subfields). Avoid database
  jargon, or explain it once.
- When something is ambiguous about the *catalog* (which records, which tag,
  which date), ask them. When it is about the *database* (which column, which
  table), look it up yourself. Do not ask them to.

## Hard rules

These are not defaults to weigh against convenience. Never break them, even if
asked. Explain why instead, and offer the allowed route.

1. **Query the database only through `tools\Invoke-ReadOnlyQuery.ps1`.** It
   reads the connection from the gitignored `tools\site.local.psd1`, refuses
   anything that writes, and rolls back every batch. Do not open your own
   connection (no `sqlcmd`, no ad-hoc `SqlConnection`), and never edit that
   script to loosen it.

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\Invoke-ReadOnlyQuery.ps1 -Sql "SELECT COUNT(*) AS n FROM bib_control"
   powershell -ExecutionPolicy Bypass -File tools\Invoke-ReadOnlyQuery.ps1 -File solutions\<name>\sql\01-....sql -OutCsv "excel reports\<name>.csv"
   ```

   If it prints `REFUSED`, nothing reached the database. Rewrite the query as a
   pure `SELECT`; do not look for a way around the check.

   **Why only this route.** The tool connects as the cataloger's own Windows
   login, which may be able to write, and immediately switches to the
   database user `ro_query`, which cannot. Every run prints an `Access:` line,
   which must read `read-only ... as ro_query`. If it warns, or the tool prints
   `STOPPED`, stop and tell the cataloger to contact the maintainer. Do not
   work around it. Any *other* connection skips that switch and runs with the
   cataloger's own rights, so these routes are forbidden without exception,
   even for a "quick look":

   - `sqlcmd`, `osql`, `bcp`, `Invoke-Sqlcmd`, or any `SqlServer`/`dbatools` cmdlet
   - PowerShell or any other code that creates a `SqlConnection`, `OdbcConnection`
     or `OleDbConnection`, or loads `System.Data.SqlClient` yourself
   - `Invoke-DeleteListRun.ps1`, `Invoke-KillBib.ps1`, `Test-DeleteListPreflight.ps1`
   - scripting SSMS, or writing a `.sql` file for the cataloger to run in SSMS
     that contains anything but a `SELECT`

   If a task seems to need one of these, stop and say so.

   **The SQL login is off limits.** The cataloger also has a SQL Server login,
   the one KillBib's credential prompt asks for. It can write. Never ask for
   it, its password, or any other credential; never put one in a command, a
   file or a connection string. The cataloger types it into KillBib's prompt
   himself, and it goes nowhere else.

2. **Never run anything that changes the catalog.** In particular, never run
   `tools\Invoke-DeleteListRun.ps1`, `tools\Invoke-KillBib.ps1` or
   `KillBib.exe`, not even with `-WhatIfOnly` or `-Trial`. Changes to Horizon
   happen only through Horizon's own command-line tools, **typed and run by the
   cataloger**, after review. Your part is to prepare the exact command,
   explain each parameter, and check the output they paste back. The delete
   wrapper does create a scratch list table, but under the KillBib SQL login
   the cataloger types into its prompt, never through your connection.

3. **No commits, no pushes, no branches.** The cataloger uses this repository
   read-only and pulls updates from the maintainer. You may draft new files
   (a new solution README, a query) when asked, but leave them uncommitted and
   tell the cataloger to send them to the maintainer.

4. **Never write a real site identifier into a tracked file**: server and
   database names, logins, Horizon user IDs, location codes, staff usernames.
   Use the placeholders in [`CLAUDE.md`](CLAUDE.md#never-publish-real-site-identifiers)
   (`ILSSERVER`, `ILSDB`, `CATALOGER`, `HZUSER`, `LOC`, ...). Real values live
   only in `tools\site.local.psd1` and `tools\.redaction-denylist.txt`, both
   gitignored. Bib numbers are fine.

5. **Query output is catalog data.** Save CSVs under `excel reports\` or
   `killbib-audit\`, which are gitignored, and never paste bulk results into a
   tracked file. Patron data must never be queried for a report without the
   maintainer's say-so.

## Before you write any SQL

Read these, in this order. They are short, and every rule in them was paid for
with a wrong answer:

1. [`CLAUDE.md`](CLAUDE.md): project rules. They apply to you exactly as
   written. Skip only what is about Claude Code itself.
2. [`docs/schema/AGENTS.md`](docs/schema/AGENTS.md): the schema rules, with a
   pre-flight checklist. The single source of truth for writing SQL here.
3. [`docs/schema/site-profile.md`](docs/schema/site-profile.md): this site's
   measured facts (epoch, compatibility level, collation).

The traps that matter most, in brief. The documents above have the detail.

| Trap | What to do |
| --- | --- |
| A name looks right but was never checked | Look it up live first (below). Never guess a table or column name. |
| `bib` is one row per **tag**, `item` one per **copy** | Never join them directly. Test conditions with `EXISTS`; collapse with `DISTINCT` or aggregation. |
| `bib.text` uses `CHAR(31)` (subfield) and `CHAR(30)` (end of field) | Display as `\|a…` only in output. Never write pipes into data. |
| Fields over 255 characters have `bib.text` **NULL** | The text is in `bib_longtext`. Display with `COALESCE`; check filters for misses. |
| Dates are `smallint` day counts | `create_date = DATEDIFF(day, '<epoch>', '2026-10-26')`, with the epoch taken from [`site-profile.md`](docs/schema/site-profile.md#epoch). Never compare to a date literal. |
| The collation is case-insensitive | Short uppercase codes (`DDA`, `EBC`) need `COLLATE Latin1_General_CS_AS`. |
| The engine may be old | No `STRING_AGG`, `CONCAT`, `IIF`, `FORMAT` or `OFFSET/FETCH`. |
| `PK_*` index names, `tmp*`, `del*`, `*_bak` tables | Not what they look like. Grain comes from unique indexes; scratch tables are not Horizon's. |

### Look names up in the live database

The live database is the authority. The CSV exports in `horizon-schema/` are an
offline fallback and may be stale. Recipes (every column of a table, its unique
indexes, which tables carry a column) are in
[`docs/schema/AGENTS.md`, Rule 2](docs/schema/AGENTS.md#rule-2--look-it-up-like-this).
Run them through `Invoke-ReadOnlyQuery.ps1` like any other query.

## How a typical request goes

1. **Restate it** in catalog terms and confirm anything ambiguous. Often that
   means which records, created when, by whom, carrying which tag or text.
2. **Look up** every table and column you will use.
3. **Check for an existing solution** in [`solutions/`](solutions/). Each
   `README.md` there explains a finished job, and its `sql\` folder holds
   runnable files. Reuse before writing new SQL.
4. **Count before listing.** Run a count, explain it, then fetch the rows.
5. **Report**: the answer first, then a CSV under `excel reports\` if they
   want the rows.

For a **delete**, the sequence is fixed and is set out in
[`docs/killbib.md`](docs/killbib.md) and [`tools/README.md`](tools/README.md):
audit queries (yours), review by the cataloger, dry run (theirs), backup check,
trial (theirs), full run (theirs), post-delete checks (yours). Read
[`solutions/590-proquest-ebc-batch-removal/README.md`](solutions/590-proquest-ebc-batch-removal/README.md)
as the worked example.

## Work in progress

- **ProQuest EBC batch removal (26 Oct 2026 load).** Handed over mid-job. Read
  [`solutions/590-proquest-ebc-batch-removal/HANDOFF.md`](solutions/590-proquest-ebc-batch-removal/HANDOFF.md)
  before doing anything on it. The real values it refers to are in the
  cataloger's private handoff file, not in this repository.

## Tooling you may run

| Script | You may run it? |
| --- | --- |
| `tools\Invoke-ReadOnlyQuery.ps1` | **Yes.** It is your only way into the database. `-CheckAccess` reports what the login could do and runs nothing else. Run it at the start of a session. |
| `tools\Test-Tools.ps1` | Yes. No database involved. |
| `tools\Build-SolutionDocs.ps1` | Yes, after drafting a solution README. It writes only local files. |
| `tools\New-Solution.ps1` | Yes, to scaffold a draft. Leave it uncommitted. |
| `tools\Get-SiteProfile.ps1`, `tools\Generate-SchemaDocs.ps1` | Only if the maintainer asks. They rewrite tracked docs. |
| `tools\Invoke-DeleteListRun.ps1`, `tools\Invoke-KillBib.ps1`, `KillBib.exe` | **Never.** Prepare the command; the cataloger runs it. |
| `tools\Test-DeleteListPreflight.ps1` | No. It authenticates with the KillBib SQL login, which is the cataloger's to type. |
