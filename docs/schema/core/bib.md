# `bib` — MARC record content

> **Reference-site export.** This page describes Horizon's design and was
> captured from one library's database. The column *names* and the *grain* are
> Horizon's and travel; the column *count* and any local additions are not.
> Confirm against your own [`horizon-schema/`](../../../horizon-schema/) export
> before relying on a name — see [AGENTS.md](../AGENTS.md#rule-1--never-guess-a-name).

**Grain: `bib#, tag, tagord` — one row per MARC tag occurrence.**
12 columns. This is the most-queried table in the repository and the source of
its signature hazard.

A bibliographic record is not a row here. It is a *set* of rows — one per MARC
field, and more than one per field when the field is long.

## Columns

| Ord | Column | Type | Notes |
| --- | --- | --- | --- |
| 1 | `bib#` | `int` | Record number. Not unique in this table. |
| 4 | `indicators` | `char(2)` | MARC indicators |
| 5 | `text` | `varchar(255)` | Subfield content — **control-character encoded** |
| 6 | `cat_link_xref#` | `int` | Authority/link cross-reference |
| 9 | `link_type` | `tinyint` | |
| 10 | `tag` | `tag_type` → `varchar(5)` | MARC tag: `'245'`, `'590'`, `'049'` |
| 11 | `tagord` | `tagord_type` → `int` | Ordinal among repeated tags |
| 12 | `cat_link_type#` | `key#` → `int` | |

Columns 2, 3, and 8 are named `unused_smallint`, `unused_ord_type`, and
`unused_int`. They are exactly what they say — do not read meaning into them.

## The fan-out

`bib` has many rows per `bib#`, and so does `item`. Nothing links a specific tag
row to a specific item row, because no such relationship exists — they are
independent children of the same record.

> A bib with **2** `590` tags and **3** items yields **6 rows** from
> `bib JOIN item`. The count is not a bug in the join; it is what the join means.

Collapse the tag side whenever you want one row per record:

```sql
-- Test a condition on the record without multiplying it
WHERE EXISTS (SELECT 1 FROM bib b
              WHERE b.[bib#] = x.[bib#] AND b.tag = '590'
                AND b.text LIKE '%ProQuest%')
```

Use a plain `JOIN` only when the fan-out is the point — a detail report showing
one row per tag.

## `text` is control-character encoded

Subfields are separated by `CHAR(31)`; `CHAR(30)` terminates the field. `$a` is
`CHAR(31)+'a'`. There are no literal pipes in the stored data.

```sql
-- Writing a value
SET text = CHAR(31)+'a'+@value+CHAR(30)

-- Displaying one in audit output only
SELECT '|a' + <parsed value> AS [readable]
```

Because `text` is `varchar(255)`, **a longer field is not stored here.** Its row
keeps `tag` and `tagord`, `text` is **NULL**, and the whole field is in
`bib_longtext.longtext`, keyed uniquely by `bib#, tag, tagord`. Read field text
as:

```sql
SELECT COALESCE(b.text, CAST(l.longtext AS varchar(8000))) AS field_text
FROM bib b
LEFT JOIN bib_longtext l
       ON l.[bib#] = b.[bib#] AND l.tag = b.tag AND l.tagord = b.tagord
```

A `LIKE` on `b.text` alone silently misses every long field; see
[AGENTS.md Rule 8](../AGENTS.md#rule-8--marc-text-is-not-plain-text) for the
check to run before trusting a filter.

> **Corrected 2026-11-25.** This page said long fields were split across several
> `bib` rows with consecutive `tagord`s. A live database showed otherwise: the
> field moves wholesale to `bib_longtext`.

When you aggregate several tags into one cell, note that `FOR XML PATH`
**entitizes** the `CHAR(31)`/`CHAR(30)` delimiters as `&#x1F;`/`&#x1E;` rather
than preserving them, and `STRING_AGG` is unavailable at low compatibility
levels. Replace the delimiters before aggregating, or ship a detail query with
one row per tag.

## Targeting one of several same-`tag` rows

Isolate by `tagord`:

```sql
-- The later of two duplicate tags, preserving the first
AND b.tagord = (SELECT MAX(tagord) FROM bib
                WHERE [bib#] = b.[bib#] AND tag = '049')
```

For "this record has exactly N identical tags", the established idiom is:

```sql
HAVING COUNT(*) = 2 AND MIN(text) = MAX(text)
```

## Extracting `245$a`

The title parser reused across this repo's reports locates the `$a` delimiter,
takes text up to the next `CHAR(31)`/`CHAR(30)` or end of string, then strips one
trailing ISBD punctuation mark (`/ : ; , = .`). Run it on
`COALESCE(text, longtext)` as above, or a long `245` comes back NULL.

Always attach it with `OUTER APPLY`, never `CROSS APPLY` — a record whose `245$a`
cannot be parsed must still appear in the report rather than silently vanishing.
See `590-proquest-purchase-removal-report/README.md` for the full expression.

## Case sensitivity when matching `text`

`text` is `SQL_Latin1_General_CP850_CI_AS` — case-insensitive. Usually right:
`%ProQuest%` should match `PROQUEST` and `Proquest`.

But short uppercase acronyms need care. A case-insensitive `%DDA%` also matches
the `dDa` sequence produced where a `$d` subfield code abuts content beginning
`Da…`, generating false positives. Add `COLLATE Latin1_General_CS_AS` for those:

```sql
AND b.text COLLATE Latin1_General_CS_AS LIKE '%DDA%'
```

Long distinctive literals like `ProQuest` cannot be forged at a code/content
boundary and need no guard.

## Related

- [`bib_control.md`](bib_control.md) — one row per `bib#`; creation metadata
- [`title.md`](title.md) — one row per `bib#`; normalised title text
- [`item.md`](item.md) — copies; the other half of the Cartesian product
