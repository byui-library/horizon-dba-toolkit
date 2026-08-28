# Raw schema exports

**This directory is empty until you fill it.** That is deliberate.

These CSVs are the source of truth for every table and column name used in this
repository — and they must describe *your* Horizon database, not somebody else's.
Object counts, local customisations, add-on modules and version drift all differ
between sites, so a schema shipped from elsewhere would be a plausible-looking
set of names that might not exist in your database. That is precisely the failure
mode [`AGENTS.md`](../docs/schema/AGENTS.md#rule-1--never-guess-a-name) exists to
prevent.

## Filling it

The four export queries are in [`docs/schema/README.md`](../docs/schema/README.md#building-the-exports).
Run each, save the result here, then regenerate the derived pages. The whole
sequence is in [SETUP.md](../SETUP.md).

| File | Contents |
| --- | --- |
| `all_tables_all_views.csv` | Every column of every table and view |
| `indexes_and_keys.csv` | Every index, its columns, uniqueness |
| `foreign_keys.csv` | Every declared foreign key column |
| `table_origin_and_rowcounts.csv` | Table creation dates and row counts (optional; used by the scratch-table cleanup) |

## No header row

Save from SSMS with **Results to Grid** → right-click → **Save Results As…** →
CSV, which omits headers. Field order is fixed by the export query:

`all_tables_all_views.csv`:

```
1 schema        2 object      3 object_type   4 ord        5 column
6 declared_type 7 base_type   8 len_bytes     9 prec      10 scale
11 nullable    12 is_identity 13 is_computed 14 collation 15 pk
16 pk_ord      17 default_definition
```

`indexes_and_keys.csv`:

```
1 schema  2 object  3 index_name  4 index_type  5 is_pk
6 is_unique  7 key_ord  8 column  9 direction  10 part
```

`foreign_keys.csv`:

```
1 fk_name  2 parent_schema  3 parent_table  4 parent_column
5 referenced_schema  6 referenced_table  7 referenced_column
8 col_ord  9 on_delete  10 on_update  11 disabled
```

SSMS writes these with a UTF-8 BOM. `Import-Csv` and `grep` both handle it;
strip it with `sed '1s/^\xEF\xBB\xBF//'` if a tool chokes.

## Reading them

Lookup recipes are in [`docs/schema/AGENTS.md`](../docs/schema/AGENTS.md#rule-2--look-it-up-like-this).
The short version:

```bash
grep -E '^dbo,bib_control,' "horizon-schema/all_tables_all_views.csv"
```

## Refreshing

After overwriting these files, regenerate the derived pages:

```powershell
powershell -ExecutionPolicy Bypass -File tools\Generate-SchemaDocs.ps1
```

Re-run the export after a Horizon upgrade, after adding or dropping tables, and
after the [scratch-table cleanup](../solutions/db-scratch-table-cleanup/README.md).

## Committing them

`.gitignore` blocks `*.csv` to keep catalogue and patron data out of the
repository, with a narrow `!horizon-schema/*.csv` exception for these files.
They are schema **metadata**: names, types, collations, index and FK
definitions. No catalogue records, no patron data, no credentials.

**Do not add exceptions for query output.** Results from `borrower`, `circ`, or
any patron-bearing table must never be committed.

One thing to check before pushing a fork publicly: the export names every table
in your database, including local scratch tables. If any of those carry a staff
member's name, **rename the table** rather than editing the export — a doctored
export silently disagrees with the database, which is the exact class of error
this repository guards against.
