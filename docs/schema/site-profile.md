# Site profile — NOT YET GENERATED

**This is a placeholder. It contains no facts about your database.**

Everything the rest of this repository says about *your* Horizon installation is
supposed to be on this page, measured rather than assumed. Until you generate it,
those links land here.

```powershell
powershell -ExecutionPolicy Bypass -File tools\Get-SiteProfile.ps1 `
    -Server ILSSERVER -Database ILSDB
```

Read-only. It overwrites this file. Takes under a minute.

---

## What it will tell you

| Section | Why you need it |
| --- | --- |
| **Epoch** | what date your integer date columns count from — see below |
| Engine | SQL Server version, **compatibility level**, collation, recovery model |
| Engine features | which T-SQL functions actually work here, probed by running them |
| Size | tables, views, columns, foreign keys, objects with no unique index |
| Keys | the **declared** primary keys, beside the many indexes merely *named* like one |
| Integer date columns | how many, across how many objects, and their paired `_time` columns |
| User-defined types | the UDT catalogue with use counts |
| Object creation clusters | which tables arrived with an install, and which are local |

## Why the epoch section is the one that matters

Horizon stores dates as `smallint` day counts from a fixed anchor. **Every
example in this repository assumes `1970-01-01`**, because that is what the site
this was written at measured. It is not a guarantee about yours.

If your anchor differs by even one day, every dated query you write here selects
the wrong day's records. Nothing errors. Nothing looks odd. The count comes back
looking perfectly reasonable.

The obvious check — `MAX(create_date)` decodes to about today — **cannot detect
this**, because "newest record is today" and "newest record is yesterday" are
both entirely normal. So the profiler uses the weekend instead: cataloguing stops
on Saturday and Sunday, and only the correct anchor puts the quiet days there. It
scores every candidate from −3 to +3 days and reports whether the winner is
unambiguous.

Until that check has run and said `VERIFIED`, treat every date predicate in this
repository as unverified.

---

## Then commit it

The generated page records **no** server, database, login or location name — only
measurements — so it is safe to commit even in a public fork. Committing it is
what makes the rest of the documentation true for your site rather than someone
else's.

Full setup sequence: [SETUP.md](../../SETUP.md).
