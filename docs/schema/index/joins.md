# Declared foreign keys (generated)

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

The foreign keys your database actually **enforces** — far fewer than the relationships that exist. `bib` to `item`, among many others, is undeclared.
Read this as a record of what is enforced, never as a map of how the data relates. An absent FK is not evidence that two tables are unrelated.

---

Never hand-edit this file. Re-run the generator instead.
