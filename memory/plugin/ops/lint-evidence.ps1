param([string]$Path, [switch]$SelfTest)
$ErrorActionPreference = 'Continue'
# 2026-10-25 证据行 lint：回指不算证据；且证据行必须带「值 + 层级 + 时刻」
# 适用范围**仅限证据行**（避免重演 CONVENTIONS-IDENTITY-CONFLICT 的每轮 100% 误报）

$backref = '见上|如前所述|同上|as reported|see above|reported above'
# 证据行判定（收紧）：命中其一才算证据行；markdown 结构行（|、#、>、```、-、*）一律 SKIP
$evidence = '^\s*EVIDENCE:|^\s*VERDICT|(pkg:|file:|conv:|doc:|tail-build).*(sha256|[0-9A-Fa-f]{64}|INJECT-)'
$structural = '^\s*(\||#|>|```|-\s|\*\s)'
$hasValue = '[0-9A-Fa-f]{64}|[0-9a-f]{40}|INJECT-[A-Z]|conventions@'
$hasLevel = 'pkg:|file:|conv:|doc:|tail-build'
$hasTime  = '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}|\d{2}:\d{2}:\d{2}'

function Test-EvidenceLine([string]$line) {
    if ($line -match $structural) { return @{ Verdict = 'SKIP'; Reason = '结构行（表格/标题/代码围栏/列表）' } }
    $isEvidence = $line -match $evidence
    if (-not $isEvidence) { return @{ Verdict = 'SKIP'; Reason = '非证据行（叙述性）' } }
    $isBackref = $line -match $backref
    $v = $line -match $hasValue
    $l = $line -match $hasLevel
    $t = $line -match $hasTime
    if ($isBackref -and (-not $v)) {
        return @{ Verdict = 'FAIL'; Reason = '回指且无值' }
    }
    $missing = @()
    if (-not $v) { $missing += 'value' }
    if (-not $l) { $missing += 'level' }
    if (-not $t) { $missing += 'time' }
    if ($missing.Count -gt 0) {
        return @{ Verdict = 'FAIL'; Reason = ('缺 ' + ($missing -join '/')) }
    }
    return @{ Verdict = 'PASS'; Reason = '值+层级+时刻齐全' }
}

if ($SelfTest) {
    $bad = 0
    $cases = @(
        @{ line = 'EVIDENCE: pkg: 见上一条，值不重复'; expect = 'FAIL'; why = '回指+无值' },
        @{ line = '流程说明：重启见上一条，按 §3 执行'; expect = 'SKIP'; why = '叙述行，不该报' },
        @{ line = 'EVIDENCE: file:index.mjs:5DDAF76220108E2218ECBF1D29347DE6C99DDC124A92A8AFE988B31E3D773E63 at 2026-10-25T01:02:09'; expect = 'PASS'; why = '值+层级+时刻' }
    )
    foreach ($c in $cases) {
        $r = Test-EvidenceLine $c.line
        if ($r.Verdict -eq $c.expect) { Write-Host ('  PASS case(' + $c.why + ') → ' + $r.Verdict) }
        else { Write-Host ('  FAIL case(' + $c.why + ') expect=' + $c.expect + ' got=' + $r.Verdict + ' reason=' + $r.Reason); $bad++ }
    }
    if ($bad -eq 0) { Write-Host 'SELFTEST: PASS (3/3)'; exit 0 }
    Write-Host ('SELFTEST: FAIL ' + $bad); exit 1
}

if (-not $Path -or -not (Test-Path $Path)) {
    Write-Host 'RESULT: FAIL 1（未指定 -Path，或文件不存在）'
    exit 1
}
$lines = Get-Content -LiteralPath $Path -Encoding UTF8
$fail = 0; $pass = 0; $skip = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    $r = Test-EvidenceLine $lines[$i]
    switch ($r.Verdict) {
        'PASS' { $pass++ }
        'SKIP' { $skip++ }
        'FAIL' { $fail++; Write-Host ('  L' + ($i + 1) + ' FAIL(' + $r.Reason + '): ' + $lines[$i].Trim()) }
    }
}
Write-Host ('evidence pass=' + $pass + ' fail=' + $fail + ' skip=' + $skip)
if ($fail -gt 0) { Write-Host ('RESULT: FAIL ' + $fail); exit 1 }
Write-Host 'RESULT: PASS'; exit 0
