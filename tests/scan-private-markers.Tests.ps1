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
    # Fixture roots are temporary non-git directories; force worktree mode so
    # host-specific git stderr behavior does not mask scanner assertions.
    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scannerPath -Path $fixtureRoot -ScanMode worktree 2>&1

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

    Invoke-Test 'does not treat codex task filenames as OpenAI keys' {
        New-FixtureFile -RelativePath 'TASKS_BACKLOG.md' -Content 'See docs/codex-task-scanner-hardening.md for the synthetic handoff.'

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'The scanner should not flag the sk- fragment inside task-.'
        Assert-Contains -Text $result.Output -Needle 'Private marker scan passed' -Message 'Scan should pass.'
    }

    # --- New (H-B) secret-format regression tests ------------------------
    # Each case: the scanner must (a) exit 1, (b) name the rule, and
    # (c) never replay the synthetic value. Values are assembled by
    # concatenation so this test file does not self-trigger the scanner.
    function Test-DetectsAndRedacts {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$Marker,
            [Parameter(Mandatory = $true)][string]$Rule
        )

        Invoke-Test "detects $Name and keeps the value redacted" {
            New-FixtureFile -RelativePath 'docs/leak.md' -Content "Synthetic credential: $Marker"

            $result = Invoke-Scanner

            Assert-Equal -Actual $result.ExitCode -Expected 1 -Message "$Name should fail the scan."
            Assert-Contains -Text $result.Output -Needle $Rule -Message "Finding should name the $Name rule."
            Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Finding should show redaction.'
            Assert-NotContains -Text $result.Output -Needle $Marker -Message "Finding output should not replay the $Name value."
        }
    }

    Test-DetectsAndRedacts -Name 'AWS access key id' `
        -Marker ('AKIA' + 'ABCDEFGHIJKLMNOP') -Rule 'aws-access-key-id'

    Test-DetectsAndRedacts -Name 'GCP API key' `
        -Marker ('AIza' + 'SyA0123456789abcdefghijklmnopqrstuvw') -Rule 'gcp-api-key'

    Test-DetectsAndRedacts -Name 'npm auth token assignment' `
        -Marker ('//registry.npmjs.org/:_auth' + 'Tok' + 'en=abcdef0123456789abcdef0123456789') -Rule 'npm-auth-token-assignment'

    Test-DetectsAndRedacts -Name 'PyPI API token prefix' `
        -Marker ('pypi-' + 'AgEIcHlwaS5vcmcCsyntheticfixture0000000000') -Rule 'python-package-index-token-prefix'

    Test-DetectsAndRedacts -Name 'RubyGems credentials assignment' `
        -Marker (':rubygems_' + 'api_' + 'key: ' + 'abcd' + 'ef0123456789abcdef0123456789') -Rule 'ruby-package-credentials-assignment'

    # GitHub classic token prefixes differ by token source; fixture all public
    # prefixes so ghp_ is not the only covered case.
    Test-DetectsAndRedacts -Name 'GitHub personal access token prefix' -Marker ('g' + 'hp_' + 'syntheticfixture0123456789abcdef') -Rule 'github-classic-token-prefix'

    Test-DetectsAndRedacts -Name 'GitHub OAuth token prefix' -Marker ('g' + 'ho_' + 'syntheticfixture0123456789abcdef') -Rule 'github-classic-token-prefix'

    Test-DetectsAndRedacts -Name 'GitHub user-to-server token prefix' -Marker ('g' + 'hu_' + 'syntheticfixture0123456789abcdef') -Rule 'github-classic-token-prefix'

    Test-DetectsAndRedacts -Name 'GitHub server-to-server token prefix' -Marker ('g' + 'hs_' + 'syntheticfixture0123456789abcdef') -Rule 'github-classic-token-prefix'

    Test-DetectsAndRedacts -Name 'GitHub refresh token prefix' -Marker ('g' + 'hr_' + 'syntheticfixture0123456789abcdef') -Rule 'github-classic-token-prefix'

    Invoke-Test 'does not flag npm auth token environment placeholder' {
        New-FixtureFile -RelativePath '.npmrc' -Content ('//registry.npmjs.org/:_auth' + 'Tok' + 'en=${NODE_AUTH_TOKEN}')

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'Environment-variable npm auth placeholders should not fail.'
        Assert-Contains -Text $result.Output -Needle 'Private marker scan passed' -Message 'Scan should pass.'
    }

    Test-DetectsAndRedacts -Name 'Slack user token' `
        -Marker ('xo' + 'xp-0000000000-0000000000-abcdefghij') -Rule 'slack-token-prefix'

    Test-DetectsAndRedacts -Name 'Slack app-level token' `
        -Marker ('xa' + 'pp-1-A000-000-abcdef0123456789') -Rule 'slack-app-token-prefix'

    Test-DetectsAndRedacts -Name 'Anthropic API key prefix' `
        -Marker ('sk-ant-' + 'api03-syntheticfixture000000000000') -Rule 'anthropic-api-key-prefix'

    Test-DetectsAndRedacts -Name 'JWT token shape' `
        -Marker ('eyJ' + 'hbGciOiJIUzI1NiJ9.eyJzdWIiOiJmaXh0dXJlIn0.signaturepart') -Rule 'jwt-token-shape'

    Test-DetectsAndRedacts -Name 'Stripe live secret key' `
        -Marker ('sk' + '_live_0123456789abcdefABCDEF') -Rule 'stripe-live-key'

    Test-DetectsAndRedacts -Name 'Stripe live restricted key' `
        -Marker ('rk' + '_live_0123456789abcdefABCDEF') -Rule 'stripe-live-key'

    Test-DetectsAndRedacts -Name 'RSA PEM private key header' `
        -Marker ('-----BEGIN ' + 'RSA PRIVATE KEY-----') -Rule 'private-key-block'

    Test-DetectsAndRedacts -Name 'OpenSSH PEM private key header' `
        -Marker ('-----BEGIN ' + 'OPENSSH PRIVATE KEY-----') -Rule 'private-key-block'

    Test-DetectsAndRedacts -Name 'EC PEM private key header' `
        -Marker ('-----BEGIN ' + 'EC PRIVATE KEY-----') -Rule 'private-key-block'

    Test-DetectsAndRedacts -Name 'plain PEM private key header' `
        -Marker ('-----BEGIN ' + 'PRIVATE KEY-----') -Rule 'private-key-block'

    # --- False-positive suppression regression tests ---------------------
    Invoke-Test 'does not flag a bare Bearer word without a token value' {
        New-FixtureFile -RelativePath 'docs/usage.md' -Content @"
# Auth notes

Send the credential using the Bearer scheme described above.
"@

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'Bearer word with no token value should not fail.'
        Assert-Contains -Text $result.Output -Needle 'Private marker scan passed' -Message 'Scan should pass.'
    }

    Invoke-Test 'flags a Bearer header that carries a token value' {
        # Assemble the header by concatenation so this test file does not itself
        # become a scanner finding (the variable holding it is named neutrally).
        $authValue = ('Bear' + 'er ' + 'abcdef0123456789')
        New-FixtureFile -RelativePath 'docs/header.md' -Content "Authorization: $authValue"

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Bearer header with a token value should fail.'
        Assert-Contains -Text $result.Output -Needle 'bearer-token-header' -Message 'Finding should name the header rule.'
        Assert-NotContains -Text $result.Output -Needle $authValue -Message 'Finding output should not replay the header value.'
    }

    Invoke-Test 'does not flag documentation-safe placeholder emails' {
        New-FixtureFile -RelativePath 'docs/contact.md' -Content @"
# Contact

Reach the demo bot at bot@example.com or maintainer@example.org for synthetic tests.
"@

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'Placeholder emails should not fail.'
        Assert-Contains -Text $result.Output -Needle 'Private marker scan passed' -Message 'Scan should pass.'
    }

    Invoke-Test 'flags a non-allowlisted real email address' {
        $email = ('alice' + '@' + 'realcorp.io')
        New-FixtureFile -RelativePath 'docs/people.md' -Content "Owner: $email"

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Real email should fail.'
        Assert-Contains -Text $result.Output -Needle 'email-address' -Message 'Finding should name the email rule.'
        Assert-NotContains -Text $result.Output -Needle $email -Message 'Finding output should not replay the email.'
    }

    Invoke-Test 'skips binary-extension files instead of line-walking them' {
        # A .png whose bytes happen to contain a marker prefix must be skipped.
        $marker = ('s' + 'k-binary-should-be-skipped')
        New-FixtureFile -RelativePath 'examples/screenshot.png' -Content "binary-ish $marker"

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'Binary-extension files should be skipped.'
        Assert-Contains -Text $result.Output -Needle 'Private marker scan passed' -Message 'Scan should pass.'
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
exit 0
