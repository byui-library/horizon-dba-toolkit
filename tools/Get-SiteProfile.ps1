<#
.SYNOPSIS
    Measures the facts about YOUR Horizon database that vary between sites, and
    writes docs/schema/site-profile.md.

.DESCRIPTION
    This toolkit's prose states the things that are true of Horizon everywhere:
    bib fans out per MARC tag, indexes named PK_* are usually not primary keys,
    bib.text uses CHAR(31)/CHAR(30). Those are safe to assert.

    Everything else varies by site, version, upgrade history and local practice:
    how many objects exist, how many primary keys were actually declared, which
    T-SQL functions your compatibility level allows, what collation you run,
    and - most dangerous of all - what date the integer date columns count from.

    Rather than print another site's numbers and hope they transfer, this script
    measures yours and writes them to a page the rest of the docs link to.

    READ-ONLY. Every query reads sys catalog views or COUNTs bib_control. It
    creates nothing, changes nothing, and takes no locks beyond a shared read.

    NO SITE IDENTIFIERS ARE WRITTEN. The output records measurements only - no
    server, database, login or location - so the page is safe to commit even if
    you publish your fork.

.PARAMETER Server
    SQL Server instance hosting the Horizon database.

.PARAMETER Database
    The Horizon database name.

.PARAMETER Credential
    SQL login with read access. Prompted for if omitted.

.PARAMETER OutFile
    Where to write the profile. Defaults to docs/schema/site-profile.md.

.PARAMETER EpochProbeDays
    How far back to sample bib_control for the epoch check. The default of 28
    spans four weekends, which is what makes the test decisive. Raise it if
    cataloguing at your site is sporadic.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\Get-SiteProfile.ps1 -Server ILSSERVER -Database ILSDB

.NOTES
    Re-run after a Horizon upgrade, a compatibility-level change, or a restore
    from another site's backup. All three can invalidate the page.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage='SQL Server instance, e.g. ILSSERVER')]
    [string] $Server,

    [Parameter(Mandatory=$true, HelpMessage='Horizon database name, e.g. ILSDB')]
    [string] $Database,

    [Parameter(Mandatory=$false)]
    [System.Management.Automation.PSCredential] $Credential,

    [string] $OutFile,

    [ValidateRange(7, 400)]
    [int] $EpochProbeDays = 28
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'HorizonSql.ps1')

if (-not $Credential) {
    $Credential = Get-Credential -Message "SQL login with read access to $Database"
}
if (-not $OutFile) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $OutFile  = Join-Path $repoRoot 'docs\schema\site-profile.md'
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-Scalar {
    param($Conn, [string] $Sql, [int] $Timeout = 120)
    $dt = Invoke-HorizonTable -Connection $Conn -Sql $Sql -Timeout $Timeout
    if ($dt.Rows.Count -eq 0) { return $null }
    return $dt.Rows[0][0]
}

function Test-Feature {
    <#
        Probes one T-SQL feature by running it. A feature absent at this
        compatibility level raises a parse or bind error, which is the only
        reliable signal - the catalog views that would answer the question
        directly are themselves version-gated, so probing with them just moves
        the problem one level down.
    #>
    param($Conn, [string] $Name, [string] $Sql)
    try {
        $cmd = New-HorizonCommand -Connection $Conn -Sql $Sql -Timeout 30
        [void] $cmd.ExecuteScalar()
        return [pscustomobject]@{ Feature = $Name; Available = $true; Detail = '' }
    } catch {
        # First line only: the full SqlException carries a stack trace that
        # would swamp the table and adds nothing.
        $msg = ($_.Exception.Message -split "`r?`n")[0].Trim()
        return [pscustomobject]@{ Feature = $Name; Available = $false; Detail = $msg }
    }
}

function Format-Bool { param([bool] $b) if ($b) { 'yes' } else { 'no' } }

function Get-FirstLine {
    param($ErrorRecord)
    return ($ErrorRecord.Exception.Message -split "`r?`n")[0].Trim()
}

$EPOCH = Get-Date '1970-01-01'

# ---------------------------------------------------------------------------
# Measure
# ---------------------------------------------------------------------------

