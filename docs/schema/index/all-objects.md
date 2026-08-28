# All objects (generated)

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

Every table and view in your database, with its type, column count and — the reason this page exists — its **grain**: the column set that is provably one row.
Check both sides here before writing any join. Getting a grain wrong silently multiplies your result set rather than failing.

---

Never hand-edit this file. Re-run the generator instead.
