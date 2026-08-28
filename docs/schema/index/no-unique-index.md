# Objects with no unique index (generated)

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

Objects that have **no stated grain**: nothing constrains them to one row per key.
Treat every join to one of these as a fan-out risk, and collapse it with `EXISTS`, `DISTINCT` or aggregation unless you genuinely want the extra rows.

---

Never hand-edit this file. Re-run the generator instead.
