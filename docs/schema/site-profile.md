# Site profile (generated)

Measured **2026-10-19** by `tools/Get-SiteProfile.ps1` against this site's live
Horizon database. **Do not hand-edit** - re-run the script instead.

Everything on this page varies between Horizon sites. The rest of the
documentation states only what is true of Horizon everywhere and links here for
the numbers. If a figure below disagrees with something written in prose
elsewhere in this repository, **this page wins** - it was measured; the prose
was written.

No server, database, login or location name is recorded here.

---

## Engine

| Property | Value |
| --- | --- |
| SQL Server version | `12.0.6449.1` SP3 |
| Edition | Standard Edition (64-bit) |
| Database compatibility level | **120** |
| Collation | `SQL_Latin1_General_CP850_CI_AS` |
| Recovery model | **FULL** |
| Read-committed snapshot | yes |

The collation is **case-insensitive** (`_CI_`), so `=` and `LIKE` ignore case.
Usually what you want - but a short uppercase acronym such as `DDA` will also
match lowercase text that happens to contain the letters. Add
`COLLATE Latin1_General_CS_AS` where exact case matters.

Recovery model is `FULL`, so `SELECT ... INTO` is **fully logged** and gets no
minimal-logging benefit. Size the transaction log for the row count before
building a large working table.

## Engine features

Probed by running each one. Write to what is available *here*, not to what the
SQL Server version alone suggests - compatibility level gates most of it.

| Feature | Available | If not, the error was |
| --- | --- | --- |
| `STRING_AGG` | no | Exception calling "ExecuteScalar" with "0" argument(s): "'STRING_AGG' is not a recognized built-in function... |
| `STRING_AGG WITHIN GROUP` | no | Exception calling "ExecuteScalar" with "0" argument(s): "The function 'STRING_AGG' may not have a WITHIN GR... |
| `CONCAT` | yes |  |
| `IIF` | yes |  |
| `FORMAT` | yes |  |
| `TRY_CONVERT` | yes |  |
| `OFFSET / FETCH` | yes |  |
| `FOR XML PATH with MARC control chars` | yes |  |

**Unavailable here: STRING_AGG, STRING_AGG WITHIN GROUP.**

Use `CASE` for `IIF`, `+` for `CONCAT`, `TOP` for `OFFSET/FETCH`, and ship a
second detail query (one row per tag) instead of aggregating note text into
one cell.

## Size

| Measure | Count |
| --- | ---: |
| Tables | 931 |
| Views | 433 |
| Columns (tables and views) | 13953 |
| Declared foreign keys | 139 (166 columns) |
| Tables with no unique index | 242 |

A table with no unique index has **no stated grain**: nothing constrains it to
one row per key, so treat every join to it as a fan-out risk.

## Keys - and the `PK_` trap

| Measure | Count |
| --- | ---: |
| **Declared** primary key constraints (columns) | **5** |
| Indexes *named* like a primary key | 164 |
| ...of those, **not** actually primary keys | **162** |
| Unique indexes | 753 |

**162 indexes here are named `PK...` and are not primary keys.**
Never infer a constraint from an index name; check `is_unique` in
`indexes_and_keys.csv`. Grain at this site comes from **unique indexes**.

The declared primary keys, in full:

| Table | Constraint | Column | Ord |
| --- | --- | --- | ---: |
| `circ` | `PK_circ` | `borrower#` | 1 |
| `circ` | `PK_circ` | `item#` | 2 |
| `item_circ_renewal` | `PK_item_circ_renewal` | `borrower#` | 1 |
| `item_circ_renewal` | `PK_item_circ_renewal` | `item#` | 2 |
| `item_circ_renewal` | `PK_item_circ_renewal` | `renewal#` | 3 |

## Integer date columns

**941 `smallint` date columns across 294 objects**, with **225** paired
`_time` columns. These hold a **day count**, not a SQL `date`.

### Epoch

> **Epoch: `1970-01-01` - VERIFIED 2026-10-19.**
>
> Verified. Under 1970-01-01, 0 of 6616 records (0%) land on a weekend; every other candidate epoch from -3 to +3 days scores worse.

Write date predicates against that anchor, which is what every example in this
repository assumes:

