[CmdletBinding()]
param(
    [string]$Path = '',

    # Scan only git-tracked files (default when inside a git work tree and git is
    # available). This keeps local runs and CI checkout in agreement: CI only
    # checks out tracked files, so untracked docs/.claude/.codex no longer cause a
    # local-only exit 1 while remaining detectable once they are git add-ed.
    [ValidateSet('auto', 'tracked', 'worktree')]
    [string]$ScanMode = 'auto'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Split-Path -Parent $scriptRoot
}

$root = (Resolve-Path -LiteralPath $Path).Path

$ownRepoUrlPattern = '^https://github\.com/h8nc4y/agentic-coding-security-gate(?:\.git)?$'

# Email allowlist: documentation-safe placeholder domains and the npm scope
# marker. Real maintainer addresses must still be flagged.
$emailAllowlistPattern = '@(?:example\.(?:com|org|net)|test|localhost)$'

# Best-effort secret/private-marker rules. This is NOT a guarantee that every
# secret format is caught (see SKILL.md / SECURITY.md). Literal prefixes are
# assembled by concatenation so this scanner file does not self-trigger.
$rules = @(
    # Require a token-like boundary so ordinary words such as codex-task-* do not
    # match the short OpenAI key prefix fragment.
    @{ Name = 'openai-api-key-prefix'; Pattern = ('(?<![A-Za-z0-9_])s' + 'k-[A-Za-z0-9_\-]{16,}'); Kind = 'regex' },
    @{ Name = 'github-classic-token-prefix'; Pattern = ('g' + 'hp_'); Kind = 'literal' },
    @{ Name = 'github-fine-grained-token-prefix'; Pattern = ('github' + '_pat_'); Kind = 'literal' },
    @{ Name = 'slack-bot-token-prefix'; Pattern = ('xo' + 'xb-'); Kind = 'literal' },
    # New (H-B): Slack user/legacy and app-level tokens.
    @{ Name = 'slack-token-prefix'; Pattern = ('xo' + 'x[pab]-'); Kind = 'regex' },
    @{ Name = 'slack-app-token-prefix'; Pattern = ('xa' + 'pp-'); Kind = 'literal' },
    # New (H-B): AWS access key id.
    @{ Name = 'aws-access-key-id'; Pattern = ('AKIA' + '[0-9A-Z]{16}'); Kind = 'regex' },
    # New (H-B): GCP / Google API key.
    @{ Name = 'gcp-api-key'; Pattern = ('AIza' + '[0-9A-Za-z_\-]{35}'); Kind = 'regex' },
    # New (H-D): npm registry auth token assignment with a literal value.
    @{ Name = 'npm-auth-token-assignment'; Pattern = '[_A-Za-z0-9./:-]*_authToken\s*=\s*[A-Za-z0-9._\-]{8,}'; Kind = 'regex' },
    # New (H-D): PyPI API token prefix with a token-length suffix.
    @{ Name = 'python-package-index-token-prefix'; Pattern = ('pypi-' + '[A-Za-z0-9_\-]{16,}'); Kind = 'regex' },
    # New (H-D): RubyGems credentials file assignment with a literal value.
    @{ Name = 'ruby-package-credentials-assignment'; Pattern = (':rubygems_' + 'api_key:\s+[A-Za-z0-9_\-]{8,}'); Kind = 'regex' },
    # New (H-C): Anthropic console/API key prefix and compact JWT-shaped bearer values.
    @{ Name = 'anthropic-api-key-prefix'; Pattern = ('sk-ant-' + '[A-Za-z0-9_\-]{16,}'); Kind = 'regex' },
    @{ Name = 'jwt-token-shape'; Pattern = 'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}'; Kind = 'regex' },
    # New (H-B): Stripe live secret / restricted keys.
    @{ Name = 'stripe-live-key'; Pattern = ('(?:sk|rk)' + '_live_[0-9A-Za-z]{16,}'); Kind = 'regex' },
    # New (H-B): PEM private-key block variants (RSA/EC/OPENSSH/ENCRYPTED + plain).
    @{ Name = 'private-key-block'; Pattern = ('BEGIN ' + '(?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY'); Kind = 'regex' },
    @{ Name = 'bearer-token-header'; Pattern = ('Bearer' + ' [A-Za-z0-9._\-]{8,}'); Kind = 'regex' },
    @{ Name = 'private-inventory-repo'; Pattern = ('h8nc4y' + '/codex-global-context'); Kind = 'literal' },
    @{ Name = 'private-projects-path'; Pattern = ('D:' + '\Agent\Codex\Projects'); Kind = 'literal' },
    @{ Name = 'private-user-path'; Pattern = ('C:' + '\Users\h8nc4'); Kind = 'literal' },
    @{ Name = 'email-address'; Pattern = '\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Kind = 'regex' },
    @{ Name = 'windows-absolute-path'; Pattern = '\b[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\?){2,}'; Kind = 'regex' },
    @{ Name = 'secret-assignment'; Pattern = '\b(?:API_KEY|TOKEN|SECRET|PASSWORD)\s*='; Kind = 'regex' }
)

# Text-only scan: skip binary/large assets so future binary examples (PNG, etc.)
# cannot be line-walked into false positives or slow the scan. Files with no
# extension (LICENSE, etc.) are treated as text.
$textExtensions = @(
    '.md', '.markdown', '.txt', '.ps1', '.psm1', '.psd1', '.yml', '.yaml',
    '.json', '.jsonc', '.js', '.ts', '.py', '.sh', '.cfg', '.ini', '.toml',
    '.editorconfig', '.gitignore', '.gitattributes', '.npmrc', '.xml', '.html', '.css'
)

function Test-IsTextFile {
    param([System.IO.FileInfo]$File)

    $ext = $File.Extension
    if ([string]::IsNullOrEmpty($ext)) {
        return $true
    }

    return $textExtensions -contains $ext.ToLowerInvariant()
}

$githubUrlPattern = 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?'
$findings = New-Object System.Collections.Generic.List[object]

# --- File selection ------------------------------------------------------
# 新H-A: prefer git-tracked files so the local scan target matches what CI
# checks out. Untracked docs/.claude/.codex therefore do not trip the scan, but
# anything that is git add-ed (and would actually be published) is still scanned.
function Get-TrackedFiles {
    param([string]$Root)

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCmd) {
        return $null
    }

    $insideWorkTree = (& git -C $Root rev-parse --is-inside-work-tree 2>$null)
    if ($LASTEXITCODE -ne 0 -or "$insideWorkTree".Trim() -ne 'true') {
        return $null
    }

    # -z gives NUL-separated, untranslated paths (safe for spaces/unicode).
    $raw = & git -C $Root ls-files -z 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $list = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($rel in ($raw -split "`0")) {
        if ([string]::IsNullOrEmpty($rel)) { continue }
        $full = Join-Path $Root $rel
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $list.Add([System.IO.FileInfo]::new($full)) | Out-Null
        }
    }

    return , $list.ToArray()
}

