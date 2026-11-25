<#
.SYNOPSIS
    Runs one read-only SELECT against the Horizon database named in
    tools\site.local.psd1, and shows or saves the result.

.DESCRIPTION
    The single way an AI assistant (Codex, Claude Code, or any other) - or a
    person - queries the live catalog from this repository. It exists so that
    every query connects the same way and none of them can change data.

    Three independent layers keep it read-only:

      1. The SQL is refused before it is sent if it contains any statement that
         writes (INSERT, UPDATE, DELETE, MERGE, CREATE, DROP, ALTER, GRANT,
         TRUNCATE, EXEC, SELECT ... INTO, ...), calls an external data source,
         or does not start with SELECT / WITH / DECLARE / SET. The check fails
         CLOSED: anything it cannot positively accept is refused.
      2. The batch runs inside a transaction that is ALWAYS rolled back, so a
         write that somehow passed layer 1 is undone before the connection
         closes.
      3. The connection uses Windows authentication. Ask IT for a login that
         holds only db_datareader; then the database itself refuses writes,
         whatever the first two layers do.

    Connection details come from tools\site.local.psd1, which is gitignored.
    Copy tools\site.local.example.psd1 to create it. Real server and database
    names never appear in a tracked file.

    Changing data is deliberately out of scope. Deletes go through
    Invoke-DeleteListRun.ps1 / Invoke-KillBib.ps1, run by a person.

.PARAMETER Sql
    The query text. Use -File instead for anything long.
.PARAMETER File
    A .sql file to run - e.g. one of the generated solutions\*\sql\*.sql files.
.PARAMETER OutCsv
    Save every row of the first result set to this CSV (UTF-8, all fields
    quoted, so commas in MARC text are safe). Catalog data: keep it under
    "excel reports\" or killbib-audit\, both gitignored.
.PARAMETER MaxRows
    How many rows to print to the console per result set. Default 50. The CSV
    always gets every row.
.PARAMETER Timeout
    Query timeout in seconds. Default 600.
.PARAMETER ConfigPath
    Use a different site config file.

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
    [string] $ConfigPath
)

$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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

function Test-ReadOnlySql {
    <#
        Returns $null when the batch is acceptable, otherwise the reason it was
        refused. Fails CLOSED. Comments and string literals are removed first,
        so a keyword inside a note ('... UPDATE ...') does not count, and one
        hidden in a comment cannot smuggle anything past the start-of-batch rule.
    #>
    param([string] $Code)

    $bare = $Code -replace '(?s)/\*.*?\*/', ' ' -replace '(?m)--[^\n]*', ' ' -replace "'(?:''|[^'])*'", " '' "

    if ($bare -match '(?im)^\s*GO\s*$') {
        return "contains GO. Send one batch at a time - GO is an SSMS separator, not T-SQL."
    }
    $m = [regex]::Match($bare, '(?i)\b(INSERT|UPDATE|DELETE|MERGE|CREATE|DROP|ALTER|GRANT|REVOKE|DENY|TRUNCATE|EXEC|EXECUTE|BACKUP|RESTORE|DBCC|BULK|KILL|SHUTDOWN|RECONFIGURE|USE)\b')
    if ($m.Success) { return "contains $($m.Value.ToUpper()). This tool only reads; changes go through the delete tooling, run by a person." }
    if ($bare -match '(?is)\bSELECT\b.*?\bINTO\b\s+[\[\w#@]') {
        return "contains SELECT ... INTO, which creates a table. Remove the INTO clause."
    }
    $m = [regex]::Match($bare, '(?i)\b(OPENROWSET|OPENQUERY|OPENDATASOURCE|OPENXML|xp_\w+|sp_\w+)\b')
    if ($m.Success) { return "calls $($m.Value), which is not allowed here." }
    if ($bare -match '(?i)\bSET\s+(LOCK_TIMEOUT|DEADLOCK_PRIORITY|CONTEXT_INFO|IDENTITY_INSERT)\b') {
        return "changes a session setting this tool does not allow."
    }

    $start = $bare.TrimStart(" `t`r`n;")
    if ($start -notmatch '(?i)^(SELECT|WITH|DECLARE|SET)\b') {
        return "does not start with SELECT, WITH, DECLARE or SET. A bare procedure name runs it as a call."
    }
    return $null
}

# Lets Test-Tools.ps1 load the functions above without connecting anywhere.
if ($MyInvocation.InvocationName -eq '.') { return }

# --- input -----------------------------------------------------------------
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

if (-not $ConfigPath) { $ConfigPath = Join-Path $toolsDir 'site.local.psd1' }
$cfg = Get-HorizonSiteConfig -Path $ConfigPath

# --- run -------------------------------------------------------------------
$cs = "Server=$($cfg.Server);Database=$($cfg.Database);Integrated Security=SSPI;" +
      "Application Name=ReadOnlyQuery;ApplicationIntent=ReadOnly;Connect Timeout=15"
$conn = New-Object System.Data.SqlClient.SqlConnection $cs
$ds = New-Object System.Data.DataSet
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$conn.Open()
try {
    $tx = $conn.BeginTransaction()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.Transaction    = $tx
        $cmd.CommandText    = $Sql
        $cmd.CommandTimeout = $Timeout
        $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        [void] $da.Fill($ds)
    } finally {
        # Always. Even a pure SELECT ends here, so nothing a batch did survives.
        try { $tx.Rollback() } catch { }
    }
} finally {
    $conn.Close()
}
$sw.Stop()

# --- output ----------------------------------------------------------------
if ($ds.Tables.Count -eq 0) {
    Write-Host ("No result set returned ({0:N1}s)." -f $sw.Elapsed.TotalSeconds) -ForegroundColor Yellow
    exit 0
}
$i = 0
foreach ($t in $ds.Tables) {
    $i++
    $label = if ($ds.Tables.Count -gt 1) { "Result set $i" } else { "Result" }
    Write-Host ("{0}: {1} row(s), {2:N1}s" -f $label, $t.Rows.Count, $sw.Elapsed.TotalSeconds) -ForegroundColor Cyan
    if ($t.Rows.Count -gt 0) {
        $t.Rows | Select-Object -First $MaxRows -Property ($t.Columns | ForEach-Object { $_.ColumnName }) |
            Format-Table -AutoSize -Wrap | Out-String -Width 4096 | Write-Host
        if ($t.Rows.Count -gt $MaxRows) {
            Write-Host "  ... $($t.Rows.Count - $MaxRows) more row(s) not shown. Use -OutCsv for all of them." -ForegroundColor DarkGray
        }
    }
}

if ($OutCsv) {
    $dir = Split-Path -Parent $OutCsv
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $t = $ds.Tables[0]
    $t.Rows | Select-Object -Property ($t.Columns | ForEach-Object { $_.ColumnName }) |
        Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Saved $($t.Rows.Count) row(s) to $((Resolve-Path -LiteralPath $OutCsv).Path)" -ForegroundColor Green
}
exit 0