Write-Host "Connecting to $Database ..." -ForegroundColor Cyan
$conn = New-HorizonConnection -Server $Server -Database $Database -Credential $Credential -AppName 'HorizonTools:SiteProfile'

try {
    Write-Host "  engine and settings" -ForegroundColor Gray
    $engineSql = @'
SELECT
    CAST(SERVERPROPERTY('ProductVersion') AS varchar(64))  AS [product_version],
    CAST(SERVERPROPERTY('ProductLevel')   AS varchar(64))  AS [product_level],
    CAST(SERVERPROPERTY('Edition')        AS varchar(128)) AS [edition],
    d.compatibility_level                                  AS [compat_level],
    d.collation_name                                       AS [collation],
    d.recovery_model_desc                                  AS [recovery_model],
    d.is_read_committed_snapshot_on                        AS [rcsi]
FROM sys.databases d
WHERE d.database_id = DB_ID();
'@
    $e = (Invoke-HorizonTable -Connection $conn -Sql $engineSql).Rows[0]

    Write-Host "  object counts" -ForegroundColor Gray
    $countsSql = @'
SELECT
    SUM(CASE WHEN o.type = 'U' THEN 1 ELSE 0 END) AS [tables],
    SUM(CASE WHEN o.type = 'V' THEN 1 ELSE 0 END) AS [views]
FROM sys.objects o
WHERE o.type IN ('U','V') AND o.is_ms_shipped = 0;
'@
    $counts = (Invoke-HorizonTable -Connection $conn -Sql $countsSql).Rows[0]

    $columnCountSql = @'
SELECT COUNT(*)
FROM sys.objects o
INNER JOIN sys.columns c ON c.object_id = o.object_id
WHERE o.type IN ('U','V') AND o.is_ms_shipped = 0;
'@
    $columnCount = Get-Scalar $conn $columnCountSql

    # Declared primary keys - is_primary_key = 1, not "named like one". The gap
    # between those two numbers is the most misleading thing in this schema, so
    # the profile reports both.
    Write-Host "  keys and indexes" -ForegroundColor Gray
    $declaredPkSql = @'
SELECT
    o.name         AS [tbl],
    i.name         AS [cons],
    c.name         AS [col],
    ic.key_ordinal AS [key_ord]
FROM sys.indexes i
INNER JOIN sys.objects o ON o.object_id = i.object_id
INNER JOIN sys.index_columns ic
        ON ic.object_id = i.object_id AND ic.index_id = i.index_id
INNER JOIN sys.columns c
        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.is_primary_key = 1 AND o.is_ms_shipped = 0
ORDER BY o.name, ic.key_ordinal;
'@
    $declaredPk = Invoke-HorizonTable -Connection $conn -Sql $declaredPkSql

    $pkNamedSql = @'
SELECT
    SUM(CASE WHEN i.name LIKE 'PK%' THEN 1 ELSE 0 END) AS [named_like_pk],
    SUM(CASE WHEN i.name LIKE 'PK%' AND i.is_primary_key = 0 THEN 1 ELSE 0 END) AS [named_pk_but_not_pk],
    SUM(CASE WHEN i.is_unique = 1 THEN 1 ELSE 0 END) AS [unique_indexes]
FROM sys.indexes i
INNER JOIN sys.objects o ON o.object_id = i.object_id
WHERE o.type = 'U' AND o.is_ms_shipped = 0 AND i.type > 0;
'@
    $pkNamed = (Invoke-HorizonTable -Connection $conn -Sql $pkNamedSql).Rows[0]

    $fkCount    = Get-Scalar $conn 'SELECT COUNT(*) FROM sys.foreign_keys;'
    $fkColCount = Get-Scalar $conn 'SELECT COUNT(*) FROM sys.foreign_key_columns;'

    $noUniqueSql = @'
SELECT COUNT(*)
FROM sys.objects o
WHERE o.type = 'U' AND o.is_ms_shipped = 0
  AND NOT EXISTS (SELECT 1 FROM sys.indexes i
                  WHERE i.object_id = o.object_id AND i.is_unique = 1 AND i.type > 0);
'@
    $noUnique = Get-Scalar $conn $noUniqueSql

    # Same heuristic Generate-SchemaDocs.ps1 uses, so the two never disagree.
    Write-Host "  integer date columns" -ForegroundColor Gray
    $dateColsSql = @'
SELECT COUNT(*) AS [date_columns],
       COUNT(DISTINCT o.object_id) AS [objects]
FROM sys.objects o
INNER JOIN sys.columns c ON c.object_id = o.object_id
WHERE o.type IN ('U','V') AND o.is_ms_shipped = 0
  AND TYPE_NAME(c.system_type_id) = 'smallint'
  AND (c.name LIKE '%date' OR c.name LIKE '%[_]date%');
'@
    $dateCols = (Invoke-HorizonTable -Connection $conn -Sql $dateColsSql).Rows[0]

    $timeColsSql = @'
SELECT COUNT(*)
FROM sys.objects o
INNER JOIN sys.columns c ON c.object_id = o.object_id
WHERE o.type IN ('U','V') AND o.is_ms_shipped = 0
  AND TYPE_NAME(c.system_type_id) = 'smallint'
  AND c.name LIKE '%time'
  AND EXISTS (SELECT 1 FROM sys.columns d
              WHERE d.object_id = c.object_id
                AND d.name = LEFT(c.name, LEN(c.name) - 4) + 'date');
'@
    $timeCols = Get-Scalar $conn $timeColsSql

    Write-Host "  user-defined types" -ForegroundColor Gray
    $udtSql = @'
SELECT TOP 20
    t.name                      AS [declared_type],
    TYPE_NAME(t.system_type_id) AS [base_type],
    t.max_length                AS [len_bytes],
    COUNT(*)                    AS [uses]
FROM sys.columns c
INNER JOIN sys.types t   ON t.user_type_id = c.user_type_id
INNER JOIN sys.objects o ON o.object_id = c.object_id
WHERE t.is_user_defined = 1 AND o.type IN ('U','V') AND o.is_ms_shipped = 0
GROUP BY t.name, t.system_type_id, t.max_length
ORDER BY COUNT(*) DESC;
'@
    $udt = Invoke-HorizonTable -Connection $conn -Sql $udtSql

    Write-Host "  engine feature probes" -ForegroundColor Gray
    $probes = @(
        @{ n = 'STRING_AGG';              s = "SELECT STRING_AGG(CAST(name AS varchar(50)), ',') FROM (SELECT TOP 2 name FROM sys.objects) x;" },
        @{ n = 'STRING_AGG WITHIN GROUP'; s = "SELECT STRING_AGG(CAST(name AS varchar(50)), ',') WITHIN GROUP (ORDER BY name) FROM (SELECT TOP 2 name FROM sys.objects) x;" },
        @{ n = 'CONCAT';                  s = "SELECT CONCAT('a','b');" },
        @{ n = 'IIF';                     s = "SELECT IIF(1 = 1, 'a', 'b');" },
        @{ n = 'FORMAT';                  s = "SELECT FORMAT(1, '0');" },
        @{ n = 'TRY_CONVERT';             s = "SELECT TRY_CONVERT(int, '1');" },
        @{ n = 'OFFSET / FETCH';          s = "SELECT name FROM sys.objects ORDER BY name OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;" },
        @{ n = 'FOR XML PATH on bib.text'; s = "SELECT TOP 1 (SELECT TOP 3 b.text AS [text()] FROM bib b WHERE b.[bib#] = x.[bib#] FOR XML PATH('')) AS agg FROM (SELECT TOP 1 [bib#] FROM bib) x;" }
    )
    $features = @()
    foreach ($p in $probes) { $features += (Test-Feature $conn $p.n $p.s) }

    Write-Host "  object creation clusters" -ForegroundColor Gray
    $clustersSql = @'
SELECT TOP 10
    CAST(o.create_date AS date) AS [created_on],
    COUNT(*)                    AS [tables]
FROM sys.objects o
WHERE o.type = 'U' AND o.is_ms_shipped = 0
GROUP BY CAST(o.create_date AS date)
ORDER BY COUNT(*) DESC;
'@
    $clusters = Invoke-HorizonTable -Connection $conn -Sql $clustersSql

    # ---- Epoch verification ------------------------------------------------
    # The decisive test. A MAX(create_date) sanity check cannot tell a correct
    # epoch from one that is off by a day, and a one-day error silently shifts
    # every dated query at the site. Weekends are the fingerprint: cataloguing
    # stops on Saturday and Sunday, so the right epoch is the one that puts the
    # quiet days on the weekend.
    Write-Host "  epoch verification (bib_control histogram)" -ForegroundColor Gray
    $epochOk    = $false
    $epochNote  = ''
    $hist       = $null
    $bestShift  = $null
    $weekendPct = $null
    try {
        $histSql = "SELECT bc.create_date AS [day_number], COUNT(*) AS [bibs] " +
                   "FROM bib_control bc " +
                   "WHERE bc.create_date >= DATEDIFF(day, '1970-01-01', DATEADD(day, -$EpochProbeDays, GETDATE())) " +
                   "AND bc.create_date <= DATEDIFF(day, '1970-01-01', GETDATE()) " +
                   "GROUP BY bc.create_date ORDER BY bc.create_date;"
        $hist = Invoke-HorizonTable -Connection $conn -Sql $histSql -Timeout 300
    } catch {
        $epochNote = "bib_control could not be sampled: " + (Get-FirstLine $_)
    }

    if ($hist -and $hist.Rows.Count -gt 0) {
        $total = 0
        foreach ($r in $hist.Rows) { $total += [int] $r['bibs'] }

        if ($total -eq 0) {
            $epochNote = 'bib_control returned no rows in the probe window - nothing to test against.'
        } else {
            # Score each candidate epoch by how much cataloguing it puts on a
            # weekend. The true epoch should be the clear minimum.
            $scores = @{}
            foreach ($shift in -3..3) {
                $weekend = 0
                foreach ($r in $hist.Rows) {
                    $d = $EPOCH.AddDays([int] $r['day_number'] + $shift)
                    if ($d.DayOfWeek -eq [System.DayOfWeek]::Saturday -or
                        $d.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
                        $weekend += [int] $r['bibs']
                    }
                }
                $scores[$shift] = $weekend
            }
            $bestShift = ($scores.GetEnumerator() | Sort-Object Value, Name | Select-Object -First 1).Name
            $bestScore = $scores[$bestShift]
            $zeroScore = $scores[0]
            $tieCount  = @($scores.GetEnumerator() | Where-Object { $_.Value -eq $bestScore }).Count

            if ($tieCount -gt 1) {
                $bestShift = $null
                $epochNote = "Inconclusive: $tieCount candidate epochs tie at $bestScore weekend records. " +
                             "Raise -EpochProbeDays, or verify against a bulk load whose date you know independently."
            } elseif ($bestShift -eq 0) {
                $epochOk    = $true
                $weekendPct = [math]::Round(100.0 * $zeroScore / $total, 2)
                $epochNote  = "Verified. Under 1970-01-01, $zeroScore of $total records ($weekendPct%) land on a " +
                              "weekend; every other candidate epoch from -3 to +3 days scores worse."
            } else {
                $suggested = $EPOCH.AddDays($bestShift).ToString('yyyy-MM-dd')
                $epochNote = "MISMATCH. 1970-01-01 puts $zeroScore of $total records on a weekend; " +
                             "$suggested puts only $bestScore there."
            }
        }
    } elseif (-not $epochNote) {
        $epochNote = 'bib_control returned no rows in the probe window - nothing to test against.'
    }
} finally {
    $conn.Close()
}

