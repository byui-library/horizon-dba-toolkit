# Horizon schema conventions

Background reference for the patterns that repeat across a Horizon database. The
enforceable rules are in [AGENTS.md](AGENTS.md); this page explains *why* they
are what they are, and holds the verification procedures.

> **Universals only.** Everything here is a pattern of Horizon's design, not a
> measurement of any one installation. Every number specific to *your* database
> lives in [`site-profile.md`](site-profile.md), written by
> `tools/Get-SiteProfile.ps1`. Where the two touch on the same subject, the
> profile wins.

---

## Dates

### The convention

A Horizon date column is a **`smallint` day count**, not a SQL `date`. Time of
day, where kept at all, is a **separate paired `_time` column**. This affects a
large fraction of the schema — typically several hundred columns across a few
hundred tables. Your exact figure is in
[`site-profile.md`](site-profile.md#integer-date-columns); the full inventory is
[`index/date-columns.md`](index/date-columns.md).

This is why the pattern matters so much: get the decoding wrong once and every
dated query is wrong by the same constant, which is the hardest kind of error to
spot. Nothing looks broken; the numbers are just quietly incorrect.

### Consequences for query writing

- **`=` on a single day is exact and complete.** There is no time component to
  fall outside a range, so no `>= / <` half-open pattern is needed.
- **`BETWEEN` is safe for ranges.** The usual "`BETWEEN` misses the last day's
  afternoon" bug cannot occur, because there is no afternoon in the column.
- **Never cast.** `CAST(create_date AS DATE)` is meaningless on an integer, and
  wrapping a column in a function prevents an index seek regardless.
- **`smallint` caps at 32,767**, so a 1970-anchored encoding runs out in 2059.

### The epoch — verify it, never assume it

Horizon's day count is anchored to a fixed date. The reference site for this
toolkit measured **`1970-01-01`**, and every example here is written against
that anchor. **Confirm it against your own database before running anything
dated.**

`tools/Get-SiteProfile.ps1` does this automatically and records the verdict and
the evidence in [`site-profile.md`](site-profile.md#epoch). The manual procedure
below is the same test, for when you want to see it yourself or the script
cannot reach `bib_control`.

Use **both** steps — step 1 alone is not proof.

**Step 1 — order-of-magnitude sanity check.**

```sql
SELECT MIN(create_date) AS [min_day],
       DATEADD(day, MIN(create_date), CAST('1970-01-01' AS DATE)) AS [min_decodes_to],
       MAX(create_date) AS [max_day],
       DATEADD(day, MAX(create_date), CAST('1970-01-01' AS DATE)) AS [max_decodes_to]
FROM bib_control;
```

| Result | Meaning |
| --- | --- |
| `max_decodes_to` on or near today | Consistent — but **not yet proof**. Go to step 2. |
| Off by weeks or more | Different anchor. Shift `'1970-01-01'` by the difference. |
| A 1970s or far-future date | Not a day count at all. Stop and re-derive the encoding. |

> This step **cannot detect a one-day error**. "Newest record is yesterday" and
> "newest record is today" are both ordinary, so a ±1 anchor passes it. That is
> precisely the error worth catching: it is invisible and it silently shifts
> every dated query by a day.

**Step 2 — the weekend fingerprint (decisive).**

```sql
SELECT bc.create_date AS [day_number],
       DATEADD(day, bc.create_date, CAST('1970-01-01' AS DATE)) AS [decodes_to],
       DATENAME(weekday,
                DATEADD(day, bc.create_date, CAST('1970-01-01' AS DATE))) AS [weekday],
       COUNT(*) AS [bibs_created]
FROM bib_control bc
WHERE bc.create_date >= DATEDIFF(day, '1970-01-01', DATEADD(day, -28, GETDATE()))
GROUP BY bc.create_date
ORDER BY bc.create_date;
```

Cataloguing stops at weekends, so Saturdays and Sundays should be absent or
near-zero while weekdays are populated. If activity lands on a weekend, or
Mondays come back empty, the anchor is off — shift it until the quiet days line
up with the weekends. A one-day error is obvious here and invisible in step 1.

Corroborate with a date you independently know, such as when a bulk load ran.

**Worked example.** At the reference site the check ran over a two-week window:

| Day number | Decodes to | Weekday | Bibs created |
| ---: | --- | --- | ---: |
| 20679 | 2026-08-14 | Friday | 1 |
| 20680, 20681 | 2026-08-15/16 | **Sat, Sun** | **absent** |
| 20682 | 2026-08-17 | Monday | 20 |
| 20683 | 2026-08-18 | Tuesday | 22 |
| 20685 | 2026-08-20 | Thursday | 13 |
| 20687, 20688 | 2026-08-22/23 | **Sat, Sun** | **absent** |
| 20689 | 2026-08-24 | Monday | 18 |
| 20690 | 2026-08-25 | Tuesday | 6,797 ← bulk load |
| 20691 | 2026-08-26 | Wednesday | 22 |

All four weekend days empty, every populated day a weekday. Under a one-day-later
anchor the same data would put **two Mondays at zero** and a Saturday at 1 — a
poor fit. The 6,797 on day 20690 was independently corroborated against a load
whose date was known.

Note what makes this decisive: it is not that the numbers look plausible, it is
that the *alternative* anchors look implausible. That comparison is what
`Get-SiteProfile.ps1` automates — it scores every candidate epoch from −3 to +3
days and reports whether the winner is unambiguous.

### Time columns

`create_time` and its siblings are `smallint` too, but **their encoding is not
verified anywhere in this toolkit** — minutes since midnight and an `hhmm`
integer are both plausible and both fit. Do not put a time column in a predicate
until it has been checked against a record whose creation time is independently
known.

---

## User-defined types

Horizon declares most columns through UDTs. The export records both the declared
type and the underlying base type; both matter. Declared type tells you the
column's *role*, base type tells you how it *behaves*.

Common ones, with the roles they signal:

| Declared type | Base type | Role |
| --- | --- | --- |
| `code_type` | `varchar(7)` | A short code that joins to a lookup table |
| `zero_bit` | `bit` | Flag, defaults to 0 |
| `null_string` | `varchar(80)` | General short text |
| `name_string` | `varchar(30)` | Operator logins, user and person names |
| `null_string_mlui` | `varchar(255)` | Longer text, multi-language UI |
| `enum_type` | `tinyint` | Small enumerated value |
| `zero_int` | `int` | Counter, defaults to 0 |
| `ord_type` | `tinyint` | Ordinal within a parent |
| `key#` | `int` | Surrogate key reference |
| `reconst_type` | `varchar(250)` | Reconstructed display string |
| `processed_type` | `varchar(250)` | Normalised/processed text for indexing |
| `zero_money` | `money` | Currency, defaults to 0 |
| `tag_type` | `varchar(5)` | MARC tag |
| `tagord_type` | `int` | Ordinal among repeated tags |

Your database's actual catalogue, with use counts and any local additions, is in
[`site-profile.md`](site-profile.md#user-defined-types).

**`code_type` is the strongest signal in the schema.** A `code_type` column
almost always joins to a same-named lookup table: `item.collection` →
`collection.collection`, `item.location` → `location.location`, `item.itype` →
`itype.itype`. That convention is how most of the database's relationships are
expressed, since they are not declared as foreign keys.

---

## Keys, grain, and the `PK_` trap

### Declared primary keys are almost absent

Horizon's schema is, for practical purposes, primary-key-free. A handful of
`PRIMARY KEY` constraints exist — typically on circulation tables — and that is
all. [`site-profile.md`](site-profile.md#keys--and-the-pk_-trap) lists yours in
full; it is a short list.

### The naming trap

Hundreds of indexes are **named** like primary keys — `PK_location`,
`PK_BIB_STATUS`, `PKborrower_barcode`, `PK_acq_parameter` — and **none of them
is one**. Every such index reports `is_primary_key = no`. They are unique
indexes with a misleading name, presumably a naming habit carried over from
whatever tool created them.

Two consequences:

1. **Grain comes from unique indexes**, not from primary keys. Any tool or query
   that looks for declared PKs to discover keys will find a handful and conclude
   the database is unkeyed. It is not — the information is in the indexes.
2. **Never infer a constraint from an index name.** Check `is_unique` in
   `indexes_and_keys.csv`, or read the grain column in
   [`index/all-objects.md`](index/all-objects.md), which already resolves this.

### Grain of the core tables

| Object | Grain | One row per |
| --- | --- | --- |
| `bib` | `bib#, tag, tagord` | MARC tag occurrence |
| `bib_control` | `bib#` | record |
| `title` | `bib#` | record |
| `item` | `item#` (also unique on `ibarcode`) | physical copy |
| `collection` | `collection` | collection code |
| `location` | `location` | location code |
| `borrower` | `borrower#` (also unique on `second_id`) | patron |
| `circ` | `borrower#, item#` | current checkout |

`bib` fanning out per tag while `item` fans out per copy — with no key relating a
specific tag to a specific copy — is the Cartesian product this entire repository
is built to guard against. Two `590`s and three items give six rows.

Confirm these against your own export rather than taking them on trust; local
customisation can add an index that changes a grain.

---

## Foreign keys are the exception, not the rule

A Horizon database declares very few foreign keys — a small number relative to
its table count ([`index/joins.md`](index/joins.md) lists yours). Most
relationships, including `bib` → `item`, are undeclared and held together by
convention alone.

Treat the FK list as a reliable record of what *is* enforced, never as a map of
how the data relates. An absent FK is not evidence that two tables are unrelated.

The FKs that do exist can still bite: a `killbib` batch delete at the reference
site failed on `FK_stat_data_location` because an item carried a `location` code
missing from the `location` parent table. See
[`docs/killbib.md`](../killbib.md).

---

## MARC storage in `bib.text`

`bib.text` is `varchar(255)` and holds MARC subfields separated by **control
characters**, not literal pipes:

- `CHAR(31)` — subfield delimiter, so `$a` is `CHAR(31)+'a'`
- `CHAR(30)` — field terminator

Write values as `CHAR(31)+'a'+@value+CHAR(30)`. A readable `'|a'+value` column is
for **display in audit output only** — never for the value actually stored.

Two practical consequences of the 255-character limit and the control characters:

1. **Long fields split across rows.** Horizon continues a long `245`, `520`, or
   `590` into additional rows with an incremented `tagord`. Reassembly means
   ordering by `tagord`; the `245$a` parser used across this repo deliberately
   takes only the lowest-`tagord` segment, which truncates the rare long title.
2. **`FOR XML PATH` fails on this column.** `CHAR(31)`/`CHAR(30)` are illegal in
   XML, so the usual pre-2017 string-aggregation workaround throws. Where
   `STRING_AGG` is also unavailable, the practical answer is to ship a separate
   detail query with one row per tag.

---

## Engine limitations

Horizon databases commonly sit at a low compatibility level, which gates T-SQL
features independently of the SQL Server build installed. Functions worth
checking before you rely on them:

| Feature | Typical status on an older Horizon database |
| --- | --- |
| `STRING_AGG` | Often unavailable — *"not a recognized built-in function name"* |
| `STRING_AGG ... WITHIN GROUP` | Rejected even where the function exists |
| `FOR XML PATH` on `bib.text` | Throws — illegal XML characters |
| `CONCAT`, `IIF`, `FORMAT`, `OFFSET/FETCH` | Assume unavailable unless proven |

**Your engine is probed, not guessed:** each of these is executed against your
database by `Get-SiteProfile.ps1` and tabulated in
[`site-profile.md`](site-profile.md#engine-features).

Write to the lowest common denominator regardless: `CASE` instead of `IIF`, `+`
instead of `CONCAT`, `TOP` instead of `OFFSET/FETCH`. A query written that way
travels to any other Horizon site unchanged. The `sys` catalog views used by the
schema exports are SQL Server 2005+ and are unaffected by compatibility level.

---

## Local tables mixed in with Horizon's

Not every table in the database is Horizon's. Scratch copies, pre-change backups
and one-off working sets accumulate alongside the vendor schema, and they can
hold arbitrarily stale data. A `*_bak` table is not the table it was copied from.

**Names are suggestive, not authoritative — in both directions.** `tmp`, `del`,
`temp` and `bak` prefixes also appear on tables Horizon itself ships, so a
name-based rule would eventually delete a vendor table. Equally, a vendor table
that was rebuilt at some point looks locally-created by its `create_date`.

No list of them is maintained here: it would be one site's list, stale the day
after any cleanup. Derive it live instead —
[`solutions/db-scratch-table-cleanup`](../../solutions/db-scratch-table-cleanup/README.md)
classifies by creation-time clustering plus structural signals (column count,
declared PK, user-defined-type columns), which is what actually separates the
two.

The reference site's run of that solution dropped 42 tables and, on the way,
nearly dropped a vendor lookup table that had been rebuilt during an upgrade.
That near-miss is why the solution reports structural evidence beside every
candidate instead of a bare name list.
