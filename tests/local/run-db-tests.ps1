# Runs Vectovia's database tests on a THROWAWAY local PostgreSQL (never Supabase).
# Builds a fresh database, loads the Supabase stand-in, applies every Vectovia
# revision in docs/database (v2-*.sql, in order), then runs every test in
# supabase/tests.
# Usage: powershell -File tests/local/run-db-tests.ps1 [-PgBin <path to pgsql\bin>]
param(
  [string]$PgBin = 'C:\fltest\pg\pgsql\bin',
  [string]$Work  = 'C:\vvtest',
  [int]$Port     = 54333
)
$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$data = Join-Path $Work 'data'
$log  = Join-Path $Work 'pg.log'
New-Item -ItemType Directory -Force $Work | Out-Null
$env:PGOPTIONS = '-c search_path=public,extensions,tap'

function Invoke-Sql([string]$file, [switch]$Quiet) {
  $out = & "$PgBin\psql.exe" -h localhost -p $Port -U postgres -d postgres -v ON_ERROR_STOP=1 -X -q -t -A -f $file 2>&1
  if ($LASTEXITCODE -ne 0) { $out | Out-String | Write-Host; throw "SQL failed: $file" }
  if (-not $Quiet) { $out | Where-Object { "$_".Trim() } }
}

if (Test-Path $data) { Remove-Item -Recurse -Force $data }
& "$PgBin\initdb.exe" -D $data -U postgres -A trust -E UTF8 --locale=C | Out-Null
Start-Process -FilePath "$PgBin\pg_ctl.exe" -WindowStyle Hidden -ArgumentList @('-D', "`"$data`"", '-l', "`"$log`"", '-o', "`"-p $Port -c listen_addresses=localhost`"", 'start')
$ready = $false
for ($i = 0; $i -lt 60 -and -not $ready; $i++) { Start-Sleep -Milliseconds 500; & "$PgBin\pg_isready.exe" -h localhost -p $Port -q; $ready = ($LASTEXITCODE -eq 0) }
if (-not $ready) { throw "local PostgreSQL did not start; see $log" }
$results = @()
try {
  Invoke-Sql (Join-Path $repo 'tests\local\supabase-standin.sql') -Quiet
  Invoke-Sql (Join-Path $repo 'tests\local\pgtap-shim.sql') -Quiet
  Get-ChildItem (Join-Path $repo 'docs\database') -Filter 'v2-*.sql' | Where-Object { $_.Name -notmatch 'rollback' } | Sort-Object Name | ForEach-Object {
    Invoke-Sql $_.FullName -Quiet; Write-Host "applied $($_.Name)"
  }
  Get-ChildItem (Join-Path $repo 'supabase\tests') -Filter '*.test.sql' | Sort-Object Name | ForEach-Object {
    $r = Invoke-Sql $_.FullName
    Write-Host "== $($_.Name)"; ($r | Where-Object { $_ -match '^not ok|^#' }) | Write-Host
    $results += $r
  }
  if ($results -match '^not ok') { exit 1 }
} finally {
  Start-Process -FilePath "$PgBin\pg_ctl.exe" -WindowStyle Hidden -Wait -ArgumentList @('-D', "`"$data`"", '-m', 'fast', 'stop')
}
