# Notice

## What this is, and who made it

The Horizon DBA Toolkit is an **independent, community-contributed** collection
of documentation, T-SQL and PowerShell for working safely with a SirsiDynix
Horizon database. It was written at the library of Brigham Young
University-Idaho out of ordinary day-to-day cataloguing and data-integrity work,
and is published so other Horizon sites do not have to rediscover the same
things.

**It is not a SirsiDynix product.** It is not produced, endorsed, supported or
reviewed by SirsiDynix, and nothing here should be read as vendor guidance. If
you need supported help with Horizon, contact SirsiDynix.

## Trademarks

*SirsiDynix*, *Horizon* and *Symphony* are trademarks of SirsiDynix. They are
used here only to identify the software this toolkit is written for, which is
nominative use; no affiliation, sponsorship or endorsement is claimed or implied.
*Microsoft*, *SQL Server* and *Windows PowerShell* are trademarks of Microsoft
Corporation. All other marks belong to their respective owners.

The `killbib` utility documented in [`docs/killbib.md`](docs/killbib.md) is
SirsiDynix's, shipped with Horizon. **No vendor code is redistributed here** —
that document records observed behaviour of the binary already installed at your
site, including behaviour its `/?` output does not mention.

## Redistribution

Licensed under the MIT License; see [`LICENSE`](LICENSE). That permits anyone —
SirsiDynix included — to copy, modify, redistribute and bundle this material,
commercially or otherwise, provided the copyright notice and licence text travel
with it. No separate permission is needed and none needs to be sought.

Please link to the canonical repository rather than distributing a snapshot, so
sites receive corrections. If you fork it and change it, say so, and do not
present the result as the original.

## Warranty — read this part

There is none. From the MIT text, in plain words:

> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

That is a legal disclaimer, and it is also an operational one. This toolkit
includes scripts that **permanently delete bibliographic records** and scripts
that **drop tables**. They are wrapped in pre-flight checks, count gates, typed
confirmations and audit files precisely because the underlying operations are
irreversible, but no amount of wrapping makes them safe by themselves.

Every destructive step in this repository assumes you will:

- take a backup you have actually tested restoring,
- run the audit query first and record its row count,
- and confirm the count before committing.

Those are not formalities. They are the whole safety model. **The person who
runs the script owns the outcome.**

## Contributing back

Corrections, additional solutions and — especially — findings from a Horizon
version or configuration different from the one this was written against are
welcome. Where you are contradicting something written here, say which database
version and compatibility level you observed it on: much of what looks like a
Horizon universal turns out to be one site's local truth, which is the whole
reason [`site-profile.md`](docs/schema/site-profile.md) is generated rather than
written.

Never include real server names, logins, location codes, staff usernames or
patron data in a contribution. See the placeholder table in
[`CLAUDE.md`](CLAUDE.md#never-publish-real-site-identifiers).