# ---------------------------------------------------------------------------
# Write the page
# ---------------------------------------------------------------------------

$stamp = (Get-Date).ToString('yyyy-MM-dd')
$sb    = New-Object System.Text.StringBuilder
function Add-Line { param([string] $Text = '') [void] $sb.AppendLine($Text) }

Add-Line '# Site profile (generated)'
Add-Line ''
Add-Line "Measured **$stamp** by ``tools/Get-SiteProfile.ps1`` against this site's live"
Add-Line 'Horizon database. **Do not hand-edit** - re-run the script instead.'
Add-Line ''
Add-Line 'Everything on this page varies between Horizon sites. The rest of the'
Add-Line 'documentation states only what is true of Horizon everywhere and links here for'
Add-Line 'the numbers. If a figure below disagrees with something written in prose'
Add-Line 'elsewhere in this repository, **this page wins** - it was measured; the prose'
Add-Line 'was written.'
Add-Line ''
Add-Line 'No server, database, login or location name is recorded here.'
Add-Line ''
Add-Line '---'
Add-Line ''

Add-Line '## Engine'
Add-Line ''
Add-Line '| Property | Value |'
Add-Line '| --- | --- |'
Add-Line "| SQL Server version | ``$($e['product_version'])`` $($e['product_level']) |"
Add-Line "| Edition | $($e['edition']) |"
Add-Line "| Database compatibility level | **$($e['compat_level'])** |"
Add-Line "| Collation | ``$($e['collation'])`` |"
Add-Line "| Recovery model | **$($e['recovery_model'])** |"
Add-Line "| Read-committed snapshot | $(Format-Bool ([bool][int] $e['rcsi'])) |"
Add-Line ''
if ("$($e['collation'])" -match '_CI_') {
    Add-Line 'The collation is **case-insensitive** (`_CI_`), so `=` and `LIKE` ignore case.'
    Add-Line 'Usually what you want - but a short uppercase acronym such as `DDA` will also'
    Add-Line 'match lowercase text that happens to contain the letters. Add'
    Add-Line '`COLLATE Latin1_General_CS_AS` where exact case matters.'
} else {
    Add-Line 'The collation is **case-sensitive**. Every literal in every predicate must match'
    Add-Line 'the stored case exactly. Most examples in this repository assume case-insensitive'
    Add-Line 'matching and need review before they are run here.'
}
Add-Line ''
if ("$($e['recovery_model'])" -eq 'FULL') {
    Add-Line 'Recovery model is `FULL`, so `SELECT ... INTO` is **fully logged** and gets no'
    Add-Line 'minimal-logging benefit. Size the transaction log for the row count before'
    Add-Line 'building a large working table.'
} else {
    Add-Line "Recovery model is ``$($e['recovery_model'])``, so ``SELECT ... INTO`` can be minimally logged."
    Add-Line 'That makes it a cheap way to build a large working table.'
}
Add-Line ''

