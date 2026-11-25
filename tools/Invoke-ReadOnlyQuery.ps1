<#
.SYNOPSIS
    Runs one read-only SELECT against the Horizon database named in
    tools\site.local.psd1, and shows or saves the result.

.DESCRIPTION
    The single way an AI assistant (Codex, Claude Code, or any other) - or a
    person - queries the live catalog from this repository, so that every
    query connects the same way and none of them can change data.

    In short: the batch is refused before sending if it could write, it runs
    inside a transaction that is always rolled back, and every run reports
    whether the connecting Windows login could write anyway. There is no
    separate read-only login. Full description of each layer, and why:
    tools\README.md, section "Invoke-ReadOnlyQuery.ps1".

    Connection details come from tools\site.local.psd1, which is gitignored.
    Copy tools\site.local.example.psd1 to create it. Windows authentication
    only: this script takes no login or password, by design.

.PARAMETER Sql
    The query text. Use -File instead for anything long.
.PARAMETER File
    A .sql file to run - e.g. one of the generated solutions\*\sql\*.sql files.
.PARAMETER OutCsv
    Stream every row of the first result set to this CSV (UTF-8 with BOM, every
    field quoted, so commas in MARC text are safe and Excel opens it cleanly).
    Catalog data: keep it under "excel reports\" or killbib-audit\, both
    gitignored.
.PARAMETER MaxRows
    How many rows to print to the console per result set. Default 50. The CSV
    always gets every row.
.PARAMETER Timeout
    Query timeout in seconds. Default 600.
.PARAMETER ConfigPath
    Use a different site config file.
.PARAMETER CheckAccess
    Report what the connecting Windows login is allowed to do in the database,
    then stop. Runs no query of yours.

.EXAMPLE
    tools\Invoke-ReadOnlyQuery.ps1 -Sql "SELECT COUNT(*) AS n FROM bib_control"

.EXAMPLE
    tools\Invoke-ReadOnlyQuery.ps1 -File solutions\590-ebk-purchase-dda-report\sql\01-the-report-read-only.sql -OutCsv "excel reports\dda.csv"
#>

[CmdletBinding()]
param(
    [string] $Sql,
    [string] $File,
    [string] $OutCsv,
    [int]    $MaxRows = 50,
    [int]    $Timeout = 600,
    [string] $ConfigPath,
    [switch] $CheckAccess
)

$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $toolsDir 'HorizonSql.ps1')    # ConvertTo-BareSql

function Get-HorizonSiteConfig {
    <#
        Reads tools\site.local.psd1. Throws an actionable message when it is
        missing or incomplete, rather than guessing a server.
    #>
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw @"
No site config at $Path.
Copy tools\site.local.example.psd1 to tools\site.local.psd1 and fill in the
server and database. The file is gitignored, so the real names stay local.
"@
    }
    $cfg = Import-PowerShellDataFile -LiteralPath $Path
    foreach ($k in 'Server', 'Database') {
        if (-not $cfg[$k] -or $cfg[$k] -in 'ILSSERVER', 'ILSDB') {
            throw "tools\site.local.psd1: '$k' is missing or still the placeholder. Fill in the real value."
        }
    }
    return $cfg
}

# Refusal rules, checked in order against the batch with strings, comments and
# [identifiers] blanked out. {0} in a message is the text that matched. Adding
# a rule is one line here plus a case in Test-Tools.ps1.
$script:RefusalRules = @(
    @{ P = '(?im)^\s*GO\s*$'
       M = 'contains GO. Send one batch at a time - GO is an SSMS separator, not T-SQL.' }
    @{ P = '(?i)\b(INSERT|UPDATE|DELETE|MERGE|CREATE|DROP|ALTER|GRANT|REVOKE|DENY|TRUNCATE|EXEC|EXECUTE|BACKUP|RESTORE|DBCC|BULK|KILL|SHUTDOWN|RECONFIGURE|USE)\b'
       M = 'contains {0}. This tool only reads; changes go through the delete tooling, run by a person.' }
    # The always-rollback layer only holds if the batch cannot end the
    # transaction itself.
    @{ P = '(?i)\b(COMMIT|ROLLBACK|SAVE|BEGIN\s+(TRAN|TRANSACTION|DISTRIBUTED))\b'
       M = 'contains {0}. Transactions are managed by this tool, which always rolls back.' }
    # Every batch runs in a transaction, so a lock taken by a hint or a stricter
    # isolation level lasts until the rollback - long enough to stall
    # circulation on the live system.
    @{ P = '(?i)\b(WAITFOR|TABLOCK|TABLOCKX|XLOCK|UPDLOCK|HOLDLOCK|PAGLOCK|SERIALIZABLE|REPEATABLEREAD|REPEATABLE\s+READ)\b'
       M = 'contains {0}, which would hold locks on the live catalog. Remove it.' }
    @{ P = '(?is)\bSELECT\b.*?\bINTO\b\s+[\[\w#@]'
       M = 'contains SELECT ... INTO, which creates a table. Remove the INTO clause.' }
    @{ P = '(?i)\b(OPENROWSET|OPENQUERY|OPENDATASOURCE|OPENXML|xp_\w+|sp_\w+)\b'
       M = 'calls {0}, which is not allowed here.' }
    @{ P = '(?i)\bSET\s+(LOCK_TIMEOUT|DEADLOCK_PRIORITY|CONTEXT_INFO|IDENTITY_INSERT)\b'
       M = 'changes a session setting ({0}) this tool does not allow.' }
)

