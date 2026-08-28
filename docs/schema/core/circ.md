# `circ` — current checkouts

> **Reference-site export.** This page describes Horizon's design and was
> captured from one library's database. The column *names* and the *grain* are
> Horizon's and travel; the column *count* and any local additions are not.
> Confirm against your own [`horizon-schema/`](../../../horizon-schema/) export
> before relying on a name — see [AGENTS.md](../AGENTS.md#rule-1--never-guess-a-name).

**Grain: `borrower#, item#` — a real declared `PRIMARY KEY`.** 10 columns.

`circ` and `item_circ_renewal` are, in a typical Horizon database, the only
tables carrying genuine primary key constraints — very nearly the whole schema's
declared PK columns between them. They are modelled to a different standard than
everything around them. Your own declared-PK list is in
[`site-profile.md`](../site-profile.md#keys--and-the-pk_-trap).

| Ord | Column | Type | Notes |
| --- | --- | --- | --- |
| 1 | `circ#` | `numeric(9)` | Transaction number |
| 2 | `borrower#` | `int` | **PK part 1** → [`borrower.md`](borrower.md) |
| 3 | `proxy_borrower#` | `int` | Borrowed on another's behalf |
| 4 | `item#` | `int` | **PK part 2** → [`item.md`](item.md) |
| 5 | `ill_request#` | `varchar(20)` | Interlibrary loan |
| 6 | `latest_due_date` | `smallint` | Horizon day count |
| 7 | `cko_user_id` | `name_string` | Operator who checked out |
| 9 | `rental_amount` | `int` | |

## This table is *current* loans only

`circ` holds what is checked out **right now**. Returned items leave it. History
lives elsewhere:

- `circ_longterm_history` (31 columns)
- `temp_circ_longterm_history` — a local scratch copy, **not** authoritative
- `item_circ_renewal` — grain `borrower#, item#, renewal#`, so it **fans out**
  per renewal

A question like "how many times was this borrowed" cannot be answered from
`circ`. Asking it of `circ` returns 0 or 1 and looks like a valid answer.

## Joining

Because the grain is `(borrower#, item#)`, joining `circ` to `item` on `item#`
alone is safe — an item can be out to at most one borrower at a time. Joining to
`borrower` on `borrower#` fans out across that patron's loans, which is usually
what you want for a patron report.

Note `borrower#` also appears on `item` (ord 24) as a denormalised copy of the
current borrower. Two sources for the same fact; prefer `circ` and be explicit
about which you used.

## Personal data

Joining `circ` to `borrower` produces **circulation records tied to named
patrons** — among the most sensitive data in the system. The handling rules in
[`borrower.md`](borrower.md) apply with full force. Never commit output.