Add-Line '## Engine features'
Add-Line ''
Add-Line 'Probed by running each one. Write to what is available *here*, not to what the'
Add-Line 'SQL Server version alone suggests - compatibility level gates most of it.'
Add-Line ''
Add-Line '| Feature | Available | If not, the error was |'
Add-Line '| --- | --- | --- |'
foreach ($f in $features) {
    $d = $f.Detail -replace '\|', '\|'
    if ($d.Length -gt 110) { $d = $d.Substring(0, 107) + '...' }
    Add-Line "| ``$($f.Feature)`` | $(Format-Bool $f.Available) | $d |"
}
Add-Line ''
$missing = @($features | Where-Object { -not $_.Available } | ForEach-Object { $_.Feature })
if ($missing.Count -gt 0) {
    Add-Line "**Unavailable here: $($missing -join ', ').**"
    Add-Line ''
    Add-Line 'Use `CASE` for `IIF`, `+` for `CONCAT`, `TOP` for `OFFSET/FETCH`, and ship a'
    Add-Line 'second detail query (one row per tag) instead of aggregating note text into'
    Add-Line 'one cell.'
} else {
    Add-Line 'All probed features are available. The examples in this repository are written'
    Add-Line 'to a lower common denominator and will still run.'
}
Add-Line ''