function Test-ReadOnlySql {
    <#
        Returns $null when the batch is acceptable, otherwise the reason it was
        refused. Fails CLOSED: anything it cannot positively accept is refused.
    #>
    param([string] $Code)
    # The committed solutions use placeholders for site values (CLAUDE.md).
    # Run unedited, they return a plausible answer about nobody - usually 0,
    # which a post-delete check reads as success. Case-sensitive, quoted and
    # exact, so real values and ordinary text never trip it.
    $m = [regex]::Match($Code, "'(CATALOGER|OTHERUSER|HZUSER|LOC|ILSSERVER|ILSDB|ils_svc|staff_readers)'")
    if ($m.Success) {
        return "still contains the placeholder $($m.Value). Replace it with the real value (the private handoff file lists them). A result from a placeholder is meaningless - it usually comes back 0."
    }
    $bare = ConvertTo-BareSql -Code $Code
    if ($null -eq $bare) {
        return "has an unterminated string, comment or [identifier], so it cannot be checked."
    }
    foreach ($r in $script:RefusalRules) {
        $m = [regex]::Match($bare, $r.P)
        if ($m.Success) { return ($r.M -f ($m.Value.ToUpper() -replace '\s+', ' ')) }
    }
    if ($bare.TrimStart(" `t`r`n;") -notmatch '(?i)^(SELECT|WITH|DECLARE|SET)\b') {
        return "does not start with SELECT, WITH, DECLARE or SET. A bare procedure name runs it as a call."
    }
    return $null
}

# What the connecting login could change, asked of the database itself.
# HAS_PERMS_BY_NAME answers for the EFFECTIVE permission - group memberships,
# role grants and DENYs all included - so it is right however access was given.
# Every table and procedure is checked, not a sample: one writable table
# anywhere (patron data included) is enough to make the login able to write.
$script:AccessSql = @"
SELECT
    SUSER_SNAME()                                AS login_name,
    IS_SRVROLEMEMBER('sysadmin')                 AS is_sysadmin,
    ISNULL(IS_ROLEMEMBER('db_owner'), 0)         AS is_db_owner,
    ISNULL(IS_ROLEMEMBER('db_datawriter'), 0)    AS is_db_datawriter,
    ISNULL(IS_ROLEMEMBER('db_ddladmin'), 0)      AS is_db_ddladmin,
    ISNULL(IS_ROLEMEMBER('db_datareader'), 0)    AS is_db_datareader,
    (SELECT COUNT(*) FROM (
        SELECT QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) AS qn
        FROM sys.tables) t
      WHERE ISNULL(HAS_PERMS_BY_NAME(t.qn, 'OBJECT', 'INSERT'), 0)
          + ISNULL(HAS_PERMS_BY_NAME(t.qn, 'OBJECT', 'UPDATE'), 0)
          + ISNULL(HAS_PERMS_BY_NAME(t.qn, 'OBJECT', 'DELETE'), 0) > 0)
                                                 AS writable_tables,
    (SELECT COUNT(*) FROM (
        SELECT QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) AS qn
        FROM sys.procedures) p
      WHERE ISNULL(HAS_PERMS_BY_NAME(p.qn, 'OBJECT', 'EXECUTE'), 0) = 1)
                                                 AS executable_procs,
    ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'CREATE TABLE'), 0)
  + ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'ALTER'), 0)
  + ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'CONTROL'), 0)
                                                 AS database_write_perms
"@

