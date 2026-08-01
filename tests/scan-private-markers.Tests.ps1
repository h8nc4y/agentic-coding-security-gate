[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This file predates its Pester-style suffix and remains the zero-dependency
# executable harness used by CI. When Pester discovers it, register one real
# test that launches the same harness in a clean child pwsh process. This keeps
# direct execution unchanged while preventing a misleading 0-tests pass.
$invokedByPester = @(
    Get-PSCallStack | Where-Object {
        $_.Command -eq 'Invoke-Pester' -or
        $_.InvocationInfo.MyCommand.ModuleName -eq 'Pester'
    }
).Count -gt 0

if ($invokedByPester) {
    $harnessPath = $PSCommandPath

    Describe 'scan-private-markers regression harness' {
        It 'passes all dependency-free regression cases' {
            $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $harnessPath 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0) {
                $summary = $output | Select-Object -Last 20 | Out-String
                throw "Dependency-free scanner harness failed with exit code $exitCode.`n$summary"
            }
        }
    }

    return
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scannerPath = Join-Path $repoRoot 'scripts/scan-private-markers.ps1'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agentic-coding-security-gate-tests-" + [System.Guid]::NewGuid().ToString('N'))
$failures = New-Object System.Collections.Generic.List[string]
$scannerPowerShell = 'pwsh'

if ($null -eq (Get-Command $scannerPowerShell -ErrorAction SilentlyContinue)) {
    # Prefer the same executable that is running this harness when PowerShell 7
    # is not on PATH. CI still uses pwsh; this only keeps local fallback runs
    # from failing before scanner behavior is exercised.
    $currentProcess = Get-Process -Id $PID
    if (-not [string]::IsNullOrWhiteSpace($currentProcess.Path)) {
        $scannerPowerShell = $currentProcess.Path
    } else {
        $scannerPowerShell = 'powershell.exe'
    }
}

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
    $output = & $scannerPowerShell -NoProfile -ExecutionPolicy Bypass -File $scannerPath -Path $fixtureRoot -ScanMode worktree 2>&1

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

    Test-DetectsAndRedacts -Name 'Hugging Face token prefix' `
        -Marker ('h' + 'f_' + 'synthetic012345') -Rule 'huggingface-token-prefix'

    Test-DetectsAndRedacts -Name 'Slack incoming webhook URL' `
        -Marker ('https://hooks.slack.' + 'com/services/' + 'T00000000/B00000000/abcdefghi') -Rule 'slack-webhook-url'

    Test-DetectsAndRedacts -Name 'SendGrid API key prefix' `
        -Marker ('S' + 'G.' + 'abcdefghijklmnop' + '.' + 'qrstuvwxyzABCDEF') -Rule 'sendgrid-api-key-prefix'

    Test-DetectsAndRedacts -Name 'GitLab personal access token prefix' `
        -Marker ('gl' + 'pat-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab deploy token prefix' `
        -Marker ('gl' + 'dt-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab CI job token prefix' `
        -Marker ('gl' + 'cbt-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab OAuth application secret prefix' `
        -Marker ('gl' + 'oas-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab runner authentication token prefix' `
        -Marker ('gl' + 'rt-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab trigger token prefix' `
        -Marker ('gl' + 'ptt-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab feed token prefix' `
        -Marker ('gl' + 'ft-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab incoming mail token prefix' `
        -Marker ('gl' + 'imt-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab Kubernetes agent token prefix' `
        -Marker ('gl' + 'agent-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab workspace token prefix' `
        -Marker ('gl' + 'wt-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab SCIM token prefix' `
        -Marker ('gl' + 'soat-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab feature flags client token prefix' `
        -Marker ('gl' + 'ffct-' + 'syntheticfixture0000000000') -Rule 'gitlab-token-prefix'

    Test-DetectsAndRedacts -Name 'GitLab session cookie value' `
        -Marker ('_gitlab_' + 'session=' + 'syntheticfixture0000000000') -Rule 'gitlab-session-cookie'

    Invoke-Test 'does not flag npm auth token environment placeholder' {
        New-FixtureFile -RelativePath '.npmrc' -Content ('//registry.npmjs.org/:_auth' + 'Tok' + 'en=${NODE_AUTH_TOKEN}')

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'Environment-variable npm auth placeholders should not fail.'
        Assert-Contains -Text $result.Output -Needle 'Private marker scan passed' -Message 'Scan should pass.'
    }

    Invoke-Test 'flags a prefixed secret assignment with a literal value' {
        $assignment = ('DB_' + 'PASSWORD' + '=' + 'syntheticfixturevalue')
        $quotedAssignment = ('SERVICE_' + 'TOKEN' + '=' + "'syntheticquotedvalue'")
        New-FixtureFile -RelativePath 'config.txt' -Content (@($assignment, $quotedAssignment) -join [Environment]::NewLine)

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Prefixed secret keys with literal values should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should name the assignment rule.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Finding should show redaction.'
        Assert-NotContains -Text $result.Output -Needle $assignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $quotedAssignment -Message 'Finding output should not replay quoted assignments.'
    }

    Invoke-Test 'allows recognized secret assignment placeholders and empty values' {
        $assignments = @(
            ('PASSWORD' + '=' + '${PASSWORD}'),
            ('PASSWORD' + '=' + '"${PASSWORD}"'),
            ('DB_' + 'PASSWORD' + '=' + '${DB_PASSWORD}'),
            ('API_' + 'TOKEN' + '=' + '$env:API_TOKEN'),
            ('CLIENT_' + 'SECRET' + '=' + 'process.env.CLIENT_SECRET'),
            ('ACCESS_' + 'TOKEN' + '=' + '${{ secrets.ACCESS_TOKEN }}'),
            ('API_' + 'KEY' + '=' + '<redacted>'),
            ('EMPTY_' + 'PASSWORD' + '=')
        )
        New-FixtureFile -RelativePath 'config.txt' -Content ($assignments -join [Environment]::NewLine)

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'Recognized placeholders and empty assignments should not fail.'
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

    Invoke-Test 'does not flag a plain SendGrid abbreviation' {
        New-FixtureFile -RelativePath 'docs/sendgrid.md' -Content 'SG. is a common abbreviation in this synthetic note.'

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'Plain SG. text should not fail.'
        Assert-Contains -Text $result.Output -Needle 'Private marker scan passed' -Message 'Scan should pass.'
    }

    Invoke-Test 'does not flag a Hugging Face-like fragment inside a word' {
        New-FixtureFile -RelativePath 'docs/huggingface.md' -Content 'Synthetic compound words: shelf_hf_note and shelfhf_notemark should stay public-safe.'

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 0 -Message 'hf_ with an alphanumeric left boundary should not fail.'
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

    Invoke-Test 'scans dotenv filenames and keeps assigned values redacted' {
        # Dotenv variants carry text configuration even though FileInfo reports
        # `.env`, `.example`, or `.local` as extensions outside the allowlist.
        $baseAssignment = ('DB_' + 'PASSWORD' + '=' + 'syntheticdotenvvalue')
        $exampleAssignment = ('SERVICE_' + 'TOKEN' + '=' + 'syntheticexamplevalue')
        $localAssignment = ('CLIENT_' + 'SECRET' + '=' + 'syntheticlocalvalue')
        New-FixtureFile -RelativePath '.env' -Content $baseAssignment
        New-FixtureFile -RelativePath '.env.example' -Content $exampleAssignment
        New-FixtureFile -RelativePath '.env.local' -Content $localAssignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Dotenv files with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle '.env' -Message 'Finding should include the base dotenv path.'
        Assert-Contains -Text $result.Output -Needle '.env.example' -Message 'Finding should include the example dotenv path.'
        Assert-Contains -Text $result.Output -Needle '.env.local' -Message 'Finding should include the local dotenv path.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Dotenv findings should remain redacted.'
        Assert-Contains -Text $result.Output -Needle '3 finding(s) across 3 scanned file(s).' -Message 'Every dotenv variant should be scanned.'
        Assert-NotContains -Text $result.Output -Needle $baseAssignment -Message 'Finding output should not replay the base assignment.'
        Assert-NotContains -Text $result.Output -Needle $exampleAssignment -Message 'Finding output should not replay the example assignment.'
        Assert-NotContains -Text $result.Output -Needle $localAssignment -Message 'Finding output should not replay the local assignment.'
    }

    Invoke-Test 'scans case-insensitive JSON Lines files with existing rules' {
        # JSON Lines is UTF-8 text with one JSON value per line. Route lower-
        # and mixed-case suffixes without adding format-specific semantics.
        $jsonlEmail = ('alice' + '@' + 'realcorp.io')
        $record = ('{"contact":"' + $jsonlEmail + '"}')
        New-FixtureFile -RelativePath 'events/synthetic-records.jsonl' -Content $record
        New-FixtureFile -RelativePath 'events/synthetic-audit.JsOnL' -Content $record

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'JSON Lines files with existing private markers should fail.'
        Assert-Contains -Text $result.Output -Needle 'email-address' -Message 'Finding should use the existing email rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-records.jsonl' -Message 'Finding should include the lowercase JSONL path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-audit.JsOnL' -Message 'Finding should include the mixed-case JSONL path.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Both JSONL extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'JSONL findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $record -Message 'Finding output should not replay the JSON record.'
        Assert-NotContains -Text $result.Output -Needle $jsonlEmail -Message 'Finding output should not replay the email value.'
    }

    Invoke-Test 'scans compound example suffixes only after known text extensions' {
        # Do not treat `.example` itself as text. Route only samples whose
        # inner suffix is a known text type, regardless of suffix casing.
        $compoundEmail = ('alice' + '@' + 'realcorp.io')
        $payload = ('{"contact":"' + $compoundEmail + '"}')
        New-FixtureFile -RelativePath 'templates/CLAUDE.md.example' -Content $payload
        New-FixtureFile -RelativePath 'templates/settings.JsOn.ExAmPlE' -Content $payload
        New-FixtureFile -RelativePath 'templates/opaque.example' -Content $payload
        New-FixtureFile -RelativePath 'templates/CLAUDE.md.example.example' -Content $payload

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Known text files with an example suffix should fail on existing private markers.'
        Assert-Contains -Text $result.Output -Needle 'email-address' -Message 'Finding should use the existing email rule.'
        Assert-Contains -Text $result.Output -Needle 'CLAUDE.md.example' -Message 'Finding should include the lowercase compound path.'
        Assert-Contains -Text $result.Output -Needle 'settings.JsOn.ExAmPlE' -Message 'Finding should include the mixed-case compound path.'
        Assert-NotContains -Text $result.Output -Needle 'opaque.example' -Message 'A bare unknown example suffix should remain skipped.'
        Assert-NotContains -Text $result.Output -Needle 'CLAUDE.md.example.example' -Message 'Only one example suffix should be unwrapped.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Only known inner text extensions should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Compound example findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $payload -Message 'Finding output should not replay the sample payload.'
        Assert-NotContains -Text $result.Output -Needle $compoundEmail -Message 'Finding output should not replay the email value.'
    }

    Invoke-Test 'scans case-insensitive PEM text files and keeps private key markers redacted' {
        # Keep the existing private-key rule reachable for standard text-container extensions.
        $syntheticPemMarker = ('-----BEGIN ' + 'PRIVATE KEY-----')
        New-FixtureFile -RelativePath 'certificates/synthetic-private.pem' -Content $syntheticPemMarker
        New-FixtureFile -RelativePath 'certificates/synthetic-secondary.PeM' -Content $syntheticPemMarker

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'PEM text files with private key markers should fail.'
        Assert-Contains -Text $result.Output -Needle 'private-key-block' -Message 'Finding should name the private key rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-private.pem' -Message 'Finding should include the lowercase PEM path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-secondary.PeM' -Message 'Finding should include the mixed-case PEM path.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Both PEM extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'PEM findings should remain redacted.'
        Assert-NotContains `
            -Text $result.Output `
            -Needle ('-----BEGIN ' + 'PRIVATE KEY-----') `
            -Message 'Finding output should not replay the private key marker.'
    }

    Invoke-Test 'scans case-insensitive KEY containers and keeps private key markers redacted' {
        # A KEY file commonly contains a private key. Keep mixed-case extensions
        # reachable by the existing rule without replaying values in output.
        $syntheticKeyMarker = ('-----BEGIN ' + 'PRIVATE KEY-----')
        New-FixtureFile -RelativePath 'certificates/synthetic-private.key' -Content $syntheticKeyMarker
        New-FixtureFile -RelativePath 'certificates/synthetic-secondary.KeY' -Content $syntheticKeyMarker

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'KEY containers with private key markers should fail.'
        Assert-Contains -Text $result.Output -Needle 'private-key-block' -Message 'Finding should name the private key rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-private.key' -Message 'Finding should include the lowercase KEY path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-secondary.KeY' -Message 'Finding should include the mixed-case KEY path.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Both KEY extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'KEY findings should remain redacted.'
        Assert-NotContains `
            -Text $result.Output `
            -Needle ('-----BEGIN ' + 'PRIVATE KEY-----') `
            -Message 'Finding output should not replay the private key marker.'
    }

    Invoke-Test 'scans case-insensitive JSX and TSX sources with existing rules' {
        # JSX and TSX are text variants of already-scanned JS and TS sources.
        # Keep both extensions reachable without changing detector semantics.
        $syntheticValue = 'syntheticfixturevalue'
        $assignment = ('API_' + 'TOKEN' + '=' + $syntheticValue)
        New-FixtureFile -RelativePath 'src/synthetic-view.JsX' -Content $assignment
        New-FixtureFile -RelativePath 'src/synthetic-panel.TsX' -Content $assignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'JSX and TSX sources with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should use the existing assignment rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-view.JsX' -Message 'Finding should include the mixed-case JSX path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-panel.TsX' -Message 'Finding should include the mixed-case TSX path.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Both source extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'JSX and TSX findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $assignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $syntheticValue -Message 'Finding output should not replay the assigned value.'
    }

    Invoke-Test 'scans case-insensitive MJS CJS MTS and CTS sources with existing rules' {
        # Module-specific JS and TS extensions must reach the same existing
        # detector path without changing rule or redaction semantics.
        $syntheticValue = 'syntheticmodulefixturevalue'
        $assignment = ('API_' + 'TOKEN' + '=' + $syntheticValue)
        New-FixtureFile -RelativePath 'src/synthetic-esm.MjS' -Content $assignment
        New-FixtureFile -RelativePath 'src/synthetic-common.CjS' -Content $assignment
        New-FixtureFile -RelativePath 'src/synthetic-esm.MtS' -Content $assignment
        New-FixtureFile -RelativePath 'src/synthetic-common.CtS' -Content $assignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Module-specific JS and TS sources with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should use the existing assignment rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-esm.MjS' -Message 'Finding should include the mixed-case MJS path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-common.CjS' -Message 'Finding should include the mixed-case CJS path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-esm.MtS' -Message 'Finding should include the mixed-case MTS path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-common.CtS' -Message 'Finding should include the mixed-case CTS path.'
        Assert-Contains -Text $result.Output -Needle '4 finding(s) across 4 scanned file(s).' -Message 'All four module source extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Module source findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $assignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $syntheticValue -Message 'Finding output should not replay the assigned value.'
    }

    Invoke-Test 'scans case-insensitive Vue Svelte and Astro component sources with existing rules' {
        # Single-file component formats embed ordinary text source and must
        # reach the existing detector path without changing rule semantics.
        $syntheticValue = 'syntheticcomponentfixturevalue'
        $assignment = ('API_' + 'TOKEN' + '=' + $syntheticValue)
        New-FixtureFile -RelativePath 'src/synthetic-view.VuE' -Content $assignment
        New-FixtureFile -RelativePath 'src/synthetic-panel.SvElTe' -Content $assignment
        New-FixtureFile -RelativePath 'src/synthetic-page.AsTrO' -Content $assignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Component sources with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should use the existing assignment rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-view.VuE' -Message 'Finding should include the mixed-case Vue path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-panel.SvElTe' -Message 'Finding should include the mixed-case Svelte path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-page.AsTrO' -Message 'Finding should include the mixed-case Astro path.'
        Assert-Contains -Text $result.Output -Needle '3 finding(s) across 3 scanned file(s).' -Message 'All three component extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Component source findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $assignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $syntheticValue -Message 'Finding output should not replay the assigned value.'
    }

    Invoke-Test 'scans case-insensitive Terraform sources with existing rules' {
        # Terraform configuration and variable files are plain text. Route
        # both extensions to the existing detector without changing its rules.
        $syntheticValue = 'syntheticterraformfixturevalue'
        $assignment = ('api_' + 'token' + ' = "' + $syntheticValue + '"')
        New-FixtureFile -RelativePath 'infra/synthetic-main.Tf' -Content $assignment
        New-FixtureFile -RelativePath 'infra/synthetic-vars.TfVaRs' -Content $assignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Terraform sources with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should use the existing assignment rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-main.Tf' -Message 'Finding should include the mixed-case TF path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-vars.TfVaRs' -Message 'Finding should include the mixed-case TFVARS path.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Both Terraform extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Terraform findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $assignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $syntheticValue -Message 'Finding output should not replay the assigned value.'
    }

    Invoke-Test 'scans case-insensitive HCL sources with existing rules' {
        # HCL sources use the same text assignment form as Terraform files.
        # Keep mixed-case extensions reachable without changing detector rules.
        $syntheticValue = 'synthetichclfixturevalue'
        $assignment = ('api_' + 'token' + ' = "' + $syntheticValue + '"')
        New-FixtureFile -RelativePath 'infra/synthetic-policy.hcl' -Content $assignment
        New-FixtureFile -RelativePath 'infra/synthetic-build.HcL' -Content $assignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'HCL sources with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should use the existing assignment rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-policy.hcl' -Message 'Finding should include the lowercase HCL path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-build.HcL' -Message 'Finding should include the mixed-case HCL path.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Both HCL extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'HCL findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $assignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $syntheticValue -Message 'Finding output should not replay the assigned value.'
    }

    Invoke-Test 'scans case-insensitive Java properties files with existing rules' {
        # Java properties files are plain-text configuration. Route mixed-case
        # extensions to the existing detector without changing rule semantics.
        $syntheticValue = 'syntheticpropertiesfixturevalue'
        $assignment = ('service_' + 'token' + '=' + $syntheticValue)
        New-FixtureFile -RelativePath 'config/synthetic-app.properties' -Content $assignment
        New-FixtureFile -RelativePath 'config/synthetic-build.PrOpErTiEs' -Content $assignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Properties files with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should use the existing assignment rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-app.properties' -Message 'Finding should include the lowercase properties path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-build.PrOpErTiEs' -Message 'Finding should include the mixed-case properties path.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Both properties extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Properties findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $assignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $syntheticValue -Message 'Finding output should not replay the assigned value.'
    }

    Invoke-Test 'scans case-insensitive CONF files with existing rules' {
        # CONF files are plain-text configuration like the already-routed CFG
        # variant. Keep mixed-case suffixes on the existing detector path.
        $syntheticValue = 'syntheticconffixturevalue'
        $assignment = ('service_' + 'token' + '=' + $syntheticValue)
        New-FixtureFile -RelativePath 'config/synthetic-server.conf' -Content $assignment
        New-FixtureFile -RelativePath 'config/synthetic-proxy.CoNf' -Content $assignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'CONF files with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should use the existing assignment rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-server.conf' -Message 'Finding should include the lowercase CONF path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-proxy.CoNf' -Message 'Finding should include the mixed-case CONF path.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Both CONF extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'CONF findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $assignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $syntheticValue -Message 'Finding output should not replay the assigned value.'
    }

    Invoke-Test 'scans case-insensitive SQL files with existing rules' {
        # SQL migration files are plain text. Route their assignments through
        # the existing detector without adding SQL-specific secret semantics.
        $syntheticValue = 'syntheticsqlfixturevalue'
        $assignment = ('service_' + 'token' + ' = ''' + $syntheticValue + '''')
        New-FixtureFile -RelativePath 'migrations/synthetic-schema.sql' -Content $assignment
        New-FixtureFile -RelativePath 'migrations/synthetic-seed.SqL' -Content $assignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'SQL files with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should use the existing assignment rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-schema.sql' -Message 'Finding should include the lowercase SQL path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-seed.SqL' -Message 'Finding should include the mixed-case SQL path.'
        Assert-Contains -Text $result.Output -Needle '2 finding(s) across 2 scanned file(s).' -Message 'Both SQL extension variants should be scanned.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'SQL findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle $assignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $syntheticValue -Message 'Finding output should not replay the assigned value.'
    }

    Invoke-Test 'scans case-insensitive Windows batch files with existing rules' {
        # BAT and CMD use SET-specific quoting and chaining. Keep literals in
        # commands or comments visible while runtime, empty, and prompt stay safe.
        $plainValue = 'syntheticbatchfixturevalue'
        $hashValue = 'syntheticbatchhashvalue'
        $semicolonValue = 'syntheticbatchsemicolonvalue'
        $inlineValue = 'syntheticbatchinlinevalue'
        $chainedValue = 'syntheticbatchchainedvalue'
        $commentValue = 'syntheticbatchcommentvalue'
        $quotedSuffixValue = 'syntheticbatchsuffixvalue'
        $plainAssignment = ('set API_' + 'TOKEN' + '=' + $plainValue)
        $quotedHashAssignment = ('set "API_' + 'TOKEN' + '=#' + $hashValue + '"')
        $semicolonAssignment = ('set API_' + 'TOKEN' + '=;' + $semicolonValue)
        $inlineAssignment = ('if defined READY set "API_' + 'TOKEN' + '=' + $inlineValue + '"')
        $chainedAssignment = ('echo ok & set API_' + 'TOKEN' + '=' + $chainedValue + ' & echo done')
        $runtimePlaceholder = ('set "API_' + 'TOKEN' + '=%API_' + 'TOKEN%"')
        $chainedRuntimePlaceholder = ('echo ok & set API_' + 'TOKEN' + '=%API_' + 'TOKEN% & echo done')
        $quotedChainedRuntimePlaceholder = ('set "API_' + 'TOKEN' + '=%API_' + 'TOKEN%" & echo done')
        $groupedRuntimePlaceholder = ('if defined READY (set API_' + 'TOKEN' + '=%API_' + 'TOKEN%)')
        $redirectedRuntimePlaceholder = ('set API_' + 'TOKEN' + '=%API_' + 'TOKEN% 2>nul')
        $delayedRuntimePlaceholder = ('set "API_' + 'TOKEN' + '=!API_' + 'TOKEN!"')
        $positionalRuntimePlaceholder = ('set "API_' + 'TOKEN' + '=%~1"')
        $numberedRuntimePlaceholder = ('set "API_' + 'TOKEN' + '=%1"')
        $allArgsRuntimePlaceholder = ('set "API_' + 'TOKEN' + '=%*"')
        $searchRuntimePlaceholder = ('set "API_' + 'TOKEN' + '=%~dp$PATH:1"')
        $forRuntimePlaceholder = ('set "API_' + 'TOKEN' + '=%%~fA"')
        $emptyAssignment = ('set "API_' + 'TOKEN' + '="')
        $promptAssignment = ('set /p API_' + 'TOKEN' + '=Enter token: ')
        $commentAssignment = ('REM set API_' + 'TOKEN' + '=' + $commentValue)
        $quotedSuffixAssignment = ('set "API_' + 'TOKEN' + '=%SOURCE_' + 'TOKEN%"' + $quotedSuffixValue + '"')
        New-FixtureFile -RelativePath 'scripts/synthetic-build.BaT' -Content $plainAssignment
        New-FixtureFile -RelativePath 'scripts/synthetic-hash.cmd' -Content $quotedHashAssignment
        New-FixtureFile -RelativePath 'scripts/synthetic-semicolon.CmD' -Content $semicolonAssignment
        New-FixtureFile -RelativePath 'scripts/synthetic-inline.bat' -Content $inlineAssignment
        New-FixtureFile -RelativePath 'scripts/synthetic-chained.cmd' -Content $chainedAssignment
        New-FixtureFile -RelativePath 'scripts/synthetic-comment.cmd' -Content $commentAssignment
        New-FixtureFile -RelativePath 'scripts/synthetic-quoted-suffix.bat' -Content $quotedSuffixAssignment
        New-FixtureFile -RelativePath 'scripts/synthetic-runtime.bat' -Content $runtimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-chained-runtime.cmd' -Content $chainedRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-quoted-chained-runtime.bat' -Content $quotedChainedRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-grouped-runtime.cmd' -Content $groupedRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-redirected-runtime.bat' -Content $redirectedRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-delayed-runtime.bat' -Content $delayedRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-positional-runtime.cmd' -Content $positionalRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-numbered-runtime.bat' -Content $numberedRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-all-args-runtime.cmd' -Content $allArgsRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-search-runtime.bat' -Content $searchRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-for-runtime.cmd' -Content $forRuntimePlaceholder
        New-FixtureFile -RelativePath 'scripts/synthetic-empty.cmd' -Content $emptyAssignment
        New-FixtureFile -RelativePath 'scripts/synthetic-prompt.bat' -Content $promptAssignment

        $result = Invoke-Scanner

        Assert-Equal -Actual $result.ExitCode -Expected 1 -Message 'Windows batch files with literal secret assignments should fail.'
        Assert-Contains -Text $result.Output -Needle 'secret-assignment' -Message 'Finding should use the existing assignment rule.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-build.BaT' -Message 'Finding should include the mixed-case BAT path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-hash.cmd' -Message 'Finding should include the quoted hash-value path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-semicolon.CmD' -Message 'Finding should include the semicolon-value path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-inline.bat' -Message 'Finding should include an inline SET path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-chained.cmd' -Message 'Finding should include a chained SET path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-comment.cmd' -Message 'Finding should include a commented literal path.'
        Assert-Contains -Text $result.Output -Needle 'synthetic-quoted-suffix.bat' -Message 'Finding should include malformed quoted suffix text.'
        Assert-Contains -Text $result.Output -Needle '7 finding(s) across 20 scanned file(s).' -Message 'Literal SET values should fail while safe batch forms stay allowed.'
        Assert-Contains -Text $result.Output -Needle '<redacted>' -Message 'Windows batch findings should remain redacted.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-runtime.bat' -Message 'Quoted runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-chained-runtime.cmd' -Message 'Chained runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-quoted-chained-runtime.bat' -Message 'Quoted chained runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-grouped-runtime.cmd' -Message 'Grouped runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-redirected-runtime.bat' -Message 'Redirected runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-delayed-runtime.bat' -Message 'Delayed runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-positional-runtime.cmd' -Message 'Positional runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-numbered-runtime.bat' -Message 'Numbered runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-all-args-runtime.cmd' -Message 'All-arguments runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-search-runtime.bat' -Message 'Search-modifier runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-for-runtime.cmd' -Message 'FOR runtime placeholder should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-empty.cmd' -Message 'Quoted empty assignment should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle 'synthetic-prompt.bat' -Message 'SET /P prompt should not produce a finding.'
        Assert-NotContains -Text $result.Output -Needle $plainAssignment -Message 'Finding output should not replay the assignment.'
        Assert-NotContains -Text $result.Output -Needle $plainValue -Message 'Finding output should not replay the plain value.'
        Assert-NotContains -Text $result.Output -Needle $hashValue -Message 'Finding output should not replay the hash-prefixed value.'
        Assert-NotContains -Text $result.Output -Needle $semicolonValue -Message 'Finding output should not replay the semicolon-prefixed value.'
        Assert-NotContains -Text $result.Output -Needle $inlineValue -Message 'Finding output should not replay the inline value.'
        Assert-NotContains -Text $result.Output -Needle $chainedValue -Message 'Finding output should not replay the chained value.'
        Assert-NotContains -Text $result.Output -Needle $commentValue -Message 'Finding output should not replay the commented value.'
        Assert-NotContains -Text $result.Output -Needle $quotedSuffixValue -Message 'Finding output should not replay the malformed quoted suffix.'
        Assert-NotContains -Text $result.Output -Needle $runtimePlaceholder -Message 'Finding output should not replay the runtime placeholder.'
        Assert-NotContains -Text $result.Output -Needle $delayedRuntimePlaceholder -Message 'Finding output should not replay the delayed runtime placeholder.'
        Assert-NotContains -Text $result.Output -Needle $positionalRuntimePlaceholder -Message 'Finding output should not replay the positional runtime placeholder.'
        Assert-NotContains -Text $result.Output -Needle $numberedRuntimePlaceholder -Message 'Finding output should not replay the numbered runtime placeholder.'
        Assert-NotContains -Text $result.Output -Needle $allArgsRuntimePlaceholder -Message 'Finding output should not replay the all-arguments runtime placeholder.'
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

# Keep the existing CI entrypoint responsible for the boundary suite as well.
$boundaryHarness = Join-Path `
    $PSScriptRoot `
    'scan-private-markers-boundaries.Tests.ps1'
$boundaryOutput = & $scannerPowerShell `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $boundaryHarness `
    -Path $repoRoot 2>&1
$boundaryExitCode = $LASTEXITCODE
foreach ($line in $boundaryOutput) {
    Write-Host $line
}
if ($boundaryExitCode -ne 0) {
    $failures.Add(
        "Scanner boundary self-test failed with exit code $boundaryExitCode."
    ) | Out-Null
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
