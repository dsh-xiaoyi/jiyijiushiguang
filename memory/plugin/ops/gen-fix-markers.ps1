# 2026-10-25 FIX-MARKERS 机械抽取（禁止手抄；候选串只放"存在于交付包内"的标记）
# 用法: powershell -File gen-fix-markers.ps1 [-Root <交付目录>]
param([string]$Root = 'C:\dsh-mem\_deliver\dsh-memory-bridge-v0.5.0')

$candidates = @(
    'INJECT-TOTAL-TRIM','budgetScale','SEMANTIC-BACKOFF','PATH-RESOLVED','pickExisting',
    'CONVENTIONS-POINTER-MISSING','INJECT-CONFIG-FAIL','INJECT-TAIL','INJECT-DEGRADED','INJECT-EFFCONFIG','INJECT-TAIL-LOST','SELF_ID','CONVENTIONS-IDENTITY-CONFLICT','INJECT-SELFID','INJECT-SELFID-FAIL','INJECT-EFFCONFIG-FAIL','SELF_BUILD',
    'conventions@','DB_NAME()','BEGIN TRAN','XACT_ABORT','USERPROFILE',
    'cordis.patch.G_deepseek.yml','REQUIRED_MIN'
)

$exts = @('.mjs','.ps1','.sql','.yml','.json','.md','.txt')
$files = @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $exts -contains $_.Extension.ToLower() -and $_.Name -ne 'gen-fix-markers.ps1' -and $_.Name -ne 'FIX-MARKERS.txt' })

$map = @{}
foreach ($f in $files) {
    $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    foreach ($c in $candidates) {
        if ($txt.Contains($c)) {
            if (-not $map.ContainsKey($c)) { $map[$c] = New-Object System.Collections.Generic.List[string] }
            $rel = $f.FullName.Substring($Root.Length + 1)
            if (-not $map[$c].Contains($rel)) { $map[$c].Add($rel) }
        }
    }
}

# 负向对照（拼出来，避免自身命中原串）
$neg = '__NEG_' + 'CONTROL_MUST_NOT_EXIST__'
$negHit = $false
foreach ($f in $files) { if ([System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8).Contains($neg)) { $negHit = $true } }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# FIX-MARKERS（由 ops\gen-fix-markers.ps1 机械抽取，勿手改）')
$lines.Add('# 格式: 标记串 | 所在文件；缺任何一条即构建失败')
$lines.Add('')
$missing = @()
foreach ($c in $candidates) {
    if ($map.ContainsKey($c)) { $lines.Add($c + ' | ' + (($map[$c] | Sort-Object) -join ', ')) } else { $missing += $c }
}
$outFile = Join-Path $Root 'FIX-MARKERS.txt'
[System.IO.File]::WriteAllLines($outFile, $lines, (New-Object System.Text.UTF8Encoding $false))

Write-Host ('scanned files: ' + $files.Count)
Write-Host ('written: ' + $outFile)
Write-Host ('markers found: ' + ($candidates.Count - $missing.Count) + '/' + $candidates.Count)
if ($negHit) { Write-Host 'NEGATIVE-CONTROL: FAIL（占位串竟然存在）'; Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'NEGATIVE-CONTROL: PASS（占位串确实不存在，抽取逻辑有效）'
if ($missing.Count -gt 0) { Write-Host ('MISSING: ' + ($missing -join ', ')); Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0