Add-Line '## Size'
Add-Line ''
Add-Line '| Measure | Count |'
Add-Line '| --- | ---: |'
Add-Line "| Tables | $($counts['tables']) |"
Add-Line "| Views | $($counts['views']) |"
Add-Line "| Columns (tables and views) | $columnCount |"
Add-Line "| Declared foreign keys | $fkCount ($fkColCount columns) |"
Add-Line "| Tables with no unique index | $noUnique |"
Add-Line ''
Add-Line 'A table with no unique index has **no stated grain**: nothing constrains it to'
Add-Line 'one row per key, so treat every join to it as a fan-out risk.'
Add-Line ''

Add-Line '## Keys - and the `PK_` trap'
Add-Line ''
Add-Line '| Measure | Count |'
Add-Line '| --- | ---: |'
Add-Line "| **Declared** primary key constraints (columns) | **$($declaredPk.Rows.Count)** |"
Add-Line "| Indexes *named* like a primary key | $($pkNamed['named_like_pk']) |"
Add-Line "| ...of those, **not** actually primary keys | **$($pkNamed['named_pk_but_not_pk'])** |"
Add-Line "| Unique indexes | $($pkNamed['unique_indexes']) |"
Add-Line ''
if ([int] $pkNamed['named_pk_but_not_pk'] -gt 0) {
    Add-Line "**$($pkNamed['named_pk_but_not_pk']) indexes here are named ``PK...`` and are not primary keys.**"
    Add-Line 'Never infer a constraint from an index name; check `is_unique` in'
    Add-Line '`indexes_and_keys.csv`. Grain at this site comes from **unique indexes**.'
    Add-Line ''
}
if ($declaredPk.Rows.Count -gt 0) {
    Add-Line 'The declared primary keys, in full:'
    Add-Line ''
    Add-Line '| Table | Constraint | Column | Ord |'
    Add-Line '| --- | --- | --- | ---: |'
    foreach ($r in $declaredPk.Rows) {
        Add-Line "| ``$($r['tbl'])`` | ``$($r['cons'])`` | ``$($r['col'])`` | $($r['key_ord']) |"
    }
} else {
    Add-Line 'This database declares **no** primary key constraints at all. Grain comes'
    Add-Line 'entirely from unique indexes.'
}
Add-Line ''

