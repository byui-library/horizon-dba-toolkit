# Integer date columns (generated)

> **NOT YET GENERATED — this is a placeholder.**
>
> This page is built from your own schema exports. Run:
>
> ```powershell
> powershell -ExecutionPolicy Bypass -File tools\Generate-SchemaDocs.ps1
> ```
>
> It needs the CSVs in [`horizon-schema/`](../../../horizon-schema/README.md)
> first — see [SETUP.md](../../../SETUP.md) steps 2 and 3. The generator
> overwrites this file.

## What it will contain

Every `smallint` column whose name marks it as a date, with its paired `_time` column where one exists. These hold a **day count**, not a SQL `date`.
The anchor they count from is site-specific — see [site-profile.md](../site-profile.md#epoch).

---

Never hand-edit this file. Re-run the generator instead.
