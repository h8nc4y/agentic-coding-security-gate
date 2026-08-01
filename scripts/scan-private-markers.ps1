[CmdletBinding()]
param(
    [string]$Path = '',

    [string]$ScanMode = 'auto',

    # テストでは下げられるが、本番既定値より上げられない全体deadline。
    [string]$ScanDeadlineMilliseconds = '120000',

    # Boundary self-test専用。未知entryを作り、cleanupが再帰せず固定理由で
    # fail-closedになることを実測する。通常呼出しでは指定しない。
    [Parameter(DontShow = $true)]
    [switch]$TestOnlyCreateCleanupUnknownEntry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$runtimeIsWindows = [Environment]::OSVersion.Platform -eq
    [PlatformID]::Win32NT
$scanStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# bootstrapを含む曖昧な入力はclean扱いせず、固定codeだけを出す。
function Stop-ScanIntegrityFailure {
    param([string]$Reason)

    # raw exception、local path、Git stderr、config/blob内容は一切再生しない。
    Write-Host "Private marker scan failed closed (integrity: $Reason)."
    exit 2
}

$parsedScanDeadlineMilliseconds = 0
if ($ScanMode -notin @('auto', 'tracked', 'worktree') -or
    -not [int]::TryParse(
        $ScanDeadlineMilliseconds,
        [Globalization.NumberStyles]::None,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsedScanDeadlineMilliseconds
    ) -or
    $parsedScanDeadlineMilliseconds -lt 1 -or
    $parsedScanDeadlineMilliseconds -gt 120000) {
    Stop-ScanIntegrityFailure -Reason 'argument-validation'
}
$ScanDeadlineMilliseconds = $parsedScanDeadlineMilliseconds

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
try {
    $processSupport = Join-Path $scriptRoot 'private-marker-process.ps1'
    if (-not (Test-Path -LiteralPath $processSupport -PathType Leaf)) {
        Stop-ScanIntegrityFailure -Reason 'process-boundary-setup'
    }
    . $processSupport
}
catch {
    Stop-ScanIntegrityFailure -Reason 'process-boundary-setup'
}

if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Split-Path -Parent $scriptRoot
}

$root = $Path
# このリポジトリ自身だけを公開URLとして許可し、別リポジトリは必ず検出する。
$ownRepoUrlPattern = '^https://github\.com/h8nc4y/agentic-coding-security-gate(?:\.git)?$'
$maxGitMetadataBytes = 16777216
$maxTextFileBytes = 8388608
$maxTotalScanBytes = 67108864
$maxGitDiagnosticBytes = 262144
$maxGitIndexEntries = 4096
$maxGitProcesses = 7
$maxFindings = 100
$maxFindingOutputBytes = 16384
$maxDisplayPathCharacters = 2048
$maxScanTargets = 8192
$maxWorkingTreeEntries = 32768
$maxScanLines = 1000000
$maxRegexMatches = 100000
$maxGitPathCharacters = 32768
$maxGitPathSegments = 1024
$totalScanBytes = 0L
$gitProcessCount = 0
$workingTreeEntryCount = 0
$totalScanLines = 0
$regexMatchCount = 0
$regexTimeout = [TimeSpan]::FromSeconds(2)

$rules = New-Object System.Collections.Generic.List[object]

# 検出規則は名前・種類・allowlistを構造化し、報告へ生値を渡さない。
function Add-ScanRule {
    param(
        [string]$Name,
        [string]$Pattern,
        [ValidateSet('literal', 'regex')]
        [string]$Kind,
        # Optional: suppress regex matches whose value is a known-safe placeholder.
        # This keeps documentation examples from becoming noisy findings.
        [string]$Allowlist = ''
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        return
    }

    $rules.Add([pscustomobject]@{
        Name = $Name
        Pattern = $Pattern
        Kind = $Kind
        Allowlist = $Allowlist
        Regex = if ($Kind -eq 'regex') {
            [regex]::new(
                $Pattern,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
                    [Text.RegularExpressions.RegexOptions]::CultureInvariant,
                $regexTimeout
            )
        } else {
            $null
        }
        AllowlistRegex = if (-not [string]::IsNullOrEmpty($Allowlist)) {
            [regex]::new(
                $Allowlist,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
                    [Text.RegularExpressions.RegexOptions]::CultureInvariant,
                $regexTimeout
            )
        } else {
            $null
        }
    }) | Out-Null
}

Add-ScanRule -Name 'openai-api-key-prefix' -Pattern ('(?<![A-Za-z0-9_])s' + 'k-[A-Za-z0-9_\-]{16,}') -Kind 'regex'
Add-ScanRule -Name 'github-classic-token-prefix' -Pattern ('g' + 'h[pousr]_[A-Za-z0-9_]{8,}') -Kind 'regex'
Add-ScanRule -Name 'huggingface-token-prefix' -Pattern ('(?<![A-Za-z0-9])h' + 'f_[A-Za-z0-9]{8,}') -Kind 'regex'
Add-ScanRule -Name 'slack-webhook-url' -Pattern ('hooks.slack.' + 'com/services/[A-Za-z0-9/_\-]{8,}') -Kind 'regex'
Add-ScanRule -Name 'sendgrid-api-key-prefix' -Pattern ('S' + 'G\.[A-Za-z0-9_\-]{16,}\.[A-Za-z0-9_\-]{16,}') -Kind 'regex'
Add-ScanRule -Name 'github-fine-grained-token-prefix' -Pattern ('github' + '_pat_') -Kind 'literal'
Add-ScanRule -Name 'slack-bot-token-prefix' -Pattern ('xo' + 'xb-') -Kind 'literal'
Add-ScanRule -Name 'slack-token-prefix' -Pattern ('xo' + 'x[pab]-') -Kind 'regex'
Add-ScanRule -Name 'slack-app-token-prefix' -Pattern ('xa' + 'pp-') -Kind 'literal'
Add-ScanRule -Name 'aws-access-key-id' -Pattern ('AKIA' + '[0-9A-Z]{16}') -Kind 'regex'
Add-ScanRule -Name 'gcp-api-key' -Pattern ('AIza' + '[0-9A-Za-z_\-]{35}') -Kind 'regex'
Add-ScanRule -Name 'npm-auth-token-assignment' -Pattern '[_A-Za-z0-9./:-]*_authToken\s*=\s*[A-Za-z0-9._\-]{8,}' -Kind 'regex'
Add-ScanRule -Name 'python-package-index-token-prefix' -Pattern ('pypi-' + '[A-Za-z0-9_\-]{16,}') -Kind 'regex'
Add-ScanRule -Name 'ruby-package-credentials-assignment' -Pattern (':rubygems_' + 'api_key:\s+[A-Za-z0-9_\-]{8,}') -Kind 'regex'
Add-ScanRule -Name 'gitlab-token-prefix' -Pattern ('gl' + '(?:pat|oas|dt|rt|rtr|cbt|ptt|ft|imt|agent|wt|soat|ffct)-[A-Za-z0-9_\-]{8,}') -Kind 'regex'
Add-ScanRule -Name 'gitlab-session-cookie' -Pattern ('_gitlab_' + 'session=[A-Za-z0-9._\-]{8,}') -Kind 'regex'
Add-ScanRule -Name 'anthropic-api-key-prefix' -Pattern ('sk-ant-' + '[A-Za-z0-9_\-]{16,}') -Kind 'regex'
Add-ScanRule -Name 'jwt-token-shape' -Pattern 'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}' -Kind 'regex'
Add-ScanRule -Name 'stripe-live-key' -Pattern ('(?:sk|rk)' + '_live_[0-9A-Za-z]{16,}') -Kind 'regex'
Add-ScanRule -Name 'private-key-block' -Pattern ('BEGIN ' + '(?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY') -Kind 'regex'
Add-ScanRule -Name 'bearer-token-header' -Pattern ('Bearer' + ' [A-Za-z0-9._\-]{8,}') -Kind 'regex'
Add-ScanRule -Name 'private-inventory-repo' -Pattern ('h8nc4y' + '/codex-global-context') -Kind 'literal'
Add-ScanRule -Name 'private-projects-path' -Pattern ('D:' + '\Agent\Codex\Projects') -Kind 'literal'
Add-ScanRule -Name 'private-user-path' -Pattern ('C:' + '\Users\h8nc4') -Kind 'literal'

# 安全なdocumentation placeholderだけをemail検出から除外する。
$emailAllowlistPattern = '@(?:example\.(?:com|org|net)|test|localhost)$'
Add-ScanRule -Name 'email-address' -Pattern '\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b' -Kind 'regex' -Allowlist $emailAllowlistPattern
Add-ScanRule -Name 'windows-absolute-path' -Pattern '\b[A-Za-z]:\\(?:[^\\/:*?"<>|\r\n]+\\?){2,}' -Kind 'regex'

