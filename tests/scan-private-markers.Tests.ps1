[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scannerPath = Join-Path $repoRoot 'scripts/scan-private-markers.ps1'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agentic-coding-security-gate-tests-" + [System.Guid]::NewGuid().ToString('N'))
$failures = New-Object System.Collections.Generic.List[string]

function New-FixtureFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $fullPath = Join-Path $fixtureRoot $RelativePath
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }

    Set-Content -LiteralPath $fullPath -Value $Content -Encoding utf8
}

function Invoke-Scanner {
    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scannerPath -Path $fixtureRoot 2>&1

    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | Out-String)
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        $Actual,

        [Parameter(Mandatory = $true)]
        $Expected,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected' but got '$Actual'."
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Needle,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Text.Contains($Needle)) {
        throw "$Message Missing '$Needle'. Output: $Text"
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Needle,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Text.Contains($Needle)) {
        throw "$Message Unexpected '$Needle'. Output: $Text"
    }
}

function Invoke-Test {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Body
    )

    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

    try {
        & $Body
        Write-Host "PASS $Name"
    } catch {
        $script:failures.Add("${Name}: $($_.Exception.Message)") | Out-Null
        Write-Host "FAIL $Name"
        Write-Host $_.Exception.Message
    }
}

try {
    Invoke-Test 'passes a safe public fixture' {
        $ownRepoUrl = 'https://github.com/h8nc4y/agentic-coding-security-gate.git'
        New-FixtureFile -RelativePath 'README.md' -Content @"
# Safe fixture

Clone this public repository:

$ownRepoUrl

Use synthetic examples only.
"@

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'Safe public fixture should pass.'
        Assert-Contains -Text $result.Output -Needle 'Private marker scan passed' -Message 'Passing scan should report success.'
    }

    Invoke-Test 'flags non-allowlisted GitHub repository URLs without leaking values' {
        $externalRepoUrl = 'https://github.com/' + 'example/private-fixture'
        New-FixtureFile -RelativePath 'docs/public-summary.md' -Content "External reproduction: $externalRepoUrl"

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'External repository URL should fail.'
        Assert-Contains -Text $result.Output -Needle 'non-allowlisted-github-repo-url' -Message 'Finding should name the URL rule.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Finding should show redaction.'
        Assert-NotContains -Text $result.Output -Needle $externalRepoUrl -Message 'Finding output should not replay the URL.'
    }

    Invoke-Test 'flags marker-like values even inside a scanner-named script path' {
        $marker = ('s' + 'k-fixture-value-that-must-stay-redacted')
        New-FixtureFile -RelativePath 'scripts/scan-private-markers.ps1' -Content "`$fixture = '$marker'"

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Scanner-named scripts should not be blanket-exempt.'
        Assert-Contains -Text $result.Output -Needle 'scripts/scan-private-markers.ps1' -Message 'Finding should include the relative script path.'
        Assert-Contains -Text $result.Output -Needle 'openai-api-key-prefix' -Message 'Finding should name the marker rule.'
        Assert-NotContains -Text $result.Output -Needle $marker -Message 'Finding output should not replay marker-like values.'
    }
} finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Test failures:'
    foreach ($failure in $failures) {
        Write-Host "- $failure"
    }
    exit 1
}

Write-Host ''
Write-Host 'All scan-private-markers tests passed.'
