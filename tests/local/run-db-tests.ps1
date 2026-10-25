# Runs the database tests on a THROWAWAY local PostgreSQL 17 (never Supabase).
# Builds a fresh database, loads the Supabase stand-in, the applied migrations
# (revs 6-8), the draft revision 10 and its tests, then checks the rollback.
# Usage: powershell -File tests/local/run-db-tests.ps1 [-PgBin <path to pgsql\bin>]
param(
  [string]$PgBin = 'C:\fltest\pg\pgsql\bin',
  [string]$Work  = 'C:\fltest',
  [int]$Port     = 54329
)
$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$data = Join-Path $Work 'data'
$log  = Join-Path $Work 'pg.log'
$env:PGOPTIONS = '-c search_path=public,extensions,tap'

function Invoke-Sql([string]$file, [switch]$Quiet) {
  $out = & "$PgBin\psql.exe" -h localhost -p $Port -U postgres -d postgres -v ON_ERROR_STOP=1 -X -q -t -A -f $file 2>&1
  if ($LASTEXITCODE -ne 0) { $out | Out-String | Write-Host; throw "SQL failed: $file" }
  if (-not $Quiet) { $out | Where-Object { "$_".Trim() } }
}
function Invoke-Query([string]$sql) {
  & "$PgBin\psql.exe" -h localhost -p $Port -U postgres -d postgres -X -q -t -A -c $sql
}