# 実値だけを検出し、runtime参照や明示placeholderは許可する。
$secretAssignmentKeyPattern = '(?:[A-Z][A-Z0-9]*_)*(?:API_KEY|TOKEN|SECRET|PASSWORD)'
$secretAssignmentPlaceholderPattern = '^(?:\$\{\{\s*secrets\.[A-Z_][A-Z0-9_]*\s*\}\}|\$\{[A-Z_][A-Z0-9_]*\}|\$env:[A-Z_][A-Z0-9_]*|\$[A-Z_][A-Z0-9_]*|%[A-Z_][A-Z0-9_]*%|process\.env\.[A-Z_][A-Z0-9_]*|<[A-Z0-9_.:-]+>)$'
Add-ScanRule `
    -Name 'secret-assignment' `
    -Pattern ('(?<![A-Za-z0-9])' + $secretAssignmentKeyPattern +
        '\s*=\s*(?<value>[^#;\r\n]*)') `
    -Kind 'regex'

# Git子processだけでなく列挙・decode・regex・serialize・最終emitまで同じ時計へ収める。
function Assert-ScanDeadline {
    if ($script:scanStopwatch.ElapsedMilliseconds -ge
        $ScanDeadlineMilliseconds) {
        Stop-ScanIntegrityFailure -Reason 'scan-deadline'
    }
}

$githubUrlPattern = 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?'
$boundedRegexOptions =
    [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
    [Text.RegularExpressions.RegexOptions]::CultureInvariant
$githubUrlRegex = [regex]::new(
    $githubUrlPattern,
    $boundedRegexOptions,
    $regexTimeout
)
$ownRepoUrlRegex = [regex]::new(
    $ownRepoUrlPattern,
    $boundedRegexOptions,
    $regexTimeout
)
$secretAssignmentPlaceholderRegex = [regex]::new(
    $secretAssignmentPlaceholderPattern,
    $boundedRegexOptions,
    $regexTimeout
)
# BatchのSETだけはquoted wrapperとcommand separatorを文法境界として扱う。
# `/p` promptは値ではないため除外し、line中やcomment中のliteralは検出する。
$windowsBatchCommandBoundaryPattern = '\s*(?:[&|)]|\d*[<>]|$)'
$windowsBatchSecretAssignmentRegex = [regex]::new(
    ('(?<![A-Za-z0-9_])@?set\s+(?!/p(?:\s|$))(?:(?:"' +
        $secretAssignmentKeyPattern + '\s*=(?<value>[^"\r\n]*)"(?=' +
        $windowsBatchCommandBoundaryPattern + '))|(?:(?<value>"(?=' +
        $secretAssignmentKeyPattern + '\s*=))' +
        $secretAssignmentKeyPattern + '\s*=[^\r\n]*)|(?:' +
        $secretAssignmentKeyPattern + '\s*=\s*(?<value>.*?)(?=' +
        $windowsBatchCommandBoundaryPattern + ')))'),
    $boundedRegexOptions,
    $regexTimeout
)
# Batch固有の遅延展開、位置引数、FOR変数だけをruntime参照として許可する。
$windowsBatchRuntimePlaceholderRegex = [regex]::new(
    ('^(?:![A-Z_][A-Z0-9_]*!|%(?:[0-9*]|~[FDPNXSATZ]*' +
        '(?:\$[A-Z_][A-Z0-9_]*:)?[0-9])|%%(?:[A-Z]|~[FDPNXSATZ]*' +
        '(?:\$[A-Z_][A-Z0-9_]*:)?[A-Z]))$'),
    $boundedRegexOptions,
    $regexTimeout
)
$findings = New-Object System.Collections.Generic.List[object]
$findingsTruncated = $false

# finding総数を有限に保ち、pathは既にsanitizedされた表示値だけを保持する。
function Add-ScanFinding {
    param(
        [string]$File,
        [int]$Line,
        [string]$Rule
    )

    Assert-ScanDeadline

    # A marker-dense line is untrusted input. Retain a useful bounded report
    # rather than allowing regex matches to grow memory and CI output without
    # limit.
    if ($script:findings.Count -ge $maxFindings) {
        $script:findingsTruncated = $true
        return $false
    }
    $script:findings.Add([pscustomobject]@{
        File = $File
        Line = $Line
        Rule = $Rule
        Match = '<redacted>'
    }) | Out-Null
    return $true
}

# Limit scanning to text files to avoid binary noise and expensive regex work.
# Extensionless text files such as LICENSE are still allowed. Dotfiles like
# .env are "all extension" to GetExtension, so the secret-prone ones are
# listed explicitly — otherwise they would be silently skipped.
# Treat PEM and KEY as private-key text containers so the existing rule reaches
# their standard extensions.
# JS / TS と同じ detector routing を派生sourceとcomponent sourceにも適用する。
# JSX / TSX、module形式、Vue / Svelte / Astroを明示列挙してsilent skipを防ぐ。
# Terraform、HCL、Java properties、CONF、SQL、Windows batchも既存detectorへ到達させ、ruleの意味は変えない。
# 大小文字はHashSetのcomparerで統一して扱う。
$textExtensions = @(
    '.md', '.markdown', '.txt', '.ps1', '.psm1', '.psd1', '.yml', '.yaml',
    '.json', '.jsonc', '.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx', '.mts', '.cts',
    '.vue', '.svelte', '.astro', '.py', '.sh', '.bat', '.cmd', '.sql', '.cfg', '.conf', '.ini', '.toml', '.properties',
    '.tf', '.tfvars', '.hcl', '.editorconfig', '.gitignore', '.gitattributes', '.npmrc',
    '.xml', '.html',
    '.css', '.pem', '.key'
)
$textExtensionSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$textExtensions, [System.StringComparer]::OrdinalIgnoreCase)

# `.env`やextensionless fileを含め、secretが置かれやすいtext候補を明示判定する。
function Test-IsTextFile {
    param([string]$FullPath)

    Assert-ScanDeadline
    $fileName = [IO.Path]::GetFileName($FullPath)
    # 通常名で毎回regex engineを起動せず、dotenv候補だけを詳細判定する。
    if ($fileName.StartsWith(
            '.env',
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        [regex]::IsMatch(
            $fileName,
            '^\.env(?:\.[A-Za-z0-9_-]+)*$',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase,
            $regexTimeout
        )) {
        # Common dotenv variants (.env.local, .env.production, and similar)
        # use the suffix as a profile name rather than a file type.
        return $true
    }
    if ($fileName.StartsWith('.') -and
        $fileName.IndexOf('.', 1) -lt 0) {
        # A single-leading-dot name has no semantic extension even though
        # GetExtension treats the whole name as one (for example `.hidden`).
        return $true
    }
    $extension = [System.IO.Path]::GetExtension($FullPath)
    if ([string]::IsNullOrEmpty($extension)) {
        # Treat extensionless files as text.
        return $true
    }
    return $textExtensionSet.Contains($extension)
}

function Test-BoundedProcessHealthy {
    param([object]$Result)

    Assert-ScanDeadline
    return -not $Result.TimedOut -and
        -not $Result.OutputLimitExceeded -and
        $Result.TreeStopped -and
        $Result.StreamsDrained
}

# 各regex評価にもhard timeoutを与え、scan-wide時計へ戻らない単一matchを作らない。
function Get-FirstBoundedRegexMatch {
    param(
        [AllowEmptyString()]
        [string]$InputText,
        [Parameter(Mandatory = $true)]
        [regex]$Regex
    )

    Assert-ScanDeadline
    try {
        $match = $Regex.Match($InputText)
    }
    catch [Text.RegularExpressions.RegexMatchTimeoutException] {
        Stop-ScanIntegrityFailure -Reason 'scan-regex-timeout'
    }
    catch {
        Stop-ScanIntegrityFailure -Reason 'scan-regex'
    }
    Assert-ScanDeadline
    return $match
}

function Test-ByteArraysEqual {
    param(
        [byte[]]$Left,
        [byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if (($index -band 4095) -eq 0) {
            Assert-ScanDeadline
        }
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Test-IsReparsePoint {
    param([System.IO.FileSystemInfo]$Item)

    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $true
    }

    # PowerShell on POSIX exposes symbolic links through LinkType even on
    # runtimes where FileAttributes does not report ReparsePoint consistently.
    $linkTypeProperty = $Item.PSObject.Properties['LinkType']
    return $null -ne $linkTypeProperty -and
        -not [string]::IsNullOrWhiteSpace([string]$linkTypeProperty.Value)
}

function Test-HasGitMetadataAncestor {
    param([string]$StartPath)

    $directory = New-Object System.IO.DirectoryInfo($StartPath)
    $nameComparison = if ($runtimeIsWindows) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    while ($null -ne $directory) {
        Assert-ScanDeadline
        # `.git` 自体を解決するとdangling link/junctionを不存在と誤認し得る。
        # 親を非再帰列挙し、targetを辿らずentry名だけを判定する。
        try {
            $entries = @(
                Get-ChildItem `
                    -LiteralPath $directory.FullName `
                    -Force `
                    -Filter '.git' `
                    -ErrorAction Stop |
                    Select-Object -First 2
            )
        }
        catch {
            Stop-ScanIntegrityFailure -Reason 'git-ancestry'
        }
        foreach ($entry in $entries) {
            if ([string]::Equals(
                $entry.Name,
                '.git',
                $nameComparison
            )) {
                return $true
            }
        }
        $directory = $directory.Parent
    }
    return $false
}

# control/bidi/line-separatorをescapeし、1件の表示pathにもbyte予算を課す。
function ConvertTo-SafeDisplayPath {
    param([string]$RelativePath)

    Assert-ScanDeadline
    $displayPath =
        [AgenticCodingSecurityGate.PrivateMarkerWorktreeSnapshot]::
            EscapeDisplayPath($RelativePath, $maxDisplayPathCharacters)
    Assert-ScanDeadline
    return $displayPath
}

# worktree snapshotはprovider pathを検査後に開き直さない。Windowsは各componentを
# OPEN_REPARSE_POINTで保持し、POSIXはopenat+O_NOFOLLOWでrootから辿る。
# leafのstable identityと内容hashを保存し、最終報告直前に同じ経路で再検証する。
if ($null -eq (
    'AgenticCodingSecurityGate.PrivateMarkerWorktreeSnapshot' -as [type]
)) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace AgenticCodingSecurityGate
{
    public sealed class PrivateMarkerWorktreeSnapshot
    {
        private const uint GENERIC_READ = 0x80000000;
        private const uint FILE_READ_ATTRIBUTES = 0x00000080;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        private const uint FILE_FLAG_SEQUENTIAL_SCAN = 0x08000000;
        private const uint FILE_ATTRIBUTE_DIRECTORY = 0x00000010;
        private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400;
        private const int ERROR_FILE_NOT_FOUND = 2;
        private const int ENOENT = 2;
        private const int AT_EMPTY_PATH = 0x1000;
        private const uint STATX_BASIC_STATS = 0x000007ff;
        private const ushort S_IFMT = 0xf000;
        private const ushort S_IFDIR = 0x4000;
        private const ushort S_IFREG = 0x8000;

        private readonly string repositoryRoot;
        private readonly string[] segments;
        private readonly long maximumBytes;
        private readonly string identity;
        private readonly string version;
        private readonly string contentHash;
        private static string testPauseReadyPath;
        private static string testPauseReleasePath;
        private static int testPauseTimeoutMilliseconds;
        private static readonly object contentHashLock = new object();
        private static readonly SHA256 contentHasher = SHA256.Create();

        public bool IsMissing { get; private set; }
        public byte[] Bytes { get; private set; }

        private PrivateMarkerWorktreeSnapshot(
            string root,
            string[] pathSegments,
            long maxBytes,
            bool missing,
            byte[] bytes,
            string stableIdentity,
            string stableVersion,
            string hash
        )
        {
            repositoryRoot = root;
            segments = pathSegments;
            maximumBytes = maxBytes;
            IsMissing = missing;
            Bytes = bytes;
            identity = stableIdentity;
            version = stableVersion;
            contentHash = hash;
        }

        public static PrivateMarkerWorktreeSnapshot Capture(
            string repositoryRoot,
            string[] segments,
            long maximumBytes
        )
        {
            ValidateArguments(repositoryRoot, segments, maximumBytes);
            return CaptureCore(
                Path.GetFullPath(repositoryRoot),
                (string[])segments.Clone(),
                maximumBytes
            );
        }

        public static void ConfigureSingleTestPauseBeforeLeaf(
            string readyPath,
            string releasePath,
            int timeoutMilliseconds
        )
        {
            if (String.IsNullOrWhiteSpace(readyPath) ||
                String.IsNullOrWhiteSpace(releasePath) ||
                timeoutMilliseconds < 1 ||
                timeoutMilliseconds > 10000)
            {
                throw new ArgumentException(
                    "Invalid worktree snapshot test pause."
                );
            }
            testPauseReadyPath = readyPath;
            testPauseReleasePath = releasePath;
            testPauseTimeoutMilliseconds = timeoutMilliseconds;
        }

        public static Task<PrivateMarkerWorktreeSnapshot>
            CaptureWithConfiguredTestPauseAsync(
                string repositoryRoot,
                string[] segments,
                long maximumBytes
            )
        {
            return Task.Run(delegate
            {
                return Capture(repositoryRoot, segments, maximumBytes);
            });
        }

        public static string EscapeDisplayPath(
            string relativePath,
            int maximumCharacters
        )
        {
            if (relativePath == null || maximumCharacters < 32)
            {
                throw new ArgumentException("Invalid display path input.");
            }
            const string suffix = "...<truncated>";
            int prefixLimit = maximumCharacters - suffix.Length;
            var builder = new StringBuilder(
                Math.Min(maximumCharacters, relativePath.Length)
            );
            foreach (char character in relativePath)
            {
                int codePoint = character;
                bool unsafeCharacter =
                    codePoint <= 0x1f ||
                    (codePoint >= 0x7f && codePoint <= 0x9f) ||
                    codePoint == 0x00ad ||
                    (codePoint >= 0x0600 && codePoint <= 0x0605) ||
                    codePoint == 0x061c ||
                    codePoint == 0x06dd ||
                    codePoint == 0x070f ||
                    (codePoint >= 0x0890 && codePoint <= 0x0891) ||
                    codePoint == 0x08e2 ||
                    (codePoint >= 0x17b4 && codePoint <= 0x17b5) ||
                    codePoint == 0x180e ||
                    (codePoint >= 0x200b && codePoint <= 0x200f) ||
                    (codePoint >= 0x2028 && codePoint <= 0x202e) ||
                    (codePoint >= 0x2060 && codePoint <= 0x2064) ||
                    (codePoint >= 0x2066 && codePoint <= 0x206f) ||
                    (codePoint >= 0xd800 && codePoint <= 0xdfff) ||
                    codePoint == 0xfeff ||
                    (codePoint >= 0xfff9 && codePoint <= 0xfffb);
                string piece;
                if (character == '\\')
                {
                    piece = "\\u005c";
                }
                else if (unsafeCharacter)
                {
                    piece = "\\u" + codePoint.ToString(
                        "x4",
                        CultureInfo.InvariantCulture
                    );
                }
                else
                {
                    piece = character.ToString();
                }
                if (builder.Length + piece.Length > prefixLimit)
                {
                    builder.Append(suffix);
                    return builder.ToString();
                }
                builder.Append(piece);
            }
            return builder.ToString();
        }

        public bool MatchesCurrent()
        {
            PrivateMarkerWorktreeSnapshot current = CaptureCore(
                repositoryRoot,
                (string[])segments.Clone(),
                maximumBytes
            );
            if (IsMissing || current.IsMissing)
            {
                return IsMissing && current.IsMissing;
            }
            return String.Equals(
                    identity,
                    current.identity,
                    StringComparison.Ordinal
                ) &&
                String.Equals(
                    version,
                    current.version,
                    StringComparison.Ordinal
                ) &&
                String.Equals(
                    contentHash,
                    current.contentHash,
                    StringComparison.Ordinal
                );
        }

        private static PrivateMarkerWorktreeSnapshot CaptureCore(
            string repositoryRoot,
            string[] segments,
            long maximumBytes
        )
        {
            if (Environment.OSVersion.Platform == PlatformID.Win32NT)
            {
                return CaptureWindows(repositoryRoot, segments, maximumBytes);
            }
            return CapturePosix(repositoryRoot, segments, maximumBytes);
        }

        private static void ValidateArguments(
            string repositoryRoot,
            string[] segments,
            long maximumBytes
        )
        {
            if (String.IsNullOrWhiteSpace(repositoryRoot) ||
                !Path.IsPathRooted(repositoryRoot) ||
                segments == null ||
                segments.Length == 0 ||
                maximumBytes < 0 ||
                maximumBytes > Int32.MaxValue)
            {
                throw new InvalidDataException("Invalid worktree snapshot input.");
            }
            foreach (string segment in segments)
            {
                if (String.IsNullOrEmpty(segment) ||
                    segment == "." ||
                    segment == ".." ||
                    Path.IsPathRooted(segment) ||
                    segment.IndexOf(Path.DirectorySeparatorChar) >= 0 ||
                    (Path.AltDirectorySeparatorChar !=
                        Path.DirectorySeparatorChar &&
                        segment.IndexOf(Path.AltDirectorySeparatorChar) >= 0))
                {
                    throw new InvalidDataException(
                        "Invalid worktree snapshot segment."
                    );
                }
            }
        }

        private static PrivateMarkerWorktreeSnapshot CaptureWindows(
            string repositoryRoot,
            string[] segments,
            long maximumBytes
        )
        {
            var handles = new List<SafeFileHandle>();
            try
            {
                SafeFileHandle rootHandle = OpenWindowsPath(
                    repositoryRoot,
                    FILE_READ_ATTRIBUTES,
                    FILE_FLAG_BACKUP_SEMANTICS |
                        FILE_FLAG_OPEN_REPARSE_POINT
                );
                handles.Add(rootHandle);
                WindowsMetadata rootMetadata = GetWindowsMetadata(rootHandle);
                if (!rootMetadata.IsDirectory || rootMetadata.IsReparsePoint)
                {
                    throw new InvalidDataException(
                        "Unsafe worktree snapshot root."
                    );
                }

                string currentPath = repositoryRoot;
                for (int index = 0; index < segments.Length; index++)
                {
                    bool final = index == segments.Length - 1;
                    currentPath = Path.Combine(currentPath, segments[index]);
                    PauseBeforeLeafForTest();
                    SafeFileHandle handle = CreateFile(
                        ToExtendedWindowsPath(currentPath),
                        final ? GENERIC_READ | FILE_READ_ATTRIBUTES :
                            FILE_READ_ATTRIBUTES,
                        FILE_SHARE_READ,
                        IntPtr.Zero,
                        OPEN_EXISTING,
                        final ?
                            FILE_FLAG_OPEN_REPARSE_POINT |
                                FILE_FLAG_SEQUENTIAL_SCAN :
                            FILE_FLAG_BACKUP_SEMANTICS |
                                FILE_FLAG_OPEN_REPARSE_POINT,
                        IntPtr.Zero
                    );
                    if (handle.IsInvalid)
                    {
                        int error = Marshal.GetLastWin32Error();
                        handle.Dispose();
                        if (final && error == ERROR_FILE_NOT_FOUND)
                        {
                            return Missing(
                                repositoryRoot,
                                segments,
                                maximumBytes
                            );
                        }
                        throw new IOException(
                            "Safe Windows worktree open failed.",
                            new System.ComponentModel.Win32Exception(error)
                        );
                    }
                    handles.Add(handle);
                    WindowsMetadata before = GetWindowsMetadata(handle);
                    if (before.IsReparsePoint ||
                        (final && before.IsDirectory) ||
                        (!final && !before.IsDirectory))
                    {
                        throw new InvalidDataException(
                            "Unsafe Windows worktree component."
                        );
                    }
                    if (!final)
                    {
                        continue;
                    }
                    if (before.Length > maximumBytes)
                    {
                        throw new InvalidDataException(
                            "Worktree snapshot exceeds byte limit."
                        );
                    }
                    byte[] bytes = ReadHandleBytes(
                        handle,
                        before.Length,
                        maximumBytes
                    );
                    WindowsMetadata after = GetWindowsMetadata(handle);
                    if (!String.Equals(
                            before.Identity,
                            after.Identity,
                            StringComparison.Ordinal
                        ) ||
                        !String.Equals(
                            before.Version,
                            after.Version,
                            StringComparison.Ordinal
                        ) ||
                        after.Length != bytes.LongLength)
                    {
                        throw new InvalidDataException(
                            "Windows worktree changed while reading."
                        );
                    }
                    return Present(
                        repositoryRoot,
                        segments,
                        maximumBytes,
                        bytes,
                        before.Identity,
                        before.Version
                    );
                }
                throw new InvalidDataException("Worktree leaf is missing.");
            }
            finally
            {
                for (int index = handles.Count - 1; index >= 0; index--)
                {
                    handles[index].Dispose();
                }
            }
        }

        private static SafeFileHandle OpenWindowsPath(
            string path,
            uint desiredAccess,
            uint flags
        )
        {
            SafeFileHandle handle = CreateFile(
                ToExtendedWindowsPath(path),
                desiredAccess,
                FILE_SHARE_READ,
                IntPtr.Zero,
                OPEN_EXISTING,
                flags,
                IntPtr.Zero
            );
            if (handle.IsInvalid)
            {
                int error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new IOException(
                    "Safe Windows worktree root open failed.",
                    new System.ComponentModel.Win32Exception(error)
                );
            }
            return handle;
        }

        private static string ToExtendedWindowsPath(string path)
        {
            string fullPath = Path.GetFullPath(path);
            if (fullPath.StartsWith(
                @"\\?\",
                StringComparison.Ordinal
            ))
            {
                return fullPath;
            }
            if (fullPath.StartsWith(
                @"\\",
                StringComparison.Ordinal
            ))
            {
                return @"\\?\UNC\" + fullPath.Substring(2);
            }
            return @"\\?\" + fullPath;
        }

        private static PrivateMarkerWorktreeSnapshot CapturePosix(
            string repositoryRoot,
            string[] segments,
            long maximumBytes
        )
        {
            bool darwin = RuntimeInformation.IsOSPlatform(OSPlatform.OSX);
            int noFollow = darwin ? 0x00000100 : 0x00020000;
            int directory = darwin ? 0x00100000 : 0x00010000;
            int closeOnExec = darwin ? 0x01000000 : 0x00080000;
            var handles = new List<SafeFileHandle>();
            try
            {
                int rootDescriptor = open(
                    repositoryRoot,
                    noFollow | directory | closeOnExec
                );
                if (rootDescriptor < 0)
                {
                    throw new IOException("Safe POSIX worktree root open failed.");
                }
                var rootHandle = new SafeFileHandle(
                    new IntPtr(rootDescriptor),
                    true
                );
                handles.Add(rootHandle);
                PosixMetadata rootMetadata =
                    GetPosixMetadata(rootDescriptor, darwin);
                if (!rootMetadata.IsDirectory)
                {
                    throw new InvalidDataException(
                        "Unsafe POSIX worktree root."
                    );
                }

                int parentDescriptor = rootDescriptor;
                for (int index = 0; index < segments.Length; index++)
                {
                    bool final = index == segments.Length - 1;
                    PauseBeforeLeafForTest();
                    int descriptor = openat(
                        parentDescriptor,
                        segments[index],
                        noFollow | closeOnExec | (final ? 0 : directory)
                    );
                    if (descriptor < 0)
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (final && error == ENOENT)
                        {
                            return Missing(
                                repositoryRoot,
                                segments,
                                maximumBytes
                            );
                        }
                        throw new IOException(
                            "Safe POSIX worktree component open failed."
                        );
                    }
                    var handle = new SafeFileHandle(
                        new IntPtr(descriptor),
                        true
                    );
                    handles.Add(handle);
                    PosixMetadata before =
                        GetPosixMetadata(descriptor, darwin);
                    if ((final && !before.IsRegular) ||
                        (!final && !before.IsDirectory))
                    {
                        throw new InvalidDataException(
                            "Unsafe POSIX worktree component."
                        );
                    }
                    if (!final)
                    {
                        parentDescriptor = descriptor;
                        continue;
                    }
                    if (before.Length > maximumBytes)
                    {
                        throw new InvalidDataException(
                            "Worktree snapshot exceeds byte limit."
                        );
                    }
                    byte[] bytes = ReadHandleBytes(
                        handle,
                        before.Length,
                        maximumBytes
                    );
                    PosixMetadata after =
                        GetPosixMetadata(descriptor, darwin);
                    if (!String.Equals(
                            before.Identity,
                            after.Identity,
                            StringComparison.Ordinal
                        ) ||
                        !String.Equals(
                            before.Version,
                            after.Version,
                            StringComparison.Ordinal
                        ) ||
                        after.Length != bytes.LongLength)
                    {
                        throw new InvalidDataException(
                            "POSIX worktree changed while reading."
                        );
                    }
                    return Present(
                        repositoryRoot,
                        segments,
                        maximumBytes,
                        bytes,
                        before.Identity,
                        before.Version
                    );
                }
                throw new InvalidDataException("Worktree leaf is missing.");
            }
            finally
            {
                for (int index = handles.Count - 1; index >= 0; index--)
                {
                    handles[index].Dispose();
                }
            }
        }

        private static void PauseBeforeLeafForTest()
        {
            string readyPath = testPauseReadyPath;
            string releasePath = testPauseReleasePath;
            int timeoutMilliseconds = testPauseTimeoutMilliseconds;
            if (String.IsNullOrWhiteSpace(readyPath))
            {
                return;
            }

            // test専用hookは1回だけ消費し、final identity再検証では停止しない。
            testPauseReadyPath = null;
            testPauseReleasePath = null;
            testPauseTimeoutMilliseconds = 0;
            File.WriteAllText(readyPath, "ready");
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();
            while (stopwatch.ElapsedMilliseconds < timeoutMilliseconds)
            {
                if (File.Exists(releasePath))
                {
                    return;
                }
                System.Threading.Thread.Sleep(5);
            }
            throw new TimeoutException(
                "Worktree snapshot test pause timed out."
            );
        }

        private static byte[] ReadHandleBytes(
            SafeFileHandle handle,
            long expectedLength,
            long maximumBytes
        )
        {
            if (expectedLength < 0 ||
                expectedLength > maximumBytes ||
                expectedLength > Int32.MaxValue)
            {
                throw new InvalidDataException(
                    "Invalid worktree snapshot length."
                );
            }
            byte[] bytes = new byte[(int)expectedLength];
            // FileStreamは渡したSafeFileHandleをdisposeするため、identity再確認用の
            // original handleを残し、read専用duplicateだけをstreamへ所有させる。
            SafeFileHandle readHandle = DuplicateForRead(handle);
            using (var stream = new FileStream(
                readHandle,
                FileAccess.Read,
                8192,
                false
            ))
            {
                int offset = 0;
                while (offset < bytes.Length)
                {
                    int count = stream.Read(
                        bytes,
                        offset,
                        bytes.Length - offset
                    );
                    if (count == 0)
                    {
                        throw new EndOfStreamException(
                            "Worktree snapshot ended early."
                        );
                    }
                    offset += count;
                }
                if (stream.ReadByte() != -1)
                {
                    throw new InvalidDataException(
                        "Worktree snapshot grew while reading."
                    );
                }
            }
            return bytes;
        }

        private static SafeFileHandle DuplicateForRead(
            SafeFileHandle handle
        )
        {
            if (Environment.OSVersion.Platform == PlatformID.Win32NT)
            {
                SafeFileHandle duplicate;
                IntPtr currentProcess = GetCurrentProcess();
                if (!DuplicateHandle(
                    currentProcess,
                    handle,
                    currentProcess,
                    out duplicate,
                    0,
                    false,
                    0x00000002
                ))
                {
                    throw new IOException(
                        "Windows worktree handle duplication failed.",
                        new System.ComponentModel.Win32Exception(
                            Marshal.GetLastWin32Error()
                        )
                    );
                }
                return duplicate;
            }
            int descriptor = dup(handle.DangerousGetHandle().ToInt32());
            if (descriptor < 0)
            {
                throw new IOException(
                    "POSIX worktree handle duplication failed."
                );
            }
            return new SafeFileHandle(new IntPtr(descriptor), true);
        }

        private static PrivateMarkerWorktreeSnapshot Missing(
            string repositoryRoot,
            string[] segments,
            long maximumBytes
        )
        {
            return new PrivateMarkerWorktreeSnapshot(
                repositoryRoot,
                (string[])segments.Clone(),
                maximumBytes,
                true,
                null,
                null,
                null,
                null
            );
        }

        private static PrivateMarkerWorktreeSnapshot Present(
            string repositoryRoot,
            string[] segments,
            long maximumBytes,
            byte[] bytes,
            string identity,
            string version
        )
        {
            string hash;
            lock (contentHashLock)
            {
                hash = Convert.ToBase64String(
                    contentHasher.ComputeHash(bytes)
                );
            }
            return new PrivateMarkerWorktreeSnapshot(
                repositoryRoot,
                (string[])segments.Clone(),
                maximumBytes,
                false,
                bytes,
                identity,
                version,
                hash
            );
        }

        private static WindowsMetadata GetWindowsMetadata(
            SafeFileHandle handle
        )
        {
            BY_HANDLE_FILE_INFORMATION information;
            if (!GetFileInformationByHandle(handle, out information))
            {
                throw new IOException(
                    "Windows worktree identity query failed.",
                    new System.ComponentModel.Win32Exception(
                        Marshal.GetLastWin32Error()
                    )
                );
            }
            FILE_BASIC_INFO basic;
            if (!GetFileInformationByHandleEx(
                handle,
                0,
                out basic,
                (uint)Marshal.SizeOf(typeof(FILE_BASIC_INFO))
            ))
            {
                throw new IOException(
                    "Windows worktree version query failed.",
                    new System.ComponentModel.Win32Exception(
                        Marshal.GetLastWin32Error()
                    )
                );
            }
            long length = ((long)information.FileSizeHigh << 32) |
                information.FileSizeLow;
            string identity = String.Format(
                CultureInfo.InvariantCulture,
                "{0:x8}:{1:x8}{2:x8}",
                information.VolumeSerialNumber,
                information.FileIndexHigh,
                information.FileIndexLow
            );
            string version = String.Format(
                CultureInfo.InvariantCulture,
                "{0}:{1}:{2}",
                basic.ChangeTime,
                basic.LastWriteTime,
                length
            );
            return new WindowsMetadata(
                identity,
                version,
                length,
                (information.FileAttributes &
                    FILE_ATTRIBUTE_DIRECTORY) != 0,
                (information.FileAttributes &
                    FILE_ATTRIBUTE_REPARSE_POINT) != 0
            );
        }

        private static PosixMetadata GetPosixMetadata(
            int descriptor,
            bool darwin
        )
        {
            if (darwin)
            {
                MacStat information;
                if (fstat_mac(descriptor, out information) != 0)
                {
                    throw new IOException(
                        "macOS worktree identity query failed."
                    );
                }
                ushort type = (ushort)(information.st_mode & S_IFMT);
                string identity = String.Format(
                    CultureInfo.InvariantCulture,
                    "{0}:{1}",
                    information.st_dev,
                    information.st_ino
                );
                string version = String.Format(
                    CultureInfo.InvariantCulture,
                    "{0}:{1}:{2}",
                    information.st_ctimespec.tv_sec,
                    information.st_ctimespec.tv_nsec,
                    information.st_size
                );
                return new PosixMetadata(
                    identity,
                    version,
                    information.st_size,
                    type == S_IFDIR,
                    type == S_IFREG
                );
            }

            LinuxStatx informationLinux;
            if (statx(
                descriptor,
                String.Empty,
                AT_EMPTY_PATH,
                STATX_BASIC_STATS,
                out informationLinux
            ) != 0)
            {
                throw new IOException(
                    "Linux worktree identity query failed."
                );
            }
            ushort linuxType = (ushort)(informationLinux.stx_mode & S_IFMT);
            string linuxIdentity = String.Format(
                CultureInfo.InvariantCulture,
                "{0}:{1}:{2}",
                informationLinux.stx_dev_major,
                informationLinux.stx_dev_minor,
                informationLinux.stx_ino
            );
            string linuxVersion = String.Format(
                CultureInfo.InvariantCulture,
                "{0}:{1}:{2}",
                informationLinux.stx_ctime.tv_sec,
                informationLinux.stx_ctime.tv_nsec,
                informationLinux.stx_size
            );
            return new PosixMetadata(
                linuxIdentity,
                linuxVersion,
                checked((long)informationLinux.stx_size),
                linuxType == S_IFDIR,
                linuxType == S_IFREG
            );
        }

        private sealed class WindowsMetadata
        {
            public readonly string Identity;
            public readonly string Version;
            public readonly long Length;
            public readonly bool IsDirectory;
            public readonly bool IsReparsePoint;

            public WindowsMetadata(
                string identity,
                string version,
                long length,
                bool isDirectory,
                bool isReparsePoint
            )
            {
                Identity = identity;
                Version = version;
                Length = length;
                IsDirectory = isDirectory;
                IsReparsePoint = isReparsePoint;
            }
        }

        private sealed class PosixMetadata
        {
            public readonly string Identity;
            public readonly string Version;
            public readonly long Length;
            public readonly bool IsDirectory;
            public readonly bool IsRegular;

            public PosixMetadata(
                string identity,
                string version,
                long length,
                bool isDirectory,
                bool isRegular
            )
            {
                Identity = identity;
                Version = version;
                Length = length;
                IsDirectory = isDirectory;
                IsRegular = isRegular;
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME
        {
            public uint Low;
            public uint High;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BY_HANDLE_FILE_INFORMATION
        {
            public uint FileAttributes;
            public FILETIME CreationTime;
            public FILETIME LastAccessTime;
            public FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FILE_BASIC_INFO
        {
            public long CreationTime;
            public long LastAccessTime;
            public long LastWriteTime;
            public long ChangeTime;
            public uint FileAttributes;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct StatxTimestamp
        {
            public long tv_sec;
            public uint tv_nsec;
            public int reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct LinuxStatx
        {
            public uint stx_mask;
            public uint stx_blksize;
            public ulong stx_attributes;
            public uint stx_nlink;
            public uint stx_uid;
            public uint stx_gid;
            public ushort stx_mode;
            public ushort spare0;
            public ulong stx_ino;
            public ulong stx_size;
            public ulong stx_blocks;
            public ulong stx_attributes_mask;
            public StatxTimestamp stx_atime;
            public StatxTimestamp stx_btime;
            public StatxTimestamp stx_ctime;
            public StatxTimestamp stx_mtime;
            public uint stx_rdev_major;
            public uint stx_rdev_minor;
            public uint stx_dev_major;
            public uint stx_dev_minor;
            public ulong stx_mnt_id;
            public uint stx_dio_mem_align;
            public uint stx_dio_offset_align;
            public ulong stx_subvol;
            public uint stx_atomic_write_unit_min;
            public uint stx_atomic_write_unit_max;
            public uint stx_atomic_write_segments_max;
            public uint stx_dio_read_offset_align;
            public ulong spare1;
            public ulong spare2;
            public ulong spare3;
            public ulong spare4;
            public ulong spare5;
            public ulong spare6;
            public ulong spare7;
            public ulong spare8;
            public ulong spare9;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MacTimespec
        {
            public long tv_sec;
            public long tv_nsec;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MacStat
        {
            public int st_dev;
            public ushort st_mode;
            public ushort st_nlink;
            public ulong st_ino;
            public uint st_uid;
            public uint st_gid;
            public int st_rdev;
            public MacTimespec st_atimespec;
            public MacTimespec st_mtimespec;
            public MacTimespec st_ctimespec;
            public MacTimespec st_birthtimespec;
            public long st_size;
            public long st_blocks;
            public int st_blksize;
            public uint st_flags;
            public uint st_gen;
            public int st_lspare;
            public long st_qspare0;
            public long st_qspare1;
        }

        [DllImport(
            "kernel32.dll",
            CharSet = CharSet.Unicode,
            SetLastError = true
        )]
        private static extern SafeFileHandle CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(
            SafeFileHandle file,
            out BY_HANDLE_FILE_INFORMATION information
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle file,
            int informationClass,
            out FILE_BASIC_INFO information,
            uint bufferSize
        );

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DuplicateHandle(
            IntPtr sourceProcess,
            SafeFileHandle sourceHandle,
            IntPtr targetProcess,
            out SafeFileHandle targetHandle,
            uint desiredAccess,
            bool inheritHandle,
            uint options
        );

        [DllImport("libc", SetLastError = true)]
        private static extern int open(string path, int flags);

        [DllImport("libc", SetLastError = true)]
        private static extern int openat(
            int directoryFileDescriptor,
            string path,
            int flags
        );

        [DllImport("libc", SetLastError = true)]
        private static extern int dup(int fileDescriptor);

        [DllImport("libc", SetLastError = true)]
        private static extern int statx(
            int directoryFileDescriptor,
            string path,
            int flags,
            uint mask,
            out LinuxStatx information
        );

        [DllImport(
            "libc",
            EntryPoint = "fstat",
            SetLastError = true
        )]
        private static extern int fstat_mac(
            int fileDescriptor,
            out MacStat information
        );
    }
}
'@
}

# worktreeはlink/reparseを辿らず、stable handleから取得した内容だけを返す。
function Get-SafeTrackedWorktreeState {
    param(
        [string]$RepositoryRoot,
        [string]$GitPath,
        [string]$Mode
    )

    if ($GitPath.Length -gt $maxGitPathCharacters) {
        Stop-ScanIntegrityFailure -Reason 'git-index-path-budget'
    }
    $segments = @($GitPath -split '/')
    if ($segments.Count -gt $maxGitPathSegments) {
        Stop-ScanIntegrityFailure -Reason 'git-index-path-budget'
    }
    try {
        Assert-ScanDeadline
        $snapshot = [AgenticCodingSecurityGate.PrivateMarkerWorktreeSnapshot]::
            Capture(
            $RepositoryRoot,
            [string[]]$segments,
            $maxTextFileBytes
        )
        Assert-ScanDeadline
    }
    catch {
        Stop-ScanIntegrityFailure -Reason 'worktree-snapshot'
    }
    $script:worktreeSnapshots.Add($snapshot) | Out-Null
    if ($snapshot.IsMissing) {
        return [pscustomobject]@{
            State = 'missing'
            Bytes = $null
        }
    }

    return [pscustomobject]@{
        State = 'regular'
        Bytes = [byte[]]$snapshot.Bytes
    }
}

# index blobとworktree snapshotを同じtarget形式へ揃え、合計byte上限を集約する。
function Add-ScanTarget {
    param(
        [System.Collections.Generic.List[object]]$Targets,
        [string]$SourcePath,
        [string]$DisplayPath,
        [byte[]]$Bytes
    )

    Assert-ScanDeadline
    if ($Targets.Count -ge $maxScanTargets) {
        Stop-ScanIntegrityFailure -Reason 'scan-target-count'
    }
    if ($null -eq $Bytes -or $Bytes.Length -gt $maxTextFileBytes) {
        Stop-ScanIntegrityFailure -Reason 'scan-target-size'
    }
    $script:totalScanBytes += $Bytes.Length
    if ($script:totalScanBytes -gt $maxTotalScanBytes) {
        Stop-ScanIntegrityFailure -Reason 'scan-total-size'
    }
    $Targets.Add([pscustomobject]@{
        DisplayPath = ConvertTo-SafeDisplayPath -RelativePath $DisplayPath
        Bytes = $Bytes
        IsWindowsBatch = @('.bat', '.cmd').Contains(
            [IO.Path]::GetExtension($SourcePath).ToLowerInvariant()
        )
    }) | Out-Null
}

# Git childは専用環境・protocol遮断・deadline・output capの共通境界からだけ起動する。
function Invoke-ScannerGitProcess {
    param(
        [string]$FileName,
        [string[]]$Arguments,
        [string]$IsolationRoot,
        [string]$WorkingDirectory,
        [int]$MaxStdoutBytes,
        [AllowNull()]
        [byte[]]$StandardInputBytes = $null
    )

    Assert-ScanDeadline
    $script:gitProcessCount++
    if ($script:gitProcessCount -gt $maxGitProcesses) {
        Stop-ScanIntegrityFailure -Reason 'git-process-budget'
    }
    $remaining = $ScanDeadlineMilliseconds -
        $script:scanStopwatch.ElapsedMilliseconds
    if ($remaining -le 0) {
        Stop-ScanIntegrityFailure -Reason 'git-deadline'
    }
    $commandTimeout = [int][Math]::Min(10000L, $remaining)
    try {
        return Invoke-PrivateMarkerBoundedProcess `
            -FileName $FileName `
            -Arguments $Arguments `
            -IsolationRoot $IsolationRoot `
            -WorkingDirectory $WorkingDirectory `
            -StandardInputBytes $StandardInputBytes `
            -TimeoutMilliseconds $commandTimeout `
            -MaxStdoutBytes $MaxStdoutBytes `
            -MaxStderrBytes $maxGitDiagnosticBytes
    }
    catch {
        Stop-ScanIntegrityFailure -Reason 'process-boundary-execution'
    }
}

# temp lifecycleもexception本文を外へ出さず、作成/削除を別reasonへ固定する。
function New-ScannerIsolationDirectory {
    param([string]$LiteralPath)

    try {
        New-Item `
            -ItemType Directory `
            -Path $LiteralPath `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Stop-ScanIntegrityFailure -Reason 'process-boundary-setup'
    }
}