Add-Line '## Integer date columns'
Add-Line ''
Add-Line "**$($dateCols['date_columns']) ``smallint`` date columns across $($dateCols['objects']) objects**, with **$timeCols** paired"
Add-Line '`_time` columns. These hold a **day count**, not a SQL `date`.'
Add-Line ''
Add-Line '### Epoch'
Add-Line ''
if ($epochOk) {
    Add-Line "> **Epoch: ``1970-01-01`` - VERIFIED $stamp.**"
    Add-Line '>'
    Add-Line "> $epochNote"
    Add-Line ''
    Add-Line 'Write date predicates against that anchor, which is what every example in this'
    Add-Line 'repository assumes:'
    Add-Line ''
    Add-Line '```sql'
    Add-Line "WHERE bc.create_date = DATEDIFF(day, '1970-01-01', '2026-08-25')"
    Add-Line '```'
} elseif ($null -ne $bestShift) {
    $suggested = $EPOCH.AddDays($bestShift).ToString('yyyy-MM-dd')
    Add-Line "> **Epoch: ``$suggested`` - NOT the ``1970-01-01`` this repository's examples assume.**"
    Add-Line '>'
    Add-Line "> $epochNote"
    Add-Line ''
    Add-Line 'Every example in this repository anchors on `1970-01-01`. **Change the anchor in'
    Add-Line 'every dated query before running it here**, or every result is off by'
    Add-Line "$([math]::Abs($bestShift)) day(s) - an error nothing will flag."
    Add-Line ''
    Add-Line '```sql'
    Add-Line "WHERE bc.create_date = DATEDIFF(day, '$suggested', '2026-08-25')"
    Add-Line '```'
} else {
    Add-Line '> **Epoch: UNVERIFIED.**'
    Add-Line '>'
    Add-Line "> $epochNote"
    Add-Line ''
    Add-Line '**Do not write a dated query until this is settled.** A one-day error is'
    Add-Line 'invisible: nothing looks broken, the numbers are simply wrong. Verify by hand'
    Add-Line 'with the two-step procedure in [conventions.md](conventions.md#dates), and'
    Add-Line 'corroborate against a bulk load whose date you know independently.'
}
Add-Line ''
if ($hist -and $hist.Rows.Count -gt 0) {
    Add-Line '<details>'
    Add-Line "<summary>Evidence: bib records created per day, last $EpochProbeDays days</summary>"
    Add-Line ''
    Add-Line '| Day number | Decodes to (1970-01-01) | Weekday | Bibs created |'
    Add-Line '| ---: | --- | --- | ---: |'
    foreach ($r in $hist.Rows) {
        $d  = $EPOCH.AddDays([int] $r['day_number'])
        $wd = $d.DayOfWeek.ToString()
        if ($wd -eq 'Saturday' -or $wd -eq 'Sunday') { $wd = "**$wd**" }
        Add-Line "| $($r['day_number']) | $($d.ToString('yyyy-MM-dd')) | $wd | $($r['bibs']) |"
    }
    Add-Line ''
    Add-Line 'Days with no cataloguing are absent rather than zero. The epoch is right when'
    Add-Line 'the bold weekend rows are the ones missing.'
    Add-Line ''
    Add-Line '</details>'
    Add-Line ''
}