function Get-AccessVerdict {
    <#
        Turns one row of $AccessSql into @{ ReadOnly; Failed; Summary }. Pure,
        so the decision is testable offline. Any write permission, or any role
        that implies one, means the database would accept a write.
    #>
    param($Row)
    $reasons = @()
    if ([int]$Row.is_sysadmin          -eq 1) { $reasons += 'sysadmin on the server' }
    if ([int]$Row.is_db_owner          -eq 1) { $reasons += 'db_owner' }
    if ([int]$Row.is_db_datawriter     -eq 1) { $reasons += 'db_datawriter' }
    if ([int]$Row.is_db_ddladmin       -eq 1) { $reasons += 'db_ddladmin' }
    if ([int]$Row.writable_tables      -gt 0) { $reasons += "can insert, update or delete in $($Row.writable_tables) table(s)" }
    if ([int]$Row.executable_procs     -gt 0) { $reasons += "can execute $($Row.executable_procs) stored procedure(s)" }
    if ([int]$Row.database_write_perms -gt 0) { $reasons += 'can create or alter objects in the database' }
    if ($reasons.Count -eq 0) {
        return @{ ReadOnly = $true; Failed = $false
                  Summary = "read-only: the database itself refuses writes from $($Row.login_name)" }
    }
    return @{ ReadOnly = $false; Failed = $false
              Summary = "$($Row.login_name) CAN change data ($($reasons -join '; ')). Only this tool's checks and rollback prevent writes - never query any other way." }
}

function ConvertTo-CsvLine {
    <# One CSV line, every field quoted, embedded quotes doubled, NULL as empty. #>
    param([object[]] $Values)
    $parts = New-Object 'string[]' $Values.Count
    for ($k = 0; $k -lt $Values.Count; $k++) {
        $v = $Values[$k]
        $s = if ($v -is [DBNull] -or $null -eq $v) { '' } else { [string]$v }
        $parts[$k] = '"' + $s.Replace('"', '""') + '"'
    }
    return ($parts -join ',')
}

# Lets Test-Tools.ps1 load the functions above without connecting anywhere.
if ($MyInvocation.InvocationName -eq '.') { return }

# --- input -----------------------------------------------------------------
if (-not $CheckAccess) {
    if ($File) {
        if ($Sql) { throw "Give -Sql or -File, not both." }
        $Sql = Get-Content -LiteralPath $File -Raw -Encoding UTF8
    }
    if (-not $Sql -or -not $Sql.Trim()) { throw "No query. Pass -Sql '<query>' or -File <path.sql>." }

    $why = Test-ReadOnlySql -Code $Sql
    if ($why) {
        Write-Host "REFUSED - nothing was sent to the database." -ForegroundColor Red
        Write-Host "  The query $why" -ForegroundColor Red
        exit 2
    }
}

if (-not $ConfigPath) { $ConfigPath = Join-Path $toolsDir 'site.local.psd1' }
$cfg = Get-HorizonSiteConfig -Path $ConfigPath

# --- connect, and report what this login could do -------------------------
$cs = "Server=$($cfg.Server);Database=$($cfg.Database);Integrated Security=SSPI;" +
      "Application Name=ReadOnlyQuery;ApplicationIntent=ReadOnly;Connect Timeout=15"
$conn = New-Object System.Data.SqlClient.SqlConnection $cs
try { $conn.Open() } catch {
    Write-Host "COULD NOT CONNECT to $($cfg.Server) / $($cfg.Database):" -ForegroundColor Red
    Write-Host "  $($_.Exception.InnerException.Message)$(if (-not $_.Exception.InnerException) { $_.Exception.Message })" -ForegroundColor Red
    exit 4
}

$adt = New-Object System.Data.DataTable
try {
    $acmd = $conn.CreateCommand(); $acmd.CommandText = $script:AccessSql; $acmd.CommandTimeout = 60
    $adt.Load($acmd.ExecuteReader())
    $verdict = Get-AccessVerdict -Row $adt.Rows[0]
} catch {
    $verdict = @{ ReadOnly = $false; Failed = $true
                  Summary = "could not determine this login's permissions ($($_.Exception.Message)) - assume it can write." }
}
$color = if ($verdict.ReadOnly) { 'DarkGray' } else { 'Yellow' }
Write-Host "Access: $($verdict.Summary)" -ForegroundColor $color
if ($CheckAccess) {
    if (-not $verdict.Failed) { $adt.Rows | Format-List | Out-String | Write-Host }
    $conn.Close()
    exit $(if ($verdict.Failed) { 1 } else { 0 })   # a failed check is never a pass
}