function Remove-ScannerIsolationDirectory {
    param([string]$LiteralPath)

    try {
        Assert-ScanDeadline
        $rootDirectory = [IO.DirectoryInfo]::new($LiteralPath)
        if (-not $rootDirectory.Exists) {
            return
        }
        if (($rootDirectory.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Isolation cleanup root is a reparse point.'
        }

        $knownDirectories = [Collections.Generic.HashSet[string]]::new(
            [string[]]@(
                'home',
                'xdg',
                'tmp',
                'cache',
                'data',
                'empty-template',
                'empty-hooks'
            ),
            $pathComparer
        )
        $knownFiles = [Collections.Generic.HashSet[string]]::new(
            [string[]]@(
                'empty-global.gitconfig',
                'empty-system.gitconfig',
                'empty-attributes',
                'empty-excludes'
            ),
            $pathComparer
        )
        $rootEntries = New-Object `
            'System.Collections.Generic.List[System.IO.FileSystemInfo]'
        $rootEnumerator = $rootDirectory.
            EnumerateFileSystemInfos().
            GetEnumerator()
        try {
            while ($rootEnumerator.MoveNext()) {
                Assert-ScanDeadline
                if ($rootEntries.Count -ge 32) {
                    throw 'Isolation cleanup entry budget exceeded.'
                }
                $rootEntries.Add($rootEnumerator.Current) | Out-Null
            }
        }
        finally {
            if ($rootEnumerator -is [IDisposable]) {
                $rootEnumerator.Dispose()
            }
        }

        $filesToDelete = New-Object `
            'System.Collections.Generic.List[System.IO.FileInfo]'
        $directoriesToDelete = New-Object `
            'System.Collections.Generic.List[System.IO.DirectoryInfo]'
        $nestedFilesToDelete = New-Object `
            'System.Collections.Generic.List[System.IO.FileInfo]'
        $nestedDirectoriesToDelete = New-Object `
            'System.Collections.Generic.List[System.IO.DirectoryInfo]'
        $testUnexpectedEntryDetected = $false
        foreach ($entry in $rootEntries) {
            Assert-ScanDeadline
            if (($entry.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Isolation cleanup entry is a reparse point.'
            }
            if ($entry -is [IO.DirectoryInfo]) {
                if (-not $knownDirectories.Contains($entry.Name)) {
                    throw 'Isolation cleanup found an unknown directory.'
                }
                # 1階層を最大16件だけ列挙する。PowerShell anchorが固定名で作る
                # runtime artifact以外は降下せず失敗し、巨大treeへ依存しない。
                $childEntries = New-Object `
                    'System.Collections.Generic.List[System.IO.FileSystemInfo]'
                $childEnumerator = $entry.
                    EnumerateFileSystemInfos().
                    GetEnumerator()
                try {
                    while ($childEnumerator.MoveNext()) {
                        Assert-ScanDeadline
                        if ($childEntries.Count -ge 16) {
                            throw 'Isolation cleanup child budget exceeded.'
                        }
                        $childEntries.Add($childEnumerator.Current) | Out-Null
                    }
                }
                finally {
                    if ($childEnumerator -is [IDisposable]) {
                        $childEnumerator.Dispose()
                    }
                }

                foreach ($childEntry in $childEntries) {
                    if (($childEntry.Attributes -band
                            [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw 'Isolation cleanup child is a reparse point.'
                    }
                }
                if ($entry.Name -eq 'tmp') {
                    foreach ($childEntry in $childEntries) {
                        if ($childEntry -isnot [IO.FileInfo] -or
                            $childEntry.Name -notmatch (
                                '^CoreFxPipe_PSHost\.[0-9A-Fa-f]{8}\.' +
                                '[0-9]+\.None\.pwsh$'
                            )) {
                            throw 'Isolation cleanup found unknown temp data.'
                        }
                        $nestedFilesToDelete.Add(
                            [IO.FileInfo]$childEntry
                        ) | Out-Null
                    }
                } elseif ($entry.Name -eq 'cache') {
                    foreach ($childEntry in $childEntries) {
                        if ($childEntry -isnot [IO.DirectoryInfo] -or
                            $childEntry.Name -ne 'powershell') {
                            throw 'Isolation cleanup found unknown cache data.'
                        }
                        # Select-Object の bounded materialization で列挙handleを
                        # pipeline終了時に閉じ、直後のDirectory.Deleteを妨げない。
                        $cacheChildren = @(
                            $childEntry.EnumerateFileSystemInfos() |
                            Select-Object -First 1
                        )
                        if ($cacheChildren.Count -gt 0) {
                            throw 'Isolation cleanup cache is not empty.'
                        }
                        $nestedDirectoriesToDelete.Add(
                            [IO.DirectoryInfo]$childEntry
                        ) | Out-Null
                    }
                } elseif ($entry.Name -eq 'data') {
                    foreach ($childEntry in $childEntries) {
                        if ($childEntry -isnot [IO.DirectoryInfo] -or
                            $childEntry.Name -ne 'powershell') {
                            throw 'Isolation cleanup found unknown data.'
                        }
                        $dataChildren = @(
                            $childEntry.EnumerateFileSystemInfos() |
                            Select-Object -First 2
                        )
                        $moduleChildren = @()
                        if ($dataChildren.Count -eq 1 -and
                            $dataChildren[0] -is [IO.DirectoryInfo] -and
                            $dataChildren[0].Name -eq 'Modules' -and
                            ($dataChildren[0].Attributes -band
                                [IO.FileAttributes]::ReparsePoint) -eq 0) {
                            $moduleChildren = @(
                                $dataChildren[0].EnumerateFileSystemInfos() |
                                Select-Object -First 1
                            )
                        }
                        if ($dataChildren.Count -gt 1 -or
                            ($dataChildren.Count -eq 1 -and
                                ($dataChildren[0] -isnot [IO.DirectoryInfo] -or
                                    $dataChildren[0].Name -ne 'Modules' -or
                                    ($dataChildren[0].Attributes -band
                                        [IO.FileAttributes]::ReparsePoint) -ne
                                            0 -or
                                    $moduleChildren.Count -gt 0))) {
                            throw 'Isolation cleanup found unknown data content.'
                        }
                        if ($dataChildren.Count -eq 1) {
                            $nestedDirectoriesToDelete.Add(
                                [IO.DirectoryInfo]$dataChildren[0]
                            ) | Out-Null
                        }
                        $nestedDirectoriesToDelete.Add(
                            [IO.DirectoryInfo]$childEntry
                        ) | Out-Null
                    }
                } elseif ($childEntries.Count -gt 0) {
                    throw 'Isolation cleanup directory is not empty.'
                }
                $directoriesToDelete.Add(
                    [IO.DirectoryInfo]$entry
                ) | Out-Null
                continue
            }

            $isGateFile = $entry.Name -match (
                '^posix-session-(?:ready|release|exit)-' +
                '[0-9a-f]{32}(?:\.tmp)?$'
            )
            if (-not $knownFiles.Contains($entry.Name) -and
                -not $isGateFile) {
                if ($TestOnlyCreateCleanupUnknownEntry -and
                    $entry.Name -eq 'test-only-unexpected-entry') {
                    # self-test residueだけは削除後にもfailureを保持し、tempを汚さない。
                    ([IO.FileInfo]$entry).Delete()
                    $testUnexpectedEntryDetected = $true
                    continue
                }
                throw 'Isolation cleanup found an unknown file.'
            }
            $filesToDelete.Add([IO.FileInfo]$entry) | Out-Null
        }

        foreach ($file in $nestedFilesToDelete) {
            Assert-ScanDeadline
            $file.Delete()
        }
        foreach ($directory in $nestedDirectoriesToDelete) {
            Assert-ScanDeadline
            $directory.Delete($false)
        }
        foreach ($file in $filesToDelete) {
            Assert-ScanDeadline
            $file.Delete()
        }
        foreach ($directory in $directoriesToDelete) {
            Assert-ScanDeadline
            $directory.Delete($false)
        }
        Assert-ScanDeadline
        $rootDirectory.Delete($false)
        Assert-ScanDeadline
        if ($testUnexpectedEntryDetected) {
            throw 'Isolation cleanup test detected an unknown entry.'
        }
    }
    catch {
        Stop-ScanIntegrityFailure -Reason 'process-boundary-cleanup'
    }
}

# Prefer the exact index plus existing regular worktree content. This covers
# staged-only and unstaged-only markers while avoiding symlink target traversal.
# Non-git fixture directories use the working-tree fallback.
try {
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
}
catch {
    Stop-ScanIntegrityFailure -Reason 'scan-root-missing'
}
if (-not $rootItem.PSIsContainer -or (Test-IsReparsePoint -Item $rootItem)) {
    Stop-ScanIntegrityFailure -Reason 'scan-root-type'
}
$root = [IO.Path]::GetFullPath($rootItem.FullName)
$pathComparison = if ($runtimeIsWindows) {
    [StringComparison]::OrdinalIgnoreCase
} else {
    [StringComparison]::Ordinal
}
$pathComparer = if ($runtimeIsWindows) {
    [StringComparer]::OrdinalIgnoreCase
} else {
    [StringComparer]::Ordinal
}
$scanTargets = New-Object System.Collections.Generic.List[object]
$worktreeSnapshots = New-Object System.Collections.Generic.List[object]
$usingGitIndex = $false
$gitExe = if ($ScanMode -eq 'worktree') {
    $null
} else {
    # alias/function/scriptをGitとして実行せず、native applicationの絶対pathだけを採る。
    Get-Command `
        git `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Where-Object {
            [IO.Path]::IsPathRooted($_.Source) -and
            (Test-Path -LiteralPath $_.Source -PathType Leaf)
        } |
        Select-Object -First 1
}

if ($null -ne $gitExe) {
    $gitIsolationRoot = Join-Path (
        [System.IO.Path]::GetTempPath()
    ) ("agentic-coding-security-gate-public-git-" +
        [Guid]::NewGuid().ToString('N'))
    New-ScannerIsolationDirectory -LiteralPath $gitIsolationRoot
    try {
        $topLevelResult = Invoke-ScannerGitProcess `
            -FileName $gitExe.Source `
            -Arguments @('-C', $root, 'rev-parse', '--show-toplevel') `
            -IsolationRoot $gitIsolationRoot `
            -WorkingDirectory $root `
            -MaxStdoutBytes 65536
        if (-not (Test-BoundedProcessHealthy -Result $topLevelResult)) {
            Stop-ScanIntegrityFailure -Reason 'git-top-level-process'
        }

        if ($topLevelResult.ExitCode -eq 0) {
            $usingGitIndex = $true
            $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
            try {
                $topLevelText = $strictUtf8.GetString(
                    $topLevelResult.StdoutBytes
                ).TrimEnd([char[]]@([char]13, [char]10))
            }
            catch {
                Stop-ScanIntegrityFailure -Reason 'git-top-level-encoding'
            }
            if ([string]::IsNullOrWhiteSpace($topLevelText)) {
                Stop-ScanIntegrityFailure -Reason 'git-top-level-empty'
            }
            if ($topLevelText.IndexOfAny([char[]]@([char]0, [char]13, [char]10)) -ge 0) {
                Stop-ScanIntegrityFailure -Reason 'git-top-level-record'
            }
            try {
                $resolvedTopLevel = (Resolve-Path -LiteralPath $topLevelText).Path
            }
            catch {
                Stop-ScanIntegrityFailure -Reason 'git-top-level-missing'
            }
            if (-not [string]::Equals($root, $resolvedTopLevel, $pathComparison)) {
                Stop-ScanIntegrityFailure -Reason 'git-root-mismatch'
            }

            $indexResult = Invoke-ScannerGitProcess `
                -FileName $gitExe.Source `
                -Arguments @('-C', $root, 'ls-files', '-z', '--stage', '--') `
                -IsolationRoot $gitIsolationRoot `
                -WorkingDirectory $root `
                -MaxStdoutBytes $maxGitMetadataBytes
            if (-not (Test-BoundedProcessHealthy -Result $indexResult) -or
                $indexResult.ExitCode -ne 0) {
                Stop-ScanIntegrityFailure -Reason 'git-index-list'
            }

            # Parse NUL records as bytes so tabs/newlines inside paths do not
            # corrupt the stage header or path boundary.
            $records = New-Object System.Collections.Generic.List[object]
            $recordStart = 0
            for ($offset = 0; $offset -lt $indexResult.StdoutBytes.Length; $offset++) {
                if (($offset -band 4095) -eq 0) {
                    Assert-ScanDeadline
                }
                if ($indexResult.StdoutBytes[$offset] -ne 0) {
                    continue
                }
                $recordLength = $offset - $recordStart
                $recordBytes = New-Object byte[] $recordLength
                if ($recordLength -gt 0) {
                    [Array]::Copy(
                        $indexResult.StdoutBytes,
                        $recordStart,
                        $recordBytes,
                        0,
                        $recordLength
                    )
                }
                $records.Add($recordBytes) | Out-Null
                $recordStart = $offset + 1
            }
            if ($recordStart -ne $indexResult.StdoutBytes.Length) {
                Stop-ScanIntegrityFailure -Reason 'git-index-nul'
            }
            if ($records.Count -gt $maxGitIndexEntries) {
                Stop-ScanIntegrityFailure -Reason 'git-index-entry-budget'
            }

            # `ls-files --stage` cannot distinguish an actual empty blob from
            # the extended-index intent-to-add bit. Read the index debug flags
            # through the same bounded/hermetic Git boundary and compare every
            # raw stage header/path byte before trusting CE_INTENT_TO_ADD.
            $debugResult = Invoke-ScannerGitProcess `
                -FileName $gitExe.Source `
                -Arguments @(
                    '-C',
                    $root,
                    'ls-files',
                    '-z',
                    '--stage',
                    '--debug',
                    '--'
                ) `
                -IsolationRoot $gitIsolationRoot `
                -WorkingDirectory $root `
                -MaxStdoutBytes $maxGitMetadataBytes
            if (-not (Test-BoundedProcessHealthy -Result $debugResult) -or
                $debugResult.ExitCode -ne 0) {
                Stop-ScanIntegrityFailure -Reason 'git-index-debug'
            }

            $debugOffset = 0
            foreach ($recordBytes in $records) {
                Assert-ScanDeadline
                if (($debugOffset + $recordBytes.Length) -ge
                    $debugResult.StdoutBytes.Length) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'git-index-debug-record'
                }
                for ($recordByteIndex = 0;
                    $recordByteIndex -lt $recordBytes.Length;
                    $recordByteIndex++) {
                    if (($recordByteIndex -band 4095) -eq 0) {
                        Assert-ScanDeadline
                    }
                    if ($debugResult.StdoutBytes[
                            $debugOffset + $recordByteIndex
                        ] -ne $recordBytes[$recordByteIndex]) {
                        Stop-ScanIntegrityFailure `
                            -Reason 'git-index-debug-record'
                    }
                }
                $debugOffset += $recordBytes.Length
                if ($debugResult.StdoutBytes[$debugOffset] -ne 0) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'git-index-debug-nul'
                }
                $debugOffset++

                $debugLines = New-Object `
                    System.Collections.Generic.List[string]
                for ($debugLineIndex = 0;
                    $debugLineIndex -lt 5;
                    $debugLineIndex++) {
                    Assert-ScanDeadline
                    $lineEnd = -1
                    $lineSearchLimit = [Math]::Min(
                        $debugResult.StdoutBytes.Length,
                        $debugOffset + 256
                    )
                    for ($offset = $debugOffset;
                        $offset -lt $lineSearchLimit;
                        $offset++) {
                        if (($offset -band 4095) -eq 0) {
                            Assert-ScanDeadline
                        }
                        if ($debugResult.StdoutBytes[$offset] -eq 10) {
                            $lineEnd = $offset
                            break
                        }
                        if ($debugResult.StdoutBytes[$offset] -gt 127) {
                            Stop-ScanIntegrityFailure `
                                -Reason 'git-index-debug-encoding'
                        }
                    }
                    if ($lineEnd -lt 0) {
                        Stop-ScanIntegrityFailure `
                            -Reason 'git-index-debug-line'
                    }
                    $debugLines.Add(
                        [Text.Encoding]::ASCII.GetString(
                            $debugResult.StdoutBytes,
                            $debugOffset,
                            $lineEnd - $debugOffset
                        )
                    ) | Out-Null
                    $debugOffset = $lineEnd + 1
                }

                if ($debugLines[0] -notmatch
                    '^  ctime: [0-9]+:[0-9]+$' -or
                    $debugLines[1] -notmatch
                    '^  mtime: [0-9]+:[0-9]+$' -or
                    $debugLines[2] -notmatch
                    "^  dev: [0-9]+`tino: [0-9]+$" -or
                    $debugLines[3] -notmatch
                    "^  uid: [0-9]+`tgid: [0-9]+$") {
                    Stop-ScanIntegrityFailure `
                        -Reason 'git-index-debug-metadata'
                }
                $flagsMatch = [regex]::Match(
                    $debugLines[4],
                    "^  size: [0-9]+`tflags: (?<flags>[0-9a-fA-F]+)$"
                )
                [uint64]$debugFlags = 0
                if (-not $flagsMatch.Success -or
                    -not [uint64]::TryParse(
                        $flagsMatch.Groups['flags'].Value,
                        [Globalization.NumberStyles]::HexNumber,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$debugFlags
                    )) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'git-index-debug-flags'
                }
                if (($debugFlags -band [uint64]0x20000000) -ne 0) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'git-index-intent-to-add'
                }
            }
            if ($debugOffset -ne $debugResult.StdoutBytes.Length) {
                Stop-ScanIntegrityFailure `
                    -Reason 'git-index-debug-trailing'
            }

            $indexEntries = New-Object System.Collections.Generic.List[object]
            $seenPaths = [System.Collections.Generic.HashSet[string]]::new(
                $pathComparer
            )
            $seenFullPaths = [System.Collections.Generic.HashSet[string]]::new(
                $pathComparer
            )
            foreach ($recordBytes in $records) {
                Assert-ScanDeadline
                if ($recordBytes.Length -eq 0) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-empty-record'
                }
                $tabOffset = [Array]::IndexOf($recordBytes, [byte]9)
                if ($tabOffset -le 0 -or $tabOffset -ge ($recordBytes.Length - 1)) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-record'
                }
                $header = [Text.Encoding]::ASCII.GetString(
                    $recordBytes,
                    0,
                    $tabOffset
                )
                $headerMatch = [regex]::Match(
                    $header,
                    '^(?<mode>[0-9]{6}) (?<oid>[0-9a-fA-F]{40}|[0-9a-fA-F]{64}) (?<stage>[0-3])$'
                )
                if (-not $headerMatch.Success) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-header'
                }

                $pathLength = $recordBytes.Length - $tabOffset - 1
                try {
                    $gitPath = $strictUtf8.GetString(
                        $recordBytes,
                        $tabOffset + 1,
                        $pathLength
                    )
                }
                catch {
                    Stop-ScanIntegrityFailure -Reason 'git-index-path-encoding'
                }
                if ($gitPath.Length -gt $maxGitPathCharacters) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'git-index-path-budget'
                }
                $gitPathSegments = @($gitPath -split '/')
                if ($gitPathSegments.Count -gt $maxGitPathSegments -or
                    [string]::IsNullOrEmpty($gitPath) -or
                    [IO.Path]::IsPathRooted($gitPath) -or
                    @($gitPathSegments | Where-Object {
                        $_ -eq '' -or $_ -eq '.' -or $_ -eq '..'
                    }).Count -gt 0) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-path'
                }

                $mode = $headerMatch.Groups['mode'].Value
                $oid = $headerMatch.Groups['oid'].Value.ToLowerInvariant()
                $stage = [int]$headerMatch.Groups['stage'].Value
                if ($stage -ne 0) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-conflict'
                }
                if ($oid -match '^0+$') {
                    Stop-ScanIntegrityFailure -Reason 'git-index-intent-to-add'
                }
                if ($mode -eq '160000') {
                    Stop-ScanIntegrityFailure -Reason 'git-index-gitlink'
                }
                if ($mode -notin @('100644', '100755', '120000')) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-mode'
                }
                if (-not $seenPaths.Add($gitPath)) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-duplicate-path'
                }

                $nativeRelativePath = $gitPath.Replace(
                    [char]47,
                    [IO.Path]::DirectorySeparatorChar
                )
                try {
                    $fullPath = [IO.Path]::GetFullPath(
                        (Join-Path $root $nativeRelativePath)
                    )
                }
                catch {
                    Stop-ScanIntegrityFailure -Reason 'git-index-full-path'
                }
                $rootBoundary = $root.TrimEnd([char]47, [char]92) +
                    [IO.Path]::DirectorySeparatorChar
                if (-not $fullPath.StartsWith($rootBoundary, $pathComparison) -or
                    -not $seenFullPaths.Add($fullPath)) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-path-boundary'
                }

                $indexEntries.Add([pscustomobject]@{
                    Mode = $mode
                    Oid = $oid
                    Path = $gitPath
                    FullPath = $fullPath
                }) | Out-Null
            }

            # Fetch all unique text blobs through one binary-safe batch. This
            # keeps process count constant instead of multiplying per tracked
            # file, while the parser still enforces every object ID/type/size
            # and the exact trailing byte boundary.
            $blobCache = @{}
            $blobOids = New-Object System.Collections.Generic.List[string]
            $blobOidSet = [System.Collections.Generic.HashSet[string]]::new(
                [StringComparer]::Ordinal
            )
            foreach ($entry in $indexEntries) {
                Assert-ScanDeadline
                if ((Test-IsTextFile -FullPath $entry.Path) -and
                    $blobOidSet.Add($entry.Oid)) {
                    $blobOids.Add($entry.Oid) | Out-Null
                }
            }
            if ($blobOids.Count -gt 0) {
                $batchInputText = ($blobOids -join "`n") + "`n"
                $batchInputBytes = [Text.Encoding]::ASCII.GetBytes(
                    $batchInputText
                )
                $batchOutputLimit = [int](
                    $maxTotalScanBytes + ($blobOids.Count * 160) + 1
                )
                $batchResult = Invoke-ScannerGitProcess `
                    -FileName $gitExe.Source `
                    -Arguments @('-C', $root, 'cat-file', '--batch') `
                    -IsolationRoot $gitIsolationRoot `
                    -WorkingDirectory $root `
                    -MaxStdoutBytes $batchOutputLimit `
                    -StandardInputBytes $batchInputBytes
                if (-not (Test-BoundedProcessHealthy -Result $batchResult) -or
                    $batchResult.ExitCode -ne 0) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-blob-batch'
                }

                $batchOffset = 0
                $batchBlobTotal = 0L
                foreach ($expectedOid in $blobOids) {
                    Assert-ScanDeadline
                    $headerEnd = -1
                    $headerSearchLimit = [Math]::Min(
                        $batchResult.StdoutBytes.Length,
                        $batchOffset + 256
                    )
                    for ($offset = $batchOffset;
                        $offset -lt $headerSearchLimit;
                        $offset++) {
                        if (($offset -band 4095) -eq 0) {
                            Assert-ScanDeadline
                        }
                        if ($batchResult.StdoutBytes[$offset] -eq 10) {
                            $headerEnd = $offset
                            break
                        }
                    }
                    if ($headerEnd -lt 0) {
                        Stop-ScanIntegrityFailure `
                            -Reason 'git-index-blob-header'
                    }
                    for ($offset = $batchOffset;
                        $offset -lt $headerEnd;
                        $offset++) {
                        if (($offset -band 4095) -eq 0) {
                            Assert-ScanDeadline
                        }
                        if ($batchResult.StdoutBytes[$offset] -gt 127) {
                            Stop-ScanIntegrityFailure `
                                -Reason 'git-index-blob-header-encoding'
                        }
                    }
                    $batchHeader = [Text.Encoding]::ASCII.GetString(
                        $batchResult.StdoutBytes,
                        $batchOffset,
                        $headerEnd - $batchOffset
                    )
                    $batchHeaderMatch = [regex]::Match(
                        $batchHeader,
                        '^(?<oid>[0-9a-fA-F]{40}|[0-9a-fA-F]{64}) blob (?<size>0|[1-9][0-9]*)$'
                    )
                    if (-not $batchHeaderMatch.Success -or
                        -not $batchHeaderMatch.Groups['oid'].Value.Equals(
                            $expectedOid,
                            [StringComparison]::OrdinalIgnoreCase
                        )) {
                        Stop-ScanIntegrityFailure `
                            -Reason 'git-index-blob-header'
                    }
                    $blobSize = 0L
                    if (-not [long]::TryParse(
                        $batchHeaderMatch.Groups['size'].Value,
                        [Globalization.NumberStyles]::None,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$blobSize
                    ) -or
                        $blobSize -gt $maxTextFileBytes) {
                        Stop-ScanIntegrityFailure `
                            -Reason 'git-index-blob-size'
                    }
                    $batchBlobTotal += $blobSize
                    if ($batchBlobTotal -gt $maxTotalScanBytes) {
                        Stop-ScanIntegrityFailure `
                            -Reason 'git-index-blob-total-size'
                    }
                    $blobStart = $headerEnd + 1
                    $blobEnd = $blobStart + $blobSize
                    if ($blobEnd -ge $batchResult.StdoutBytes.Length -or
                        $batchResult.StdoutBytes[$blobEnd] -ne 10) {
                        Stop-ScanIntegrityFailure `
                            -Reason 'git-index-blob-boundary'
                    }
                    $indexBytes = New-Object byte[] ([int]$blobSize)
                    if ($blobSize -gt 0) {
                        [Array]::Copy(
                            $batchResult.StdoutBytes,
                            $blobStart,
                            $indexBytes,
                            0,
                            [int]$blobSize
                        )
                    }
                    $blobCache[$expectedOid] = $indexBytes
                    $batchOffset = [int]($blobEnd + 1)
                }
                if ($batchOffset -ne $batchResult.StdoutBytes.Length) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'git-index-blob-trailing'
                }
            }

            foreach ($entry in $indexEntries) {
                Assert-ScanDeadline
                if (-not (Test-IsTextFile -FullPath $entry.Path)) {
                    continue
                }
                if (-not $blobCache.ContainsKey($entry.Oid)) {
                    Stop-ScanIntegrityFailure -Reason 'git-index-blob-cache'
                }
                $indexBytes = [byte[]]$blobCache[$entry.Oid]

                $worktreeState = Get-SafeTrackedWorktreeState `
                    -RepositoryRoot $root `
                    -GitPath $entry.Path `
                    -Mode $entry.Mode
                if ($worktreeState.State -eq 'missing') {
                    $state = if ($entry.Mode -eq '120000') {
                        'index symlink; worktree missing'
                    } else {
                        'index; worktree missing'
                    }
                    Add-ScanTarget `
                        -Targets $scanTargets `
                        -SourcePath $entry.Path `
                        -DisplayPath "$($entry.Path) [$state]" `
                        -Bytes $indexBytes
                } elseif (Test-ByteArraysEqual `
                    -Left $indexBytes `
                    -Right $worktreeState.Bytes) {
                    Add-ScanTarget `
                        -Targets $scanTargets `
                        -SourcePath $entry.Path `
                        -DisplayPath $entry.Path `
                        -Bytes $indexBytes
                } else {
                    Add-ScanTarget `
                        -Targets $scanTargets `
                        -SourcePath $entry.Path `
                        -DisplayPath "$($entry.Path) [index]" `
                        -Bytes $indexBytes
                    Add-ScanTarget `
                        -Targets $scanTargets `
                        -SourcePath $entry.Path `
                        -DisplayPath "$($entry.Path) [worktree]" `
                        -Bytes $worktreeState.Bytes
                }
            }

            # Re-read the exact raw stage listing after every index/worktree
            # snapshot has been captured. An index mutation during the scan
            # invalidates the result even when all already-read blobs were
            # internally consistent.
            $indexVerifyResult = Invoke-ScannerGitProcess `
                -FileName $gitExe.Source `
                -Arguments @('-C', $root, 'ls-files', '-z', '--stage', '--') `
                -IsolationRoot $gitIsolationRoot `
                -WorkingDirectory $root `
                -MaxStdoutBytes $maxGitMetadataBytes
            if (-not (Test-BoundedProcessHealthy -Result $indexVerifyResult) -or
                $indexVerifyResult.ExitCode -ne 0) {
                Stop-ScanIntegrityFailure -Reason 'git-index-verify'
            }
            if (-not (Test-ByteArraysEqual `
                -Left $indexResult.StdoutBytes `
                -Right $indexVerifyResult.StdoutBytes)) {
                Stop-ScanIntegrityFailure -Reason 'git-index-drift'
            }
        } elseif ($ScanMode -eq 'tracked') {
            Stop-ScanIntegrityFailure -Reason 'tracked-mode-unavailable'
        } elseif (Test-HasGitMetadataAncestor -StartPath $root) {
            Stop-ScanIntegrityFailure -Reason 'git-probe'
        }
    }
    finally {
        if ($TestOnlyCreateCleanupUnknownEntry) {
            [IO.File]::WriteAllText(
                (Join-Path $gitIsolationRoot 'test-only-unexpected-entry'),
                'synthetic cleanup boundary fixture',
                [Text.UTF8Encoding]::new($false)
            )
        }
        Remove-ScannerIsolationDirectory -LiteralPath $gitIsolationRoot
    }
} elseif ($ScanMode -eq 'tracked') {
    Stop-ScanIntegrityFailure -Reason 'tracked-mode-unavailable'
} elseif ($ScanMode -ne 'worktree' -and
    (Test-HasGitMetadataAncestor -StartPath $root)) {
    Stop-ScanIntegrityFailure -Reason 'git-unavailable'
}

if ($usingGitIndex) {
    $selectedMode = 'tracked'
} else {
    $selectedMode = 'worktree'
    # Enumerate one directory at a time rather than using recursive provider
    # traversal. Every directory is checked before descent, so a junction or
    # POSIX symlink cannot redirect the fallback scan outside the explicit root.
    $excludedDirectoryNames = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@(
            '.git',
            'node_modules',
            '.cache',
            '__pycache__',
            '.test-tmp',
            '.claude',
            '.codex'
        ),
        $pathComparer
    )
    $pendingDirectories = New-Object `
        'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pendingDirectories.Push([System.IO.DirectoryInfo]$rootItem)
    while ($pendingDirectories.Count -gt 0) {
        Assert-ScanDeadline
        $directory = $pendingDirectories.Pop()
        try {
            # Enumerate lazily so the entry budget applies before a hostile
            # directory can be materialized as one large PowerShell array.
            $children = $directory.EnumerateFileSystemInfos()
        }
        catch {
            Stop-ScanIntegrityFailure -Reason 'working-tree-enumeration'
        }
        try {
            foreach ($child in $children) {
                Assert-ScanDeadline
                $script:workingTreeEntryCount++
                if ($script:workingTreeEntryCount -gt
                    $maxWorkingTreeEntries) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'working-tree-entry-budget'
                }
                if ($child -is [System.IO.DirectoryInfo]) {
                    if ($excludedDirectoryNames.Contains($child.Name)) {
                        continue
                    }
                    if (Test-IsReparsePoint -Item $child) {
                        Stop-ScanIntegrityFailure `
                            -Reason 'working-tree-reparse-directory'
                    }
                    $pendingDirectories.Push(
                        [System.IO.DirectoryInfo]$child
                    )
                    continue
                }
                if ([string]::Equals(
                        $child.Name,
                        '.git',
                        $pathComparison
                    ) -or
                    -not (Test-IsTextFile -FullPath $child.FullName)) {
                    continue
                }
                if (Test-IsReparsePoint -Item $child) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'working-tree-reparse-file'
                }

                $relative = $child.FullName
                $rootBoundary = $root.TrimEnd([char]47, [char]92) +
                    [IO.Path]::DirectorySeparatorChar
                if (-not $relative.StartsWith(
                    $rootBoundary,
                    $pathComparison
                )) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'working-tree-path-boundary'
                }
                $relative = $relative.Substring(
                    $rootBoundary.Length
                ).Replace(
                    [IO.Path]::DirectorySeparatorChar,
                    [char]47
                )
                $worktreeState = Get-SafeTrackedWorktreeState `
                    -RepositoryRoot $root `
                    -GitPath $relative `
                    -Mode '100644'
                if ($worktreeState.State -ne 'regular') {
                    Stop-ScanIntegrityFailure `
                        -Reason 'working-tree-type-drift'
                }
                Add-ScanTarget `
                    -Targets $scanTargets `
                    -SourcePath $relative `
                    -DisplayPath $relative `
                    -Bytes $worktreeState.Bytes
            }
        }
        catch {
            Stop-ScanIntegrityFailure -Reason 'working-tree-enumeration'
        }
    }
}

# 確定snapshotをstrict UTF-8で逐次走査し、line/match/findingの全budgetを消費する。
foreach ($target in $scanTargets) {
    Assert-ScanDeadline
    if ($findingsTruncated) {
        break
    }
    $relative = $target.DisplayPath
    $lineNumber = 0

    # Decode the exact index/worktree snapshot strictly as UTF-8. Invalid bytes
    # fail closed instead of being replaced with U+FFFD, which could hide a
    # marker boundary differently across Windows PowerShell and PowerShell 7.
    try {
        $text = [System.Text.UTF8Encoding]::new(
            $false,
            $true
        ).GetString([byte[]]$target.Bytes)
        Assert-ScanDeadline
    }
    catch {
        Stop-ScanIntegrityFailure -Reason 'scan-target-encoding'
    }
    $lineReader = New-Object System.IO.StringReader($text)
    try {
        # StringReader avoids the full line-object array created by `-split`.
        # The explicit total line budget also bounds zero-length-line inputs.
        while (-not $findingsTruncated -and $lineReader.Peek() -ge 0) {
            Assert-ScanDeadline
            if ($script:totalScanLines -ge $maxScanLines) {
                Stop-ScanIntegrityFailure -Reason 'scan-line-budget'
            }
            $line = $lineReader.ReadLine()
            $script:totalScanLines++
            $lineNumber++

            # Walk matches lazily so one marker-dense line cannot allocate an
            # unbounded MatchCollection before the finding cap is applied.
            $githubMatch = Get-FirstBoundedRegexMatch `
                -InputText $line `
                -Regex $githubUrlRegex
            while ($githubMatch.Success) {
                Assert-ScanDeadline
                $script:regexMatchCount++
                if ($script:regexMatchCount -gt $maxRegexMatches) {
                    Stop-ScanIntegrityFailure `
                        -Reason 'scan-regex-match-budget'
                }
                $ownRepoMatch = Get-FirstBoundedRegexMatch `
                    -InputText $githubMatch.Value `
                    -Regex $ownRepoUrlRegex
                if (-not $ownRepoMatch.Success -and
                    -not (Add-ScanFinding `
                        -File $relative `
                        -Line $lineNumber `
                        -Rule 'non-allowlisted-github-repo-url')) {
                    break
                }
                $githubMatch = $githubMatch.NextMatch()
            }
            if ($findingsTruncated) {
                break
            }

            foreach ($rule in $rules) {
                Assert-ScanDeadline
                $matched = $false
                if ($rule.Kind -eq 'literal') {
                    $matched = $line.Contains($rule.Pattern)
                } elseif ($rule.Name -eq 'secret-assignment') {
                    # BatchではSET構文だけを抽出し、quoted wrapper、command
                    # separator、`/p` promptをgeneric grammarから分離する。
                    if ($target.IsWindowsBatch) {
                        $assignmentMatch = Get-FirstBoundedRegexMatch `
                            -InputText $line `
                            -Regex $windowsBatchSecretAssignmentRegex
                    } else {
                        $assignmentMatch = Get-FirstBoundedRegexMatch `
                            -InputText $line `
                            -Regex $rule.Regex
                    }
                    while ($assignmentMatch.Success) {
                        Assert-ScanDeadline
                        $script:regexMatchCount++
                        if ($script:regexMatchCount -gt
                            $maxRegexMatches) {
                            Stop-ScanIntegrityFailure `
                                -Reason 'scan-regex-match-budget'
                        }
                        $value = $assignmentMatch.Groups['value'].Value.Trim()
                        if ($value.Length -ge 2 -and
                            (
                                ($value.StartsWith("'") -and
                                    $value.EndsWith("'")) -or
                                ($value.StartsWith('"') -and
                                    $value.EndsWith('"'))
                            )) {
                            $value = $value.Substring(
                                1,
                                $value.Length - 2
                            ).Trim()
                        }
                        $placeholderMatch = Get-FirstBoundedRegexMatch `
                            -InputText $value `
                            -Regex $secretAssignmentPlaceholderRegex
                        $isPlaceholder = $placeholderMatch.Success
                        if (-not $isPlaceholder -and
                            $target.IsWindowsBatch) {
                            $batchPlaceholderMatch = Get-FirstBoundedRegexMatch `
                                -InputText $value `
                                -Regex $windowsBatchRuntimePlaceholderRegex
                            $isPlaceholder = $batchPlaceholderMatch.Success
                        }
                        if (-not [string]::IsNullOrWhiteSpace($value) -and
                            -not $isPlaceholder) {
                            $matched = $true
                            break
                        }
                        $assignmentMatch = $assignmentMatch.NextMatch()
                    }
                } else {
                    $ruleMatch = Get-FirstBoundedRegexMatch `
                        -InputText $line `
                        -Regex $rule.Regex
                    while ($ruleMatch.Success) {
                        Assert-ScanDeadline
                        $script:regexMatchCount++
                        if ($script:regexMatchCount -gt
                            $maxRegexMatches) {
                            Stop-ScanIntegrityFailure `
                                -Reason 'scan-regex-match-budget'
                        }
                        if ([string]::IsNullOrEmpty($rule.Allowlist)) {
                            $matched = $true
                            break
                        }
                        $allowlistMatch = Get-FirstBoundedRegexMatch `
                            -InputText $ruleMatch.Value `
                            -Regex $rule.AllowlistRegex
                        if (-not $allowlistMatch.Success) {
                            $matched = $true
                            break
                        }
                        $ruleMatch = $ruleMatch.NextMatch()
                    }
                }

                if ($matched) {
                    [void](Add-ScanFinding `
                        -File $relative `
                        -Line $lineNumber `
                        -Rule $rule.Name)
                    if ($findingsTruncated) {
                        break
                    }
                }
            }
        }
    }
    finally {
        $lineReader.Dispose()
    }
}

# regex走査中に同一pathへ戻された置換も見逃さない。stable file ID/dev+inodeと
# 内容hashをno-follow経路から再取得し、missingを含む全snapshotを照合する。
foreach ($worktreeSnapshot in $worktreeSnapshots) {
    Assert-ScanDeadline
    try {
        $snapshotMatches = $worktreeSnapshot.MatchesCurrent()
        Assert-ScanDeadline
    }
    catch {
        Stop-ScanIntegrityFailure -Reason 'worktree-report-snapshot'
    }
    if (-not $snapshotMatches) {
        Stop-ScanIntegrityFailure -Reason 'worktree-drift'
    }
}

# The first raw recheck protects snapshot construction. Repeat it after content
# matching so an index change during a long regex scan cannot be reported as a
# success for a repository state that is no longer current.
if ($usingGitIndex) {
    Assert-ScanDeadline
    New-ScannerIsolationDirectory -LiteralPath $gitIsolationRoot
    try {
        $reportVerifyResult = Invoke-ScannerGitProcess `
            -FileName $gitExe.Source `
            -Arguments @('-C', $root, 'ls-files', '-z', '--stage', '--') `
            -IsolationRoot $gitIsolationRoot `
            -WorkingDirectory $root `
            -MaxStdoutBytes $maxGitMetadataBytes
        if (-not (Test-BoundedProcessHealthy -Result $reportVerifyResult) -or
            $reportVerifyResult.ExitCode -ne 0) {
            Stop-ScanIntegrityFailure -Reason 'git-index-report-verify'
        }
        if (-not (Test-ByteArraysEqual `
            -Left $indexResult.StdoutBytes `
            -Right $reportVerifyResult.StdoutBytes)) {
            Stop-ScanIntegrityFailure -Reason 'git-index-drift'
        }
        $reportDebugResult = Invoke-ScannerGitProcess `
            -FileName $gitExe.Source `
            -Arguments @(
                '-C',
                $root,
                'ls-files',
                '-z',
                '--stage',
                '--debug',
                '--'
            ) `
            -IsolationRoot $gitIsolationRoot `
            -WorkingDirectory $root `
            -MaxStdoutBytes $maxGitMetadataBytes
        if (-not (Test-BoundedProcessHealthy -Result $reportDebugResult) -or
            $reportDebugResult.ExitCode -ne 0) {
            Stop-ScanIntegrityFailure `
                -Reason 'git-index-report-debug-verify'
        }
        if (-not (Test-ByteArraysEqual `
            -Left $debugResult.StdoutBytes `
            -Right $reportDebugResult.StdoutBytes)) {
            Stop-ScanIntegrityFailure -Reason 'git-index-drift'
        }
    }
    finally {
        Remove-ScannerIsolationDirectory -LiteralPath $gitIsolationRoot
    }
}

if ($findings.Count -gt 0) {
    Assert-ScanDeadline
    # prefix/header/row/truncation noticeと実OS newlineを同じpayloadへ積み、
    # 最終UTF-8 bytesを一度だけstdoutへ書く。Format-Tableへ敵対的pathを
    # 渡さず、host依存の折返し・部分table・CRLF換算漏れを防ぐ。
    $reportNewline = [Environment]::NewLine
    $reportPrefix =
        "Private marker scan failed (mode: $selectedMode). Values are redacted:"
    $reportHeader = "File`tLine`tRule`tValue"
    $reportBuilder = New-Object Text.StringBuilder
    [void]$reportBuilder.Append($reportPrefix)
    [void]$reportBuilder.Append($reportNewline)
    [void]$reportBuilder.Append($reportHeader)
    [void]$reportBuilder.Append($reportNewline)
    $reportByteCount = [Text.Encoding]::UTF8.GetByteCount(
        $reportBuilder.ToString()
    )
    foreach ($finding in ($findings | Sort-Object File, Line, Rule)) {
        Assert-ScanDeadline
        $reportRow = "{0}`t{1}`t{2}`t{3}" -f @(
            $finding.File,
            $finding.Line,
            $finding.Rule,
            $finding.Match
        )
        $rowByteCount = [Text.Encoding]::UTF8.GetByteCount(
            $reportRow + $reportNewline
        )
        if (($reportByteCount + $rowByteCount) -gt
            $maxFindingOutputBytes) {
            Stop-ScanIntegrityFailure -Reason 'finding-output-budget'
        }
        [void]$reportBuilder.Append($reportRow)
        [void]$reportBuilder.Append($reportNewline)
        $reportByteCount += $rowByteCount
    }
    if ($findingsTruncated) {
        $truncationNotice =
            "Additional findings omitted after $maxFindings entries."
        $truncationByteCount = [Text.Encoding]::UTF8.GetByteCount(
            $truncationNotice + $reportNewline
        )
        if (($reportByteCount + $truncationByteCount) -gt
            $maxFindingOutputBytes) {
            Stop-ScanIntegrityFailure -Reason 'finding-output-budget'
        }
        [void]$reportBuilder.Append($truncationNotice)
        [void]$reportBuilder.Append($reportNewline)
        $reportByteCount += $truncationByteCount
    }
    $summaryLine = "{0} finding(s) across {1} scanned file(s)." -f @(
        $findings.Count,
        $scanTargets.Count
    )
    $summaryByteCount = [Text.Encoding]::UTF8.GetByteCount(
        $summaryLine + $reportNewline
    )
    if (($reportByteCount + $summaryByteCount) -gt
        $maxFindingOutputBytes) {
        Stop-ScanIntegrityFailure -Reason 'finding-output-budget'
    }
    [void]$reportBuilder.Append($summaryLine)
    [void]$reportBuilder.Append($reportNewline)
    $reportByteCount += $summaryByteCount

    Assert-ScanDeadline
    [byte[]]$reportBytes = [Text.Encoding]::UTF8.GetBytes(
        $reportBuilder.ToString()
    )
    if ($reportBytes.Length -ne $reportByteCount -or
        $reportBytes.Length -gt $maxFindingOutputBytes) {
        Stop-ScanIntegrityFailure -Reason 'finding-output-budget'
    }
    Assert-ScanDeadline
    $reportStream = [Console]::OpenStandardOutput()
    try {
        $reportStream.Write($reportBytes, 0, $reportBytes.Length)
        $reportStream.Flush()
    }
    finally {
        $reportStream.Dispose()
    }
    exit 1
}

$successLine = "Private marker scan passed (mode: $selectedMode, " +
    "$($scanTargets.Count) file(s))." + [Environment]::NewLine
[byte[]]$successBytes = [Text.Encoding]::UTF8.GetBytes($successLine)
if ($successBytes.Length -gt $maxFindingOutputBytes) {
    Stop-ScanIntegrityFailure -Reason 'success-output-budget'
}
Assert-ScanDeadline
$successStream = [Console]::OpenStandardOutput()
try {
    $successStream.Write($successBytes, 0, $successBytes.Length)
    $successStream.Flush()
}
finally {
    $successStream.Dispose()
}
exit 0