Add-Line '### Time columns'
Add-Line ''
Add-Line 'The paired `_time` columns are `smallint` too, but **their encoding is not probed'
Add-Line 'here** - minutes-since-midnight and an `hhmm` integer both fit the data. Check'
Add-Line 'one against a record whose creation time you know before putting a time column'
Add-Line 'in a predicate.'
Add-Line ''

Add-Line '## User-defined types'
Add-Line ''
Add-Line 'Horizon declares most columns through UDTs. The declared type tells you the'
Add-Line "column's *role*; the base type tells you how it *behaves*. Top 20 by use:"
Add-Line ''
Add-Line '| Declared type | Base type | Bytes | Uses |'
Add-Line '| --- | --- | ---: | ---: |'
foreach ($r in $udt.Rows) {
    Add-Line "| ``$($r['declared_type'])`` | ``$($r['base_type'])`` | $($r['len_bytes']) | $($r['uses']) |"
}
Add-Line ''
Add-Line '`code_type` is the strongest signal in the schema: such a column almost always'
Add-Line 'joins to a same-named lookup table (`item.collection` to `collection.collection`).'
Add-Line ''

Add-Line '## Object creation clusters'
Add-Line ''
Add-Line 'Tables sharing a `create_date` were created together - an install or an upgrade.'
Add-Line 'Tables created alone, later, are usually local additions. The scratch-table'
Add-Line 'cleanup uses this; the largest cluster is normally the Horizon install itself.'
Add-Line ''
Add-Line '| Created on | Tables |'
Add-Line '| --- | ---: |'
foreach ($r in $clusters.Rows) {
    Add-Line "| $(([datetime] $r['created_on']).ToString('yyyy-MM-dd')) | $($r['tables']) |"
}
Add-Line ''
Add-Line 'A late `create_date` does **not** prove a table is local: rebuilding a vendor'
Add-Line 'table during an upgrade resets it. Judge on structure as well.'
Add-Line ''
Add-Line '---'
Add-Line ''
Add-Line '## Re-run this after'
Add-Line ''
Add-Line '- a Horizon upgrade, or any change to the database compatibility level'
Add-Line '- restoring a backup, especially one taken at another site'
Add-Line '- a collation or recovery-model change'
Add-Line '- the scratch-table cleanup, which changes the object counts'
Add-Line ''
Add-Line '```powershell'
Add-Line 'powershell -ExecutionPolicy Bypass -File tools\Get-SiteProfile.ps1 -Server ILSSERVER -Database ILSDB'
Add-Line '```'

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
# WriteAllText with a BOM-less encoder: Out-File -Encoding utf8 emits a BOM on
# Windows PowerShell 5.1, which renders as a stray glyph on line 1 in GitHub.
[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))

Write-Host ""
Write-Host "Wrote $OutFile" -ForegroundColor Green
Write-Host ""
if ($epochOk) {
    Write-Host "  Epoch 1970-01-01 VERIFIED." -ForegroundColor Green
} else {
    Write-Host "  EPOCH NOT VERIFIED - read the Epoch section before writing any dated query." -ForegroundColor Yellow
    Write-Host "  $epochNote" -ForegroundColor Yellow
}
if ($missing.Count -gt 0) {
    Write-Host "  Unavailable T-SQL features: $($missing -join ', ')" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Next: commit the profile, then read docs\schema\AGENTS.md before writing SQL." -ForegroundColor Cyan