```sql
WHERE bc.create_date = DATEDIFF(day, '1970-01-01', '2026-08-25')
```

<details>
<summary>Evidence: bib records created per day, last 28 days</summary>

| Day number | Decodes to (1970-01-01) | Weekday | Bibs created |
| ---: | --- | --- | ---: |
| 20717 | 2026-09-21 | Monday | 5 |
| 20718 | 2026-09-22 | Tuesday | 9 |
| 20719 | 2026-09-23 | Wednesday | 15 |
| 20720 | 2026-09-24 | Thursday | 16 |
| 20724 | 2026-09-28 | Monday | 8 |
| 20725 | 2026-09-29 | Tuesday | 4 |
| 20726 | 2026-09-30 | Wednesday | 3193 |
| 20728 | 2026-10-02 | Friday | 1968 |
| 20731 | 2026-10-05 | Monday | 21 |
| 20732 | 2026-10-06 | Tuesday | 10 |
| 20735 | 2026-10-09 | Friday | 1334 |
| 20738 | 2026-10-12 | Monday | 12 |
| 20739 | 2026-10-13 | Tuesday | 12 |
| 20740 | 2026-10-14 | Wednesday | 2 |
| 20741 | 2026-10-15 | Thursday | 5 |
| 20745 | 2026-10-19 | Monday | 2 |

Days with no cataloguing are absent rather than zero. The epoch is right when
the bold weekend rows are the ones missing.

</details>

### Time columns

The paired `_time` columns are `smallint` too, but **their encoding is not probed
here** - minutes-since-midnight and an `hhmm` integer both fit the data. Check
one against a record whose creation time you know before putting a time column
in a predicate.

## User-defined types

Horizon declares most columns through UDTs. The declared type tells you the
column's *role*; the base type tells you how it *behaves*. Top 20 by use:

| Declared type | Base type | Bytes | Uses |
| --- | --- | ---: | ---: |
| `code_type` | `varchar` | 7 | 1818 |
| `zero_bit` | `bit` | 1 | 916 |
| `null_string` | `varchar` | 80 | 657 |
| `name_string` | `varchar` | 30 | 483 |
| `null_string_mlui` | `varchar` | 255 | 450 |
| `enum_type` | `tinyint` | 1 | 367 |
| `zero_int` | `int` | 4 | 268 |
| `ord_type` | `tinyint` | 1 | 156 |
| `key#` | `int` | 4 | 92 |
| `reconst_type` | `varchar` | 250 | 80 |
| `processed_type` | `varchar` | 250 | 75 |
| `zero_money` | `money` | 8 | 54 |
| `zero_smallint` | `smallint` | 2 | 31 |
| `long_string` | `varchar` | 255 | 28 |
| `tag_type` | `varchar` | 5 | 28 |
| `tagord_type` | `int` | 4 | 21 |
| `name_string_mlui` | `varchar` | 100 | 19 |
| `entry_code` | `varchar` | 30 | 9 |
| `ord_type_255` | `tinyint` | 1 | 6 |
| `one_bit` | `bit` | 1 | 6 |

`code_type` is the strongest signal in the schema: such a column almost always
joins to a same-named lookup table (`item.collection` to `collection.collection`).

## Object creation clusters

Tables sharing a `create_date` were created together - an install or an upgrade.
Tables created alone, later, are usually local additions. The scratch-table
cleanup uses this; the largest cluster is normally the Horizon install itself.

| Created on | Tables |
| --- | ---: |
| 2022-04-11 | 924 |
| 2024-07-29 | 4 |
| 2026-10-17 | 1 |
| 2026-09-08 | 1 |
| 2026-08-31 | 1 |

A late `create_date` does **not** prove a table is local: rebuilding a vendor
table during an upgrade resets it. Judge on structure as well.

---

## Re-run this after

- a Horizon upgrade, or any change to the database compatibility level
- restoring a backup, especially one taken at another site
- a collation or recovery-model change
- the scratch-table cleanup, which changes the object counts

```powershell
powershell -ExecutionPolicy Bypass -File tools\Get-SiteProfile.ps1 -Server ILSSERVER -Database ILSDB
```
