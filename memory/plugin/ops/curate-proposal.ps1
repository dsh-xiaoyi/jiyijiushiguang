param(
    [int]$EvidenceDays = 7,
    [int]$MaxEvidence = 20,
    [int]$Neighbours = 3,
    [string]$OutDir = 'C:\dsh-mem\reports',
    [string]$VectorFile = 'C:\dsh-mem\mem-vectors.bin',
    [string]$OllamaUrl = 'http://127.0.0.1:11434',
    [string]$Model = 'bge-m3'
)
# 2026-10-24 C3 后续：curator 的"只提案"版本。
# 读最近的 evidence（会话压缩摘要）+ 与之最相近的既有记忆，产出一份**人类可读的提案报告**。
# 绝对不写数据库：所有候选操作只写进报告文件，等主人（或小易审核后）决定。
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Data
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$report = Join-Path $OutDir ('curate-proposal-' + $stamp + '.md')

$cfg = ([System.IO.File]::ReadAllText('C:\dsh-mem\dsh-mem.config.json', [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
$cs = 'Server=' + $cfg.server + ';Database=' + $cfg.database + ';User Id=' + $cfg.user + ';Password=' + $cfg.password + ';TrustServerCertificate=True;Connect Timeout=20'
$c = New-Object System.Data.SqlClient.SqlConnection $cs
$c.Open()

function Rows([string]$sql) {
    $q = $c.CreateCommand(); $q.CommandText = $sql
    $dt = New-Object System.Data.DataTable; $dt.Load($q.ExecuteReader()); return $dt
}

$since = (Get-Date).AddDays(-$EvidenceDays).ToString('yyyy-MM-dd HH:mm:ss')
$ev = Rows ("SELECT TOP ($MaxEvidence) id, title, LEFT(body, 600) AS body, created_at FROM dbo.memories WHERE kind='evidence' AND created_at >= '$since' ORDER BY id DESC")
$mem = Rows "SELECT id, kind, title, LEFT(body, 400) AS body, status FROM dbo.memories WHERE ISNULL(status,'current')='current' AND kind NOT IN ('evidence','checkpoint','llm-call') ORDER BY id DESC"
$c.Close()

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# curator 提案报告（只提案，不改库）')
$lines.Add('')
$lines.Add('生成时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ｜ 证据窗口：近 ' + $EvidenceDays + ' 天 ｜ 证据条数：' + $ev.Rows.Count)
$lines.Add('')
$lines.Add('> 说明：本报告只列出"建议动作"，**没有对数据库做任何修改**。')
$lines.Add('> 动作语义：ADD=建议新增记忆 ｜ MERGE=与既有条目合并 ｜ NOOP=无需入记忆（寒暄/临时） ｜ SUPERSEDE=建议取代旧条目')
$lines.Add('')

if ($ev.Rows.Count -eq 0) {
    $lines.Add('（窗口内没有 evidence 记录 —— 说明最近没有发生会话压缩，或捕获未生效。）')
} else {
    $i = 0
    foreach ($e in $ev.Rows) {
        $i++
        $lines.Add('## 证据 ' + $i + '：id=' + $e.id + ' ｜ ' + ([string]$e.title).Trim())
        $lines.Add('')
        $lines.Add('- 时间：' + ([datetime]$e.created_at).ToLocalTime().ToString('yyyy-MM-dd HH:mm'))
        $lines.Add('- 摘要（前 300 字）：' + ((([string]$e.body) -replace '\s+', ' ').Substring(0, [Math]::Min(300, (([string]$e.body) -replace '\s+', ' ').Length))))
        # 简单相近度：标题/正文关键词重叠（够用且可解释；不用向量以免再依赖 Ollama 可用性）
        $etxt = (([string]$e.title) + ' ' + ([string]$e.body)).ToLower()
        $cand = @()
        foreach ($m in $mem.Rows) {
            $mtxt = (([string]$m.title) + ' ' + ([string]$m.body)).ToLower()
            $score = 0
            foreach ($w in @(($etxt -split '[^\u4e00-\u9fa5a-z0-9]+') | Where-Object { $_.Length -ge 3 } | Select-Object -Unique | Select-Object -First 40)) {
                if ($mtxt.Contains($w)) { $score++ }
            }
            if ($score -gt 0) { $cand += [pscustomobject]@{ id = $m.id; title = $m.title; kind = $m.kind; score = $score } }
        }
        $top = @($cand | Sort-Object -Property score -Descending | Select-Object -First $Neighbours)
        if ($top.Count -eq 0) {
            $lines.Add('- 相关既有记忆：无（可能是全新事实 → 建议动作 **ADD**）')
        } else {
            $lines.Add('- 相关既有记忆（重叠词数）：')
            foreach ($t in $top) { $lines.Add('    - [' + $t.id + '] (' + $t.kind + ') ' + $t.title + '  ← 重叠 ' + $t.score) }
            $lines.Add('- 建议动作：**MERGE**（与上面第一条合并）或 **NOOP**（若只是过程记录）')
        }
        $lines.Add('- 需要主人/小易决定：这条证据里有没有"值得长期记住的结论"？')
        $lines.Add('')
    }
}
$lines.Add('---')
$lines.Add('')
$lines.Add('## 如何执行（人工确认后）')
$lines.Add('')
$lines.Add('```powershell')
$lines.Add('# 新增一条记忆（示例）')
$lines.Add('powershell -File C:\dsh-mem\dsh-mem.ps1 save -Title "…" -Body "…" -Kind decision -Subject ORCHESTRATOR')
$lines.Add('')
$lines.Add('# 取代旧条目（先人工确认，再改状态；不会物理删除）')
$lines.Add('sqlcmd -S 127.0.0.1 -E -d DSHMemory -Q "UPDATE dbo.memories SET status=''superseded'', replaced_by=<新id>, valid_to=SYSUTCDATETIME() WHERE id=<旧id>; INSERT INTO dbo.memory_events(memory_id,action,actor_machine,reason) VALUES(<旧id>,''supersede'',''<机器>'',''curator 提案人工确认'');"')
$lines.Add('```')
[System.IO.File]::WriteAllText($report, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
Write-Output ('proposal -> ' + $report)
Write-Output ('evidence=' + $ev.Rows.Count + '  candidate memories=' + $mem.Rows.Count)
