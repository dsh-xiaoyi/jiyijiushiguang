# 2026-10-25 release gate: run before publishing; must pass before review
param([string]$Root = 'C:\dsh-mem\_deliver\dsh-memory-bridge-v0.5.0')
$script:fail = 0
function Say([string]$m) { Write-Host $m }
Say '--- G1 markers extracted mechanically'
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'ops\gen-fix-markers.ps1') -Root $Root 2>&1
$out | ForEach-Object { Say ('    ' + $_) }
if ($LASTEXITCODE -ne 0) { Say '  FAIL markers missing'; $script:fail++ } else { Say '  PASS markers ok' }
Say '--- G2 exactly one live artifact'
$live = @(Get-ChildItem 'C:\dsh-mem\_deliver' -Filter '*.zip' | Where-Object { $_.Name -notmatch 'SUPERSEDED' })
if ($live.Count -eq 1) { Say ('  PASS live: ' + $live[0].Name) } else { Say ('  FAIL live count=' + $live.Count); $script:fail++ }
Say '--- G3 filename sha16 matches content'
if ($live.Count -eq 1) {
    $hFull = (Get-FileHash $live[0].FullName -Algorithm SHA256).Hash
    $h = $hFull.Substring(0,16)
    if ($live[0].Name.Contains($h)) { Say ('  PASS pkg sha256(full) = ' + $hFull); Say ('       (filename carries first 16 = ' + $h + '; reconciliation MUST use the full 64)') } else { Say ('  FAIL name lacks ' + $h + ' full=' + $hFull); $script:fail++ }
}
Say '--- G4 required files present'
foreach ($p in @('plugin\index.mjs','plugin\package.json','plugin\CHANGELOG.md','FIX-MARKERS.txt','SHA256SUMS.txt','sql\020-memory-status-audit.sql','ops\gen-fix-markers.ps1')) {
    if (Test-Path (Join-Path $Root $p)) { Say ('  OK ' + $p) } else { Say ('  FAIL missing ' + $p); $script:fail++ }
}
Say '--- G5 node --check'
$null = & node --check (Join-Path $Root 'plugin\index.mjs') 2>&1
if ($LASTEXITCODE -eq 0) { Say '  PASS' } else { Say '  FAIL syntax'; $script:fail++ }

Say '--- G6 tail build must be self-hashed (no hand-written build id)'
$mdlPath = Join-Path $Root 'plugin\index.mjs'
$mdl = [System.IO.File]::ReadAllText($mdlPath, [System.Text.Encoding]::UTF8)
$sha8 = (Get-FileHash $mdlPath -Algorithm SHA256).Hash.Substring(0,8).ToUpper()
if ($mdl -match 'injector=0\.5\.0-[0-9A-Fa-f]{8}') { Say '  FAIL tail build looks like a hand-written literal'; $script:fail++ }
elseif ($mdl -notmatch 'SELF_BUILD') { Say '  FAIL SELF_BUILD not found'; $script:fail++ }
elseif ($mdl -notmatch 'readFileSync\(new URL\(import\.meta\.url\)\)') { Say '  FAIL self-hash source (readFileSync(new URL(import.meta.url))) missing'; $script:fail++ }
else {
    Say ('  PASS build is computed; expected tail build = ' + $sha8)
    $shaFull = (Get-FileHash $mdlPath -Algorithm SHA256).Hash
    Say ('       file:index.mjs full sha256 = ' + $shaFull)
    Say '       rule: tail build must NOT be UNKNOWN (UNKNOWN = self-hash failed = FAIL)'
}

Say ''
if ($script:fail -eq 0) { Say 'RESULT: PASS'; exit 0 }
Say ('RESULT: FAIL ' + $script:fail); exit 1
