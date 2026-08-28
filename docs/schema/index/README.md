# Generated index pages

**Empty until you generate them.** These pages are built from your own schema
exports, not shipped with someone else's.

```powershell
powershell -ExecutionPolicy Bypass -File tools\Generate-SchemaDocs.ps1
```

Reads the CSVs in [`horizon-schema/`](../../../horizon-schema/README.md) and
writes four pages here:

| Page | What it answers |
| --- | --- |
| `all-objects.md` | what exists, and the **grain** of each object |
| `no-unique-index.md` | which objects have no stated grain — every join to one is a fan-out risk |
| `date-columns.md` | every integer date column, with its paired `_time` column where one exists |
| `joins.md` | the declared foreign keys — what is actually *enforced*, which is far less than what relates |

Links to these pages from `AGENTS.md`, `conventions.md` and the solution READMEs
will not resolve until you have run the generator. That is expected on a fresh
clone; work through [SETUP.md](../../../SETUP.md).

**Never hand-edit anything in this directory.** Re-run the generator instead —
it overwrites. Hand-written pages (`AGENTS.md`, `conventions.md`, `core/*.md`)
and `site-profile.md` are outside its reach and are never touched.