# Exclusions for the work-tree fallback (used only when git is unavailable).
# .claude/.codex are agent-local scratch dirs that git ignores; excluding them
# keeps the fallback consistent with the tracked-file scan and repo .gitignore.
# Note: docs/ is intentionally NOT excluded here so that tracked docs are still
# scanned. The H-A guarantee ("untracked docs do not fail the scan") comes from
# the default tracked-file mode above, not from blanket-excluding docs.
$excludePattern = '\\(?:\.git|node_modules|\.cache|__pycache__|\.test-tmp|\.claude|\.codex)(?:\\|$)'

function Get-WorktreeFiles {
    param([string]$Root)

    return Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
        $_.FullName -notmatch $excludePattern
    }
}

$selectedMode = $ScanMode
$files = $null
if ($ScanMode -in @('auto', 'tracked')) {
    $files = Get-TrackedFiles -Root $root
    if ($null -ne $files) {
        $selectedMode = 'tracked'
    } elseif ($ScanMode -eq 'tracked') {
        Write-Error 'git-tracked scan requested but git is unavailable or the path is not a git work tree.'
        exit 2
    }
}

if ($null -eq $files) {
    $files = Get-WorktreeFiles -Root $root
    $selectedMode = 'worktree'
}

$files = @($files | Where-Object { Test-IsTextFile -File $_ })

foreach ($file in $files) {
    $relative = $file.FullName
    if ($relative.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $relative.Substring($root.Length).TrimStart([char]92)
    }
    $relative = $relative.Replace([string][char]92, '/')
    $lineNumber = 0

    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $lineNumber++
        foreach ($match in [regex]::Matches($line, $githubUrlPattern)) {
            if ($match.Value -notmatch $ownRepoUrlPattern) {
                $findings.Add([pscustomobject]@{
                    File = $relative
                    Line = $lineNumber
                    Rule = 'non-allowlisted-github-repo-url'
                    Value = '<redacted>'
                }) | Out-Null
            }
        }

        foreach ($rule in $rules) {
            $matched = $false
            if ($rule.Kind -eq 'literal') {
                $matched = $line.Contains($rule.Pattern)
            } else {
                $matched = [regex]::IsMatch($line, $rule.Pattern, 'IgnoreCase')
            }

            # Suppress documentation-safe placeholder emails (example.com etc.).
            if ($matched -and $rule.Name -eq 'email-address') {
                $hasRealEmail = $false
                foreach ($emailMatch in [regex]::Matches($line, $rule.Pattern, 'IgnoreCase')) {
                    if ($emailMatch.Value -notmatch $emailAllowlistPattern) {
                        $hasRealEmail = $true
                        break
                    }
                }
                $matched = $hasRealEmail
            }

            if ($matched) {
                $findings.Add([pscustomobject]@{
                    File = $relative
                    Line = $lineNumber
                    Rule = $rule.Name
                    Value = '<redacted>'
                }) | Out-Null
            }
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Host "Private marker scan failed (mode: $selectedMode). Values are redacted:"
    $findings | Sort-Object File, Line, Rule | Format-Table -AutoSize
    Write-Host ("{0} finding(s) across {1} scanned file(s)." -f $findings.Count, $files.Count)
    exit 1
}

Write-Host "Private marker scan passed for $root (mode: $selectedMode, $($files.Count) file(s))"
