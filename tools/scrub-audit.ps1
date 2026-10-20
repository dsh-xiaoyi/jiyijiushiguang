# scrub-audit.ps1 - refuse to publish anything that looks like a secret or a real environment
#
# Run this before every commit. It exits non-zero when something suspicious is found, and git hooks /
# CI use that exit code as the gate. False positives are expected and are handled by allow-listing a
# *pattern*, never by allow-listing a secret value.
#
# Usage:
#   powershell -File tools/scrub-audit.ps1              # scan the whole repo
#   powershell -File tools/scrub-audit.ps1 -Path bridge # scan one folder
#   powershell -File tools/scrub-audit.ps1 -Quiet       # only the summary
#
# Exit codes: 0 = clean, 1 = findings, 2 = scan error.
param(
    [string]$Path = '',
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Path) { $Path = $repoRoot }
$target = if (Test-Path $Path) { (Resolve-Path $Path).Path } else { throw "path not found: $Path" }

# Files we never scan (binary / generated / vendored / this detector itself)
$skipDirNames = @('.git', 'node_modules', '.pnpm-store', 'dist', 'build', '.venv')
$skipFiles = @('scrub-audit.ps1')
$textExt = @('.md', '.txt', '.ps1', '.psm1', '.js', '.mjs', '.cjs', '.ts', '.json', '.yml', '.yaml',
             '.sql', '.cs', '.py', '.cmd', '.bat', '.sh', '.gitignore', '.example', '.tmpl', '.config')

# (name, regex, why, allowWhenLineMentions)
$rules = @(
    @{ n = 'private-key';      r = '-----BEGIN [A-Z ]*PRIVATE KEY-----'; w = 'private key material'; a = 'never' },
    @{ n = '64-hex-token';     r = '(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])'; w = 'looks like a 32-byte token'; a = '<PAIR-TOKEN|<TOKEN|example|placeholder' },
    @{ n = 'long-hex-32+';     r = '(?<![0-9a-fA-F])[0-9a-fA-F]{32,}(?![0-9a-fA-F])'; w = 'looks like a hash or key'; a = 'sha256|sha1|md5|hash|example|placeholder' },
    @{ n = 'secret-assign';    r = '(?i)(password|passwd|pwd|secret|token|api[_-]?key|apikey|auth[_-]?code)\s*[=:]\s*["'']?[^\s"'',}]{6,}'; w = 'hard-coded credential assignment'; a = '<PASSWORD|<TOKEN|<SECRET|placeholder|example|xxx|your_' },
    @{ n = 'email-address';    r = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'; w = 'real e-mail address'; a = 'example\.(com|org)|@example|noreply|users\.noreply\.github\.com|<EMAIL>' },
    @{ n = 'qq-or-long-digits';r = '(?<![0-9])[1-9][0-9]{7,11}(?![0-9])'; w = 'looks like a QQ number, phone or account id'; a = 'port|version|timeout|id\s*=|order|invoice|example|placeholder|202[0-9]|19[0-9]{2}' },
    @{ n = 'private-ip';       r = '\b(?:10|192\.168|172\.(?:1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b'; w = 'real private IP'; a = '10\.0\.0\.x|192\.168\.x\.x|example|placeholder|<IP>' },
    @{ n = 'unc-or-real-user'; r = '(?i)\\\\[A-Za-z0-9_-]+\\[A-Za-z0-9_-]+|C:\\Users\\[A-Za-z0-9_.-]+'; w = 'real machine or user path'; a = '<DSH_HOME|C:\\\\Users\\\\<|example|placeholder' },
    @{ n = 'dsh-home-path';    r = '(?i)\.dsh\\profiles\\[A-Za-z0-9_.-]+'; w = 'real profile path'; a = '<PROFILE>|<DSH_HOME>' }
)

$files = Get-ChildItem -Path $target -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $p = $_.FullName
    ($skipDirs | Where-Object { $p -match $_ }).Count -eq 0 -and
    ($textExt -contains $_.Extension.ToLower() -or $_.Name -in @('.gitignore', 'LICENSE', 'README'))
}

$findings = New-Object System.Collections.Generic.List[object]
foreach ($f in $files) {
    $rel = $f.FullName.Replace($repoRoot, '').TrimStart('\')
    $lines = @()
    try { $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8) } catch { continue }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        foreach ($rule in $rules) {
            if ($line -match $rule.r) {
                if ($rule.a -ne 'never' -and $line -match $rule.a) { continue }
                if ($rule.a -eq 'never') { }
                $findings.Add([pscustomobject]@{
                    File   = $rel
                    Line   = $i + 1
                    Rule   = $rule.n
                    Why    = $rule.w
                    Snippet = ($line.Trim() -replace '\s+', ' ')
                })
            }
        }
    }
}

# never print the matched text for secret-ish rules; show a masked preview only
function Mask([string]$s) {
    if ($s.Length -le 12) { return '***' }
    return $s.Substring(0, 4) + '…' + $s.Substring($s.Length - 4)
}

Write-Output '=== scrub-audit ==='
Write-Output ('target : ' + $target)
Write-Output ('files  : ' + $files.Count)
Write-Output ''

if ($findings.Count -eq 0) {
    Write-Output 'RESULT: CLEAN - nothing that looks like a secret, a real host or real user data.'
    exit 0
}

$byRule = $findings | Group-Object Rule | Sort-Object Count -Descending
foreach ($g in $byRule) {
    Write-Output ('[' + $g.Name + '] ' + $g.Count + ' hit(s)  - ' + $g.Group[0].Why)
    if (-not $Quiet) {
        foreach ($x in ($g.Group | Select-Object -First 5)) {
            Write-Output ('    ' + $x.File + ':' + $x.Line + '   ' + (Mask $x.Snippet))
        }
        if ($g.Count -gt 5) { Write-Output ('    … ' + ($g.Count - 5) + ' more') }
    }
}
Write-Output ''
Write-Output ('RESULT: ' + $findings.Count + ' finding(s) in ' + ($findings | Group-Object File).Count + ' file(s) - DO NOT COMMIT until these are placeholders.')
Write-Output 'Fix by replacing values with placeholders (<TOKEN>, HOST-A, 10.0.0.x, <DSH_HOME>),'
Write-Output 'never by adding the secret to an allow-list.'
exit 1