if (Test-Path $data) { Remove-Item -Recurse -Force $data }
& "$PgBin\initdb.exe" -D $data -U postgres -A trust -E UTF8 --locale=C | Out-Null
# Start detached (pg_ctl -w with a captured pipe hangs on Windows), then poll.
Start-Process -FilePath "$PgBin\pg_ctl.exe" -WindowStyle Hidden `
  -ArgumentList @('-D', "`"$data`"", '-l', "`"$log`"", '-o', "`"-p $Port -c listen_addresses=localhost`"", 'start')
$ready = $false
for ($i = 0; $i -lt 60 -and -not $ready; $i++) {
  Start-Sleep -Milliseconds 500
  & "$PgBin\pg_isready.exe" -h localhost -p $Port -q; $ready = ($LASTEXITCODE -eq 0)
}
if (-not $ready) { throw "local PostgreSQL did not start; see $log" }
try {
  Invoke-Sql (Join-Path $repo 'tests\local\supabase-standin.sql') -Quiet
  # Applied migrations in order. Skipped: the pgtap-extension line (the shim
  # replaces it) and rev 9 (AI pilot: it requires the owner's real account).
  # Migrations that are copies of reviewed drafts in docs/database are applied
  # (and rolled back) explicitly below instead.
  $drafts = Get-ChildItem (Join-Path $repo 'docs\database') -Filter 'rev*.sql' | ForEach-Object { (Get-Content $_.FullName -Raw).Trim() }
  Get-ChildItem (Join-Path $repo 'supabase\migrations') -Filter *.sql | Sort-Object Name | ForEach-Object {
    $body = Get-Content $_.FullName -Raw
    if ($body -match 'create extension if not exists pgtap' -and $body.Length -lt 200) { return }
    if ($body -match 'ai_pilot_settings') { return }
    if ($drafts -contains $body.Trim()) { return }
    Invoke-Sql $_.FullName -Quiet
  }
  Invoke-Sql (Join-Path $repo 'tests\local\pgtap-shim.sql') -Quiet
  # Self-check: the shim must report deliberate failures as failures.
  $self = Invoke-Query "begin; select tap.no_plan(); select tap.is(1, 2, 'x'); select tap.ok(false, 'x'); select tap.throws_ok('select 1', '42501', null, 'x'); select tap.lives_ok('select 1/0', 'x'); select tap.throws_ok('select 1/0', '22012', null, 'x'); rollback;"
  if ((@($self) -match '^not ok').Count -ne 4 -or (@($self) -match '^ok ').Count -ne 1) { $self | Write-Host; throw 'tap shim self-check failed' }
  Write-Host 'tap shim self-check: deliberate failures detected: OK'
  $before = Invoke-Query "select count(*) from pg_tables where schemaname='public'"

  $db = Join-Path $repo 'docs\database'
  $tests = Join-Path $repo 'supabase\tests'
  $results = @()
  function Show-Summary($label, $out) { Write-Host "== $label"; ($out | Where-Object { $_ -match '^not ok|^#' }) | Write-Host }

  # Draft revisions in order: migration, its tests, its rollback.
  $revs = @(
    @{ name = 'rev10'; sql = 'rev10-cases.sql';               test = 'rev10-cases.test.sql';               rollback = 'rev10-rollback.sql' },
    @{ name = 'rev11'; sql = 'rev11-case-workspace.sql';      test = 'rev11-case-workspace.test.sql';      rollback = 'rev11-rollback.sql' },
    @{ name = 'rev12'; sql = 'rev12-categories-followups.sql'; test = 'rev12-categories-followups.test.sql'; rollback = 'rev12-rollback.sql' },
    @{ name = 'rev13'; sql = 'rev13-my-work.sql';             test = 'rev13-my-work.test.sql';             rollback = 'rev13-rollback.sql' },
    @{ name = 'rev14'; sql = 'rev14-evidence.sql';            test = 'rev14-evidence.test.sql';            rollback = 'rev14-rollback.sql' },
    @{ name = 'rev14b'; sql = 'rev14b-evidence-storage.sql';  test = 'rev14b-evidence-storage.test.sql';   rollback = 'rev14b-rollback.sql' },
    @{ name = 'rev15'; sql = 'rev15-letters.sql';             test = 'rev15-letters.test.sql';             rollback = 'rev15-rollback.sql' },
    @{ name = 'rev15b'; sql = 'rev15b-branding-storage.sql';  test = 'rev15b-branding-storage.test.sql';   rollback = 'rev15b-rollback.sql' },
    @{ name = 'rev16'; sql = 'rev16-knowledge-model.sql';     test = 'rev16-knowledge-model.test.sql';     rollback = 'rev16-rollback.sql' },
    @{ name = 'rev17'; sql = 'rev17-case-plans-tasks.sql';    test = 'rev17-case-plans-tasks.test.sql';    rollback = 'rev17-rollback.sql' },
    @{ name = 'rev18'; sql = 'rev18-proof-of-service.sql';    test = 'rev18-proof-of-service.test.sql';    rollback = 'rev18-rollback.sql' },
    @{ name = 'rev19'; sql = 'rev19-lead-officer-and-council-approval.sql'; test = 'rev19-lead-officer-and-council-approval.test.sql'; rollback = 'rev19-rollback.sql' },
    @{ name = 'rev20'; sql = 'rev20-products-and-access.sql'; test = 'rev20-products-and-access.test.sql'; rollback = 'rev20-rollback.sql' },
    @{ name = 'rev21'; sql = 'rev21-vectovia-setup.sql'; test = 'rev21-vectovia-setup.test.sql'; rollback = 'rev21-rollback.sql' },
    @{ name = 'rev22'; sql = 'rev22-vectovia-fieldwork.sql'; test = 'rev22-vectovia-fieldwork.test.sql'; rollback = 'rev22-rollback.sql' },
    @{ name = 'rev23'; sql = 'rev23-vectovia-attachments.sql'; test = 'rev23-vectovia-attachments.test.sql'; rollback = 'rev23-rollback.sql' },
    @{ name = 'rev23b'; sql = 'rev23b-vectovia-storage.sql'; test = 'rev23b-vectovia-storage.test.sql'; rollback = 'rev23b-rollback.sql' },
    @{ name = 'rev24'; sql = 'rev24-vectovia-results-risk.sql'; test = 'rev24-vectovia-results-risk.test.sql'; rollback = 'rev24-rollback.sql' },
    @{ name = 'rev25'; sql = 'rev25-vectovia-library.sql'; test = 'rev25-vectovia-library.test.sql'; rollback = 'rev25-rollback.sql' },
    @{ name = 'rev25b'; sql = 'rev25b-vectovia-library-storage.sql'; test = 'rev25b-vectovia-library-storage.test.sql'; rollback = 'rev25b-rollback.sql' },
    @{ name = 'rev26'; sql = 'rev26-vectovia-incursions.sql'; test = 'rev26-vectovia-incursions.test.sql'; rollback = 'rev26-rollback.sql' },
    @{ name = 'rev27'; sql = 'rev27-vectovia-exports-links.sql'; test = 'rev27-vectovia-exports-links.test.sql'; rollback = 'rev27-rollback.sql' },
    @{ name = 'rev28'; sql = 'rev28-invitation-emails.sql'; test = 'rev28-invitation-emails.test.sql'; rollback = 'rev28-rollback.sql' }
  ) | Where-Object { Test-Path (Join-Path $db $_.sql) }
  $fnHash = "select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'"

  for ($i = 0; $i -lt $revs.Count; $i++) {
    $rev = $revs[$i]
    $fnBefore = Invoke-Query $fnHash
    Invoke-Sql "$db\$($rev.sql)" -Quiet
    $r = Invoke-Sql "$tests\$($rev.test)"; Show-Summary "$($rev.name) tests" $r; $results += $r
    if ($i -gt 0) {
      # Rolling back must restore the previous revision exactly, and its tests must pass again.
      Invoke-Sql "$db\$($rev.rollback)" -Quiet
      $same = (Invoke-Query $fnHash) -eq $fnBefore
      Write-Host ("$($rev.name) rollback restores every $($revs[$i-1].name) function exactly: {0}" -f $(if ($same) { 'OK' } else { 'MISMATCH' }))
      if (-not $same) { $results += "not ok - $($rev.name) rollback function mismatch" }
      $r = Invoke-Sql "$tests\$($revs[$i-1].test)"; Show-Summary "$($revs[$i-1].name) tests again after $($rev.name) rollback" $r; $results += $r
      Invoke-Sql "$db\$($rev.sql)" -Quiet
    }
  }

  # Vectovia V7 proof: whole workflow in two councils, then isolation by table sweep and direct requests.
  $proof = Join-Path $tests 'v7-vectovia-proof.test.sql'
  if (Test-Path $proof) { $r = Invoke-Sql $proof; Show-Summary 'V7 Vectovia proof' $r; $results += $r }

  Write-Host '== full rollback check'
  for ($i = $revs.Count - 1; $i -ge 0; $i--) { Invoke-Sql "$db\$($revs[$i].rollback)" -Quiet }
  $after = Invoke-Query "select count(*) from pg_tables where schemaname='public'"
  Write-Host ("public tables before rev10: {0}, after rolling everything back: {1} -> {2}" -f $before, $after, $(if ($before -eq $after) { 'OK' } else { 'MISMATCH' }))
  foreach ($rev in $revs) { Invoke-Sql "$db\$($rev.sql)" -Quiet }
  Write-Host 'all revisions re-apply cleanly after rollback: OK'

  if ($results -match '^not ok' -or $before -ne $after) { exit 1 }
} finally {
  Start-Process -FilePath "$PgBin\pg_ctl.exe" -WindowStyle Hidden -Wait -ArgumentList @('-D', "`"$data`"", '-m', 'fast', 'stop')
}