# --- run: stream results, always roll back ---------------------------------
# Rows are read as they arrive rather than buffered, so a 250,000-row export
# costs no more memory than a 10-row one. The console keeps only the first
# -MaxRows rows of each result set; the CSV gets every row of the first.
$sets = New-Object System.Collections.Generic.List[object]
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$rolledBack = $false
$reader = $null; $writer = $null; $csvRows = $null
try {
    $tx = $conn.BeginTransaction()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.Transaction    = $tx
        $cmd.CommandText    = $Sql
        $cmd.CommandTimeout = $Timeout
        $reader = $cmd.ExecuteReader()
        do {
            $fc = $reader.FieldCount
            if ($fc -eq 0) { continue }
            # Unique, non-empty column names, so the console objects can be built.
            $cols = New-Object 'string[]' $fc
            for ($k = 0; $k -lt $fc; $k++) {
                $name = $reader.GetName($k); if (-not $name) { $name = "Column$($k + 1)" }
                while ($cols -contains $name) { $name += "_$($k + 1)" }
                $cols[$k] = $name
            }
            if ($OutCsv -and $sets.Count -eq 0) {
                $dir = Split-Path -Parent $OutCsv
                if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                $writer = New-Object System.IO.StreamWriter($OutCsv, $false, (New-Object System.Text.UTF8Encoding $true))
                $writer.WriteLine((ConvertTo-CsvLine -Values $cols))
            }
            $shown = New-Object System.Collections.Generic.List[object]
            $count = 0
            $vals = New-Object 'object[]' $fc
            while ($reader.Read()) {
                $count++
                [void] $reader.GetValues($vals)
                if ($writer) { $writer.WriteLine((ConvertTo-CsvLine -Values $vals)) }
                if ($shown.Count -lt $MaxRows) {
                    $o = [ordered]@{}
                    for ($k = 0; $k -lt $fc; $k++) { $o[$cols[$k]] = $vals[$k] }
                    $shown.Add([pscustomobject]$o)
                }
            }
            if ($writer) { $writer.Dispose(); $writer = $null; $csvRows = $count }
            $sets.Add(@{ Shown = $shown; Count = $count })
        } while ($reader.NextResult())
    } finally {
        if ($writer) { $writer.Dispose() }
        if ($reader -and -not $reader.IsClosed) { $reader.Close() }
        # Always. Even a pure SELECT ends here, so nothing a batch did survives.
        # A transaction whose Connection is gone was ended by the batch itself -
        # the refusal rules should make that impossible, so say so loudly.
        if ($null -ne $tx.Connection) {
            try { $tx.Rollback(); $rolledBack = $true }
            catch { Write-Host "WARNING: rollback failed: $($_.Exception.Message)" -ForegroundColor Red }
        } else {
            Write-Host "WARNING: the batch ended the transaction itself, so it could not be rolled back. Tell the maintainer." -ForegroundColor Red
        }
    }
} catch [System.Data.SqlClient.SqlException] {
    # A SQL error is an answer, not a crash: show SQL Server's own message,
    # plainly, and exit 4. The rollback above has already run.
    $conn.Close()
    Write-Host "SQL ERROR - the database rejected the query (nothing was changed):" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 4
} catch [System.Management.Automation.MethodInvocationException] {
    $inner = $_.Exception.InnerException
    if (-not ($inner -is [System.Data.SqlClient.SqlException])) { throw }
    $conn.Close()
    Write-Host "SQL ERROR - the database rejected the query (nothing was changed):" -ForegroundColor Red
    Write-Host "  $($inner.Message)" -ForegroundColor Red
    exit 4
} finally {
    $conn.Close()
}
$sw.Stop()

# --- output ----------------------------------------------------------------
if ($sets.Count -eq 0) {
    Write-Host ("No result set returned ({0:N1}s)." -f $sw.Elapsed.TotalSeconds) -ForegroundColor Yellow
}
for ($s = 0; $s -lt $sets.Count; $s++) {
    $label = if ($sets.Count -gt 1) { "Result set $($s + 1)" } else { "Result" }
    $set = $sets[$s]
    Write-Host ("{0}: {1} row(s), {2:N1}s" -f $label, $set.Count, $sw.Elapsed.TotalSeconds) -ForegroundColor Cyan
    if ($set.Count -gt 0) {
        $set.Shown | Format-Table -AutoSize -Wrap | Out-String -Width 4096 | Write-Host
        if ($set.Count -gt $set.Shown.Count) {
            Write-Host "  ... $($set.Count - $set.Shown.Count) more row(s) not shown. Use -OutCsv for all of them." -ForegroundColor DarkGray
        }
    }
}
if ($OutCsv -and $null -ne $csvRows) {
    Write-Host "Saved $csvRows row(s) to $((Resolve-Path -LiteralPath $OutCsv).Path)" -ForegroundColor Green
}
# Exit 3 when the rollback did not happen, so a caller that checks only the
# exit code still sees it.
exit $(if ($rolledBack) { 0 } else { 3 })
