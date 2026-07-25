[CmdletBinding()]
param(
    [string]$Path = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$runtimeIsWindows = [Environment]::OSVersion.Platform -eq
    [PlatformID]::Win32NT
$selfTestScriptPath = $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Split-Path -Parent $PSScriptRoot
}
$root = (Resolve-Path -LiteralPath $Path).Path
$scanner = Join-Path $root 'scripts/scan-private-markers.ps1'
$processSupport = Microsoft.PowerShell.Management\Join-Path `
    $root 'scripts/private-marker-process.ps1'
if (-not (Test-Path -LiteralPath $scanner -PathType Leaf) -or
    -not (Test-Path -LiteralPath $processSupport -PathType Leaf)) {
    throw 'Scanner boundary test prerequisites are missing.'
}
. $processSupport

$currentPowerShellExecutable = (
    [Diagnostics.Process]::GetCurrentProcess()
).MainModule.FileName
if ([string]::IsNullOrWhiteSpace($currentPowerShellExecutable) -or
    -not (Test-Path -LiteralPath $currentPowerShellExecutable -PathType Leaf)) {
    $hostExecutableName = if ($PSVersionTable.PSVersion.Major -le 5) {
        'powershell.exe'
    } elseif ($runtimeIsWindows) {
        'pwsh.exe'
    } else {
        'pwsh'
    }
    $currentPowerShellExecutable = Join-Path $PSHOME $hostExecutableName
}
if (-not (Test-Path -LiteralPath $currentPowerShellExecutable -PathType Leaf)) {
    throw 'Current PowerShell executable could not be resolved.'
}

# trusted helperをdot-sourceした直後の最初のtop-level process phaseでraw
# transportを実測する。以後のtest utilityがhelperを先に呼ぶ余地を作らない。
$tempRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ('agentic-security-scan-boundaries-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempRoot)
$rawTransportScript = @'
$stdin = [Console]::OpenStandardInput()
$readBuffer = New-Object byte[] 3
$stdout = [Console]::OpenStandardOutput()
$readCount = $stdin.Read($readBuffer, 0, $readBuffer.Length)
while ($readCount -gt 0) {
    $stdout.Write($readBuffer, 0, $readCount)
    $stdout.Flush()
    $readCount = $stdin.Read($readBuffer, 0, $readBuffer.Length)
}
$stderrBytes = [byte[]]@(255, 254, 128, 127, 13, 10, 1, 0)
$stderr = [Console]::OpenStandardError()
$stderr.Write($stderrBytes, 0, 3)
$stderr.Flush()
$stderr.Write($stderrBytes, 3, $stderrBytes.Length - 3)
$stderr.Flush()
exit 37
'@
$rawChildPath = Join-Path $tempRoot 'raw-transport-child.ps1'
[IO.File]::WriteAllText(
    $rawChildPath,
    $rawTransportScript,
    [Text.UTF8Encoding]::new($false)
)
$rawArguments = @('-NoProfile')
if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
    $rawArguments += @('-ExecutionPolicy', 'Bypass')
}
$rawArguments += @('-File', $rawChildPath)
$rawInput = [byte[]]@(
    0, 128, 255, 1, 10, 13, 127, 254, 2, 129, 253, 3
)
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess `
    -FileName $currentPowerShellExecutable `
    -Arguments $rawArguments `
    -IsolationRoot (Join-Path $tempRoot 'raw-transport-isolation') `
    -StandardInputBytes $rawInput `
    -TimeoutMilliseconds 5000 `
    -MaxStdoutBytes 64 `
    -MaxStderrBytes 64
$expectedRawStderr = [byte[]]@(255, 254, 128, 127, 13, 10, 1, 0)
if ($null -eq $rawTransportResult -or
    $rawTransportResult.TimedOut -or
    $rawTransportResult.OutputLimitExceeded -or
    -not $rawTransportResult.TreeStopped -or
    -not $rawTransportResult.StreamsDrained -or
    $rawTransportResult.ExitCode -ne 37 -or
    [Convert]::ToBase64String($rawTransportResult.StdoutBytes) -ne
        [Convert]::ToBase64String($rawInput) -or
    [Convert]::ToBase64String($rawTransportResult.StderrBytes) -ne
        [Convert]::ToBase64String($expectedRawStderr)) {
    try {
        [IO.Directory]::Delete($tempRoot, $true)
    }
    catch {
        # primary raw failureをcleanup detailで上書きしない。
    }
    throw 'Binary stdin/stdout/stderr, EOF, or exit code was not preserved.'
}

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Test-BoundedResultHealthy {
    param([object]$Result)

    return $null -ne $Result -and
        -not $Result.TimedOut -and
        -not $Result.OutputLimitExceeded -and
        $Result.TreeStopped -and
        $Result.StreamsDrained
}

function Get-ResultText {
    param([object]$Result)

    return [Text.UTF8Encoding]::new(
        $false,
        $false
    ).GetString([byte[]]$Result.StdoutBytes)
}

function Remove-TestTree {
    param([string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return
    }
    $tempBoundary = [IO.Path]::GetFullPath(
        [IO.Path]::GetTempPath()
    ).TrimEnd([char]47, [char]92) + [IO.Path]::DirectorySeparatorChar
    $resolvedTarget = [IO.Path]::GetFullPath($LiteralPath)
    $comparison = if ($runtimeIsWindows) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    if (-not $resolvedTarget.StartsWith($tempBoundary, $comparison)) {
        throw 'Refusing to remove a boundary-test path outside the temp root.'
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
}

# Windows PowerShell 5.1 の Remove-Item は junction 単体でもまれに
# NullReferenceExceptionになる。Windowsは非再帰Directory.Deleteでjunction
# entryだけを外し、POSIXはsymlink自体をRemove-Itemする。
function Remove-TestDirectoryLink {
    param([string]$LiteralPath)

    if ($runtimeIsWindows) {
        [IO.Directory]::Delete($LiteralPath, $false)
    } else {
        Remove-Item -LiteralPath $LiteralPath -Force
    }
}

function Test-AstIsDeferredDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [Management.Automation.Language.Ast]$Ast
    )

    $ancestor = $Ast.Parent
    while ($null -ne $ancestor) {
        if ($ancestor -is
                [Management.Automation.Language.FunctionDefinitionAst] -or
            $ancestor -is
                [Management.Automation.Language.FunctionMemberAst] -or
            $ancestor -is
                [Management.Automation.Language.TypeDefinitionAst]) {
            return $true
        }
        if ($ancestor -is
            [Management.Automation.Language.ScriptBlockExpressionAst]) {
            # 保存されたscriptblockはdataだが、command/memberへ渡された式は
            # 即時実行され得るためdeferredと誤認しない。
            $container = $ancestor.Parent
            $expressionCanExecute = $false
            while ($null -ne $container) {
                if ($container -is
                        [Management.Automation.Language.FunctionDefinitionAst] -or
                    $container -is
                        [Management.Automation.Language.FunctionMemberAst] -or
                    $container -is
                        [Management.Automation.Language.TypeDefinitionAst]) {
                    return $true
                }
                if ($container -is
                        [Management.Automation.Language.CommandAst] -or
                    $container -is
                        [Management.Automation.Language.InvokeMemberExpressionAst]) {
                    $expressionCanExecute = $true
                    break
                }
                $container = $container.Parent
            }
            if (-not $expressionCanExecute) {
                return $true
            }
        }
        $ancestor = $ancestor.Parent
    }
    return $false
}

function Test-CommandIsDeferredDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [Management.Automation.Language.CommandAst]$Command
    )

    return Test-AstIsDeferredDefinition -Ast $Command
}

function Get-NormalizedCommandName {
    param(
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }
    $normalized = $Name
    while ($normalized -match
        '^(?i)(?:global|script|local|private|function):(?<rest>.+)$') {
        $normalized = $Matches['rest']
    }
    $moduleSeparator = $normalized.LastIndexOf([char]92)
    if ($moduleSeparator -ge 0) {
        $normalized = $normalized.Substring($moduleSeparator + 1)
    }
    $builtinAliases = @{
        gcm = 'Get-Command'
        sal = 'Set-Alias'
        nal = 'New-Alias'
        icm = 'Invoke-Command'
        iex = 'Invoke-Expression'
    }
    $aliasKey = $normalized.ToLowerInvariant()
    if ($builtinAliases.ContainsKey($aliasKey)) {
        return $builtinAliases[$aliasKey]
    }
    return $normalized
}

function Get-StaticCommandArguments {
    param(
        [Management.Automation.Language.CommandAst]$Command
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($element in @($Command.CommandElements | Select-Object -Skip 1)) {
        if ($element -is
            [Management.Automation.Language.CommandParameterAst]) {
            continue
        }
        if ($element -isnot
            [Management.Automation.Language.StringConstantExpressionAst]) {
            return $null
        }
        $arguments.Add([string]$element.Value) | Out-Null
    }
    return ,$arguments.ToArray()
}

function Test-CommandBelongsToFunction {
    param(
        [Management.Automation.Language.CommandAst]$Command,
        [Management.Automation.Language.FunctionDefinitionAst]$Function
    )

    $ancestor = $Command.Parent
    while ($null -ne $ancestor) {
        if ($ancestor -is
            [Management.Automation.Language.FunctionDefinitionAst]) {
            return [object]::ReferenceEquals($ancestor, $Function)
        }
        $ancestor = $ancestor.Parent
    }
    return $false
}

function Test-IsTrustedProcessSupportDotSource {
    param(
        [Management.Automation.Language.CommandAst]$Command
    )

    if ($Command.InvocationOperator -ne
        [Management.Automation.Language.TokenKind]::Dot) {
        return $false
    }
    $elements = @($Command.CommandElements)
    if ($elements.Count -ne 1 -or
        $elements[0] -isnot
            [Management.Automation.Language.VariableExpressionAst] -or
        $elements[0].VariablePath.UserPath -ne 'processSupport') {
        return $false
    }

    # 変数名だけを信頼すると、攻撃側の直接代入から任意scriptをdot-source
    # できる。dot-sourceより前のtop-level代入を一意に絞り、repo rootから
    # 固定helper相対pathをmodule-qualified Join-Pathで組み立てたprovenance
    # だけを許可し、同名function/aliasのshadowもbootstrap前に遮断する。
    $sourceAst = $Command
    while ($null -ne $sourceAst.Parent) {
        $sourceAst = $sourceAst.Parent
    }
    $assignments = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                        [Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is
                        [Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -eq 'processSupport' -and
                    $node.Extent.EndOffset -le $Command.Extent.StartOffset
            },
            $true
        ) | Where-Object {
            -not (Test-AstIsDeferredDefinition -Ast $_)
        }
    )
    if ($assignments.Count -ne 1 -or
        $assignments[0].Operator -ne
            [Management.Automation.Language.TokenKind]::Equals -or
        $assignments[0].Right -isnot
            [Management.Automation.Language.PipelineAst]) {
        return $false
    }

    $pipelineElements = @($assignments[0].Right.PipelineElements)
    if ($pipelineElements.Count -ne 1 -or
        $pipelineElements[0] -isnot
            [Management.Automation.Language.CommandAst]) {
        return $false
    }
    $joinPathCommand = $pipelineElements[0]
    $joinPathElements = @($joinPathCommand.CommandElements)
    return $joinPathCommand.InvocationOperator -eq
            [Management.Automation.Language.TokenKind]::Unknown -and
        $joinPathCommand.GetCommandName() -eq
            'Microsoft.PowerShell.Management\Join-Path' -and
        $joinPathElements.Count -eq 3 -and
        $joinPathElements[1] -is
            [Management.Automation.Language.VariableExpressionAst] -and
        $joinPathElements[1].VariablePath.UserPath -eq 'root' -and
        $joinPathElements[2] -is
            [Management.Automation.Language.StringConstantExpressionAst] -and
        $joinPathElements[2].Value -eq
            'scripts/private-marker-process.ps1'
}

function Test-FirstBoundedInvocationIsRawTransport {
    param([string]$Source)

    $tokens = $null
    $parseErrors = $null
    $sourceAst = [Management.Automation.Language.Parser]::ParseInput(
        $Source,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        return $false
    }
    $targetCommandName = 'Invoke-PrivateMarkerBoundedProcess'

    $rawAssignments = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                        [Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is
                        [Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -eq 'rawTransportResult'
            },
            $true
        )
    )
    if ($rawAssignments.Count -ne 1 -or
        $rawAssignments[0].Right -isnot
            [Management.Automation.Language.PipelineAst]) {
        return $false
    }

    $pipelineElements = @($rawAssignments[0].Right.PipelineElements)
    if ($pipelineElements.Count -ne 1 -or
        $pipelineElements[0] -isnot
            [Management.Automation.Language.CommandAst] -or
        (Get-NormalizedCommandName `
            -Name $pipelineElements[0].GetCommandName()) -ne
            $targetCommandName) {
        return $false
    }
    $rawCommand = $pipelineElements[0]
    $nestedCalls = @(
        $rawAssignments[0].Right.FindAll(
            {
                param($node)
                return $node -is
                        [Management.Automation.Language.CommandAst] -and
                    (Get-NormalizedCommandName `
                        -Name $node.GetCommandName()) -eq
                        $targetCommandName
            },
            $true
        )
    )
    if ($nestedCalls.Count -ne 1 -or
        (Test-CommandIsDeferredDefinition -Command $rawCommand)) {
        return $false
    }

    # source内functionがtargetへ到達し得るかを固定点まで解決する。dynamic
    # invocation/Get-Commandは静的に安全を証明できないためfail closedにする。
    $functionDefinitions = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                    [Management.Automation.Language.FunctionDefinitionAst]
            },
            $true
        )
    )
    # helper名自体のfunction shadowはraw fixtureに見えても別実装を呼ぶ。
    if (@($functionDefinitions | Where-Object {
            (Get-NormalizedCommandName -Name $_.Name) -eq
                $targetCommandName
        }).Count -gt 0) {
        return $false
    }
    $unsafeFunctions = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($function in $functionDefinitions) {
            $functionName = Get-NormalizedCommandName -Name $function.Name
            if ($unsafeFunctions.Contains($functionName)) {
                continue
            }
            $functionCommands = @(
                $function.Body.FindAll(
                    {
                        param($node)
                        return $node -is
                            [Management.Automation.Language.CommandAst]
                    },
                    $true
                ) | Where-Object {
                    Test-CommandBelongsToFunction `
                        -Command $_ `
                        -Function $function
                }
            )
            $functionIsUnsafe = $false
            foreach ($functionCommand in $functionCommands) {
                $commandName = Get-NormalizedCommandName `
                    -Name $functionCommand.GetCommandName()
                if ([string]::IsNullOrWhiteSpace($commandName)) {
                    $functionIsUnsafe = $true
                    break
                }
                if ($commandName -eq $targetCommandName -or
                    $unsafeFunctions.Contains($commandName)) {
                    $functionIsUnsafe = $true
                    break
                }
                if ($commandName -in @('Get-Command', 'Set-Alias', 'New-Alias')) {
                    $staticArguments = Get-StaticCommandArguments `
                        -Command $functionCommand
                    if ($null -eq $staticArguments) {
                        $functionIsUnsafe = $true
                        break
                    }
                    foreach ($staticArgument in $staticArguments) {
                        $referencedName = Get-NormalizedCommandName `
                            -Name $staticArgument
                        if ($referencedName -eq $targetCommandName -or
                            $unsafeFunctions.Contains($referencedName)) {
                            $functionIsUnsafe = $true
                            break
                        }
                    }
                    if ($functionIsUnsafe) {
                        break
                    }
                }
            }
            if ($functionIsUnsafe -and
                $unsafeFunctions.Add($functionName)) {
                $changed = $true
            }
        }
    }

    # class/type memberは定義時にはdeferredだが、raw前のconstructor/static
    # member呼出しで即時実行できる。targetへ到達するtypeを別集合で保持する。
    $unsafeTypes = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $typeDefinitions = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                    [Management.Automation.Language.TypeDefinitionAst]
            },
            $true
        )
    )
    foreach ($typeDefinition in $typeDefinitions) {
        $typeCommands = @(
            $typeDefinition.FindAll(
                {
                    param($node)
                    return $node -is
                        [Management.Automation.Language.CommandAst]
                },
                $true
            )
        )
        foreach ($typeCommand in $typeCommands) {
            $typeCommandName = Get-NormalizedCommandName `
                -Name $typeCommand.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($typeCommandName) -or
                $typeCommandName -eq $targetCommandName -or
                $unsafeFunctions.Contains($typeCommandName) -or
                $typeCommandName -in @(
                    'Invoke-Command',
                    'Invoke-Expression'
                )) {
                [void]$unsafeTypes.Add([string]$typeDefinition.Name)
                break
            }
        }
    }

    # constructor/static initializerを持つunsafe typeは、member callだけでなく
    # `-as` cast・型変換・static property参照でもraw前にcodeを実行し得る。
    $eagerUnsafeTypeReferences = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                    [Management.Automation.Language.TypeExpressionAst]
            },
            $true
        ) | Where-Object {
            $_.Extent.StartOffset -lt $rawCommand.Extent.StartOffset -and
            -not (Test-AstIsDeferredDefinition -Ast $_) -and
            $unsafeTypes.Contains([string]$_.TypeName.FullName)
        }
    )
    if ($eagerUnsafeTypeReferences.Count -gt 0) {
        return $false
    }

    # function/alias provider参照とInvoke系memberはcalleeを差替え/即時実行できる。
    # raw fixture前では、安全なcalleeを静的に証明できない形をすべて拒否する。
    $sensitiveProviderReferences = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                    [Management.Automation.Language.VariableExpressionAst]
            },
            $true
        ) | Where-Object {
            $_.Extent.StartOffset -lt $rawCommand.Extent.StartOffset -and
            -not (Test-AstIsDeferredDefinition -Ast $_) -and
            $_.VariablePath.UserPath -match
                ('^(?i)(?:(?:global|script|local|private):)?' +
                    '(?:function|alias):(?<name>.+)$')
        }
    )
    foreach ($providerReference in $sensitiveProviderReferences) {
        [void]($providerReference.VariablePath.UserPath -match
            ('^(?i)(?:(?:global|script|local|private):)?' +
                '(?:function|alias):(?<name>.+)$'))
        $referenceName = Get-NormalizedCommandName `
            -Name $Matches['name']
        if ($referenceName -eq $targetCommandName -or
            $unsafeFunctions.Contains($referenceName)) {
            return $false
        }
    }

    $eagerMemberInvocations = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                    [Management.Automation.Language.InvokeMemberExpressionAst]
            },
            $true
        ) | Where-Object {
            $_.Extent.StartOffset -lt $rawCommand.Extent.StartOffset -and
            -not (Test-AstIsDeferredDefinition -Ast $_)
        }
    )
    foreach ($memberInvocation in $eagerMemberInvocations) {
        if ($memberInvocation.Member -isnot
            [Management.Automation.Language.StringConstantExpressionAst]) {
            return $false
        }
        $memberName = [string]$memberInvocation.Member.Value
        if ($memberName -match '^(?i)Invoke') {
            return $false
        }
        $memberOwner = ''
        if ($memberInvocation.Expression -is
            [Management.Automation.Language.TypeExpressionAst]) {
            $memberOwner =
                [string]$memberInvocation.Expression.TypeName.FullName
        }
        $memberAllowed = $false
        if ($memberInvocation.Static) {
            $memberAllowed = (
                ($memberOwner -eq 'string' -and
                    $memberName -eq 'IsNullOrWhiteSpace') -or
                ($memberOwner -eq 'Diagnostics.Process' -and
                    $memberName -eq 'GetCurrentProcess') -or
                ($memberOwner -eq 'IO.Path' -and
                    $memberName -eq 'GetTempPath') -or
                ($memberOwner -eq 'Guid' -and
                    $memberName -eq 'NewGuid') -or
                ($memberOwner -eq 'IO.Directory' -and
                    $memberName -eq 'CreateDirectory') -or
                ($memberOwner -eq 'IO.File' -and
                    $memberName -eq 'WriteAllText') -or
                ($memberOwner -eq 'Text.UTF8Encoding' -and
                    $memberName -eq 'new')
            )
        } elseif ($memberName -eq 'ToString' -and
            $memberInvocation.Expression -is
                [Management.Automation.Language.InvokeMemberExpressionAst]) {
            $innerMember = $memberInvocation.Expression
            $memberAllowed = $innerMember.Static -and
                $innerMember.Member -is
                    [Management.Automation.Language.StringConstantExpressionAst] -and
                $innerMember.Member.Value -eq 'NewGuid' -and
                $innerMember.Expression -is
                    [Management.Automation.Language.TypeExpressionAst] -and
                $innerMember.Expression.TypeName.FullName -eq 'Guid'
        }
        if (-not $memberAllowed) {
            return $false
        }
        $referencedTypes = @(
            $memberInvocation.FindAll(
                {
                    param($node)
                    return $node -is
                        [Management.Automation.Language.TypeExpressionAst]
                },
                $true
            )
        )
        foreach ($referencedType in $referencedTypes) {
            if ($unsafeTypes.Contains(
                [string]$referencedType.TypeName.FullName
            )) {
                return $false
            }
        }
    }

    $eagerCommands = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                    [Management.Automation.Language.CommandAst]
            },
            $true
        ) |
            Where-Object {
                -not (Test-CommandIsDeferredDefinition -Command $_)
            } |
            Sort-Object { $_.Extent.StartOffset }
    )
    $allowedEagerCommands = @(
        'Set-StrictMode',
        'Split-Path',
        'Resolve-Path',
        'Join-Path',
        'Test-Path',
        'Get-Command',
        'Set-Alias',
        'New-Alias'
    )
    $unsafeAliases = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($eagerCommand in $eagerCommands) {
        if ($eagerCommand.Extent.StartOffset -eq
                $rawCommand.Extent.StartOffset -and
            $eagerCommand.Extent.EndOffset -eq
                $rawCommand.Extent.EndOffset) {
            $rawNestedCommands = @(
                $rawCommand.FindAll(
                    {
                        param($node)
                        return $node -is
                            [Management.Automation.Language.CommandAst]
                    },
                    $true
                ) | Where-Object {
                    -not [object]::ReferenceEquals($_, $rawCommand)
                }
            )
            foreach ($rawNestedCommand in $rawNestedCommands) {
                $rawNestedName = Get-NormalizedCommandName `
                    -Name $rawNestedCommand.GetCommandName()
                if ($rawNestedName -ne 'Join-Path') {
                    return $false
                }
            }
            if (@($rawCommand.FindAll(
                    {
                        param($node)
                        return $node -is
                                [Management.Automation.Language.InvokeMemberExpressionAst] -or
                            $node -is
                                [Management.Automation.Language.ScriptBlockExpressionAst]
                    },
                    $true
                )).Count -gt 0) {
                return $false
            }
            if (@($rawCommand.FindAll(
                    {
                        param($node)
                        return $node -is
                                [Management.Automation.Language.VariableExpressionAst] -and
                            $node.VariablePath.UserPath -match
                                ('^(?i)(?:(?:global|script|local|private):)?' +
                                    '(?:function|alias):')
                    },
                    $true
                )).Count -gt 0) {
                return $false
            }
            return $true
        }
        if ($eagerCommand.Extent.StartOffset -gt
            $rawCommand.Extent.StartOffset) {
            return $false
        }

        $commandName = Get-NormalizedCommandName `
            -Name $eagerCommand.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName)) {
            if (-not (Test-IsTrustedProcessSupportDotSource `
                -Command $eagerCommand)) {
                return $false
            }
            continue
        }
        if ($commandName -eq $targetCommandName -or
            $unsafeFunctions.Contains($commandName) -or
            $unsafeAliases.Contains($commandName)) {
            return $false
        }

        if ($commandName -in @('Set-Alias', 'New-Alias')) {
            $staticArguments = Get-StaticCommandArguments `
                -Command $eagerCommand
            if ($null -eq $staticArguments -or
                $staticArguments.Count -lt 2) {
                return $false
            }
            $aliasName = Get-NormalizedCommandName `
                -Name $staticArguments[0]
            $aliasTarget = Get-NormalizedCommandName `
                -Name $staticArguments[1]
            if ($aliasName -eq $targetCommandName -or
                $aliasTarget -eq $targetCommandName -or
                $unsafeFunctions.Contains($aliasTarget) -or
                $unsafeAliases.Contains($aliasTarget)) {
                [void]$unsafeAliases.Add($aliasName)
                return $false
            }
        }
        if ($commandName -eq 'Get-Command') {
            $staticArguments = Get-StaticCommandArguments `
                -Command $eagerCommand
            if ($null -eq $staticArguments -or
                $staticArguments.Count -lt 1) {
                return $false
            }
            foreach ($staticArgument in $staticArguments) {
                $referencedName = Get-NormalizedCommandName `
                    -Name $staticArgument
                if ($referencedName -eq $targetCommandName -or
                    $unsafeFunctions.Contains($referencedName) -or
                    $unsafeAliases.Contains($referencedName)) {
                    return $false
                }
            }
        }
        if ($commandName -in @('Invoke-Command', 'Invoke-Expression')) {
            return $false
        }
        if ($commandName -notin $allowedEagerCommands) {
            return $false
        }
    }
    return $false
}

function Assert-AstValidatorRegressions {
    $cases = @(
        [pscustomobject]@{
            Name = 'direct-before'
            Expected = $false
            Source = @'
Invoke-PrivateMarkerBoundedProcess
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'function-before'
            Expected = $true
            Source = @'
function Invoke-Deferred {
    Invoke-PrivateMarkerBoundedProcess
}
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'uninvoked-scriptblock'
            Expected = $true
            Source = @'
$unused = { Invoke-PrivateMarkerBoundedProcess }
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'nested-inner'
            Expected = $false
            Source = @'
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess -Value $(Invoke-PrivateMarkerBoundedProcess)
'@
        },
        [pscustomobject]@{
            Name = 'invoked-scriptblock'
            Expected = $false
            Source = @'
({ Invoke-PrivateMarkerBoundedProcess }).Invoke()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'scoped-function-wrapper'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
global:Invoke-Early
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'alias-function-wrapper'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
Set-Alias EarlyAlias Invoke-Early
EarlyAlias
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'get-command-function-reference'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
(Get-Command Invoke-Early).ScriptBlock.Invoke()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'dynamic-get-command'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
$earlyName = 'Invoke-Early'
(Get-Command $earlyName).ScriptBlock.Invoke()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'dynamic-call-operator'
            Expected = $false
            Source = @'
$earlyName = 'Invoke-Early'
& $earlyName
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'transitive-function-wrapper'
            Expected = $false
            Source = @'
function Invoke-Later {
    Invoke-PrivateMarkerBoundedProcess
}
function Invoke-Early {
    Invoke-Later
}
Invoke-Early
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'target-function-shadow'
            Expected = $false
            Source = @'
function Invoke-PrivateMarkerBoundedProcess {
    return $null
}
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'target-alias-shadow'
            Expected = $false
            Source = @'
Set-Alias Invoke-PrivateMarkerBoundedProcess Get-Item
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'gcm-function-reference'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
(gcm Invoke-Early).ScriptBlock.Invoke()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'module-qualified-function-reference'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
(Microsoft.PowerShell.Core\Get-Command Invoke-Early).ScriptBlock.Invoke()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'function-provider-invoke'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
${function:Invoke-Early}.Invoke()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'invoke-command-function-provider'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
Invoke-Command -ScriptBlock ${function:Invoke-Early}
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'class-constructor-member'
            Expected = $false
            Source = @'
class EarlyClass {
    EarlyClass() {
        Invoke-PrivateMarkerBoundedProcess
    }
}
[void][EarlyClass]::new()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'class-method-member'
            Expected = $false
            Source = @'
class EarlyClass {
    [void] Invoke() {
        Invoke-PrivateMarkerBoundedProcess
    }
}
[EarlyClass]::new().Invoke()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'invoke-expression-static-string'
            Expected = $false
            Source = @'
Invoke-Expression 'Invoke-PrivateMarkerBoundedProcess'
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'foreach-function-provider'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
1 | ForEach-Object ${function:Invoke-Early}
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'set-item-function-provider-shadow'
            Expected = $false
            Source = @'
Set-Item Function:\Invoke-PrivateMarkerBoundedProcess { Get-Item }
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'new-item-function-provider-shadow'
            Expected = $false
            Source = @'
New-Item Function:\Invoke-PrivateMarkerBoundedProcess -Value { Get-Item }
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'function-provider-assignment-shadow'
            Expected = $false
            Source = @'
${function:Invoke-PrivateMarkerBoundedProcess} = { Get-Item }
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'alias-provider-assignment-shadow'
            Expected = $false
            Source = @'
${alias:Invoke-PrivateMarkerBoundedProcess} = 'Get-Item'
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'set-item-alias-provider-shadow'
            Expected = $false
            Source = @'
Set-Item Alias:Invoke-PrivateMarkerBoundedProcess Get-Item
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'unknown-invoke-receiver-with-safe-argument'
            Expected = $false
            Source = @'
Set-Variable -Name x -Value { Invoke-PrivateMarkerBoundedProcess }
$safe = $true
(Write-Output (Get-Variable x -ValueOnly) -Verbose:$safe).Invoke()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'foreach-stored-scriptblock'
            Expected = $false
            Source = @'
$stored = { Invoke-PrivateMarkerBoundedProcess }
1 | ForEach-Object $stored
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'where-stored-scriptblock'
            Expected = $false
            Source = @'
$stored = { Invoke-PrivateMarkerBoundedProcess }
1 | Where-Object $stored
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'class-constructor-as-cast'
            Expected = $false
            Source = @'
class EarlyClass {
    EarlyClass() {
        Invoke-PrivateMarkerBoundedProcess
    }
}
$instance = @{} -as [EarlyClass]
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'class-static-initializer-property'
            Expected = $false
            Source = @'
class EarlyClass {
    static [EarlyClass] $Instance = [EarlyClass]::new()
    EarlyClass() {
        Invoke-PrivateMarkerBoundedProcess
    }
    [void] Run() {}
}
$instance = [EarlyClass]::Instance
$instance.Run()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'set-content-alias-provider'
            Expected = $false
            Source = @'
function Invoke-Early {
    Invoke-PrivateMarkerBoundedProcess
}
Set-Content Alias:EarlyAlias Invoke-Early
EarlyAlias
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'dynamic-new-item-function-provider'
            Expected = $false
            Source = @'
$providerPath = 'Function:Invoke-PrivateMarkerBoundedProcess'
New-Item -Path $providerPath -ItemType Directory -Value { 'shadow' }
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'trusted-dot-source-direct-overwrite'
            Expected = $false
            Source = @'
$processSupport = './synthetic.ps1'
. $processSupport
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'trusted-dot-source-join-path-shadow'
            Expected = $false
            Source = @'
function Join-Path { './synthetic.ps1' }
$processSupport = Join-Path $root 'scripts/private-marker-process.ps1'
. $processSupport
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'trusted-dot-source-variable-overwrite'
            Expected = $false
            Source = @'
Set-Variable -Name processSupport -Value './synthetic.ps1'
. $processSupport
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'trusted-dot-source-scope-one-overwrite'
            Expected = $false
            Source = @'
function Set-ProcessSupport {
    Set-Variable -Scope 1 -Name processSupport -Value './synthetic.ps1'
}
Set-ProcessSupport
. $processSupport
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'safe-static-get-command'
            Expected = $true
            Source = @'
Get-Command git
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'safe-alias'
            Expected = $true
            Source = @'
Set-Alias EarlyAlias Get-Item
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'trusted-process-support-dot-source'
            Expected = $true
            Source = @'
$processSupport = Microsoft.PowerShell.Management\Join-Path $root 'scripts/private-marker-process.ps1'
. $processSupport
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        }
    )
    foreach ($case in $cases) {
        if ((Test-FirstBoundedInvocationIsRawTransport `
            -Source $case.Source) -ne $case.Expected) {
            Add-Failure "AST validator regression failed: $($case.Name)."
        }
    }
}

function Invoke-IsolatedGit {
    param(
        [string]$GitPath,
        [string]$WorkingDirectory,
        [string]$IsolationRoot,
        [string[]]$Arguments,
        [AllowNull()]
        [byte[]]$StandardInputBytes = $null
    )

    return Invoke-PrivateMarkerBoundedProcess `
        -FileName $GitPath `
        -Arguments (@('-C', $WorkingDirectory) + $Arguments) `
        -IsolationRoot $IsolationRoot `
        -WorkingDirectory $WorkingDirectory `
        -StandardInputBytes $StandardInputBytes `
        -TimeoutMilliseconds 20000
}

function Invoke-BoundaryScanner {
    param(
        [string]$ScanPath,
        [ValidateSet('auto', 'tracked', 'worktree')]
        [string]$ScanMode = 'auto',
        [int]$ScanDeadlineMilliseconds = 120000,
        [hashtable]$InheritedEnvironment = @{},
        [int]$MaxStdoutBytes = 65536,
        [string]$ScannerPath = $scanner,
        [switch]$TestOnlyCreateCleanupUnknownEntry
    )

    $arguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $arguments += @('-ExecutionPolicy', 'Bypass')
    }
    $arguments += @(
        '-File',
        $ScannerPath,
        '-Path',
        $ScanPath,
        '-ScanMode',
        $ScanMode,
        '-ScanDeadlineMilliseconds',
        [string]$ScanDeadlineMilliseconds
    )
    if ($TestOnlyCreateCleanupUnknownEntry) {
        $arguments += '-TestOnlyCreateCleanupUnknownEntry'
    }
    $isolationRoot = Join-Path (
        [IO.Path]::GetTempPath()
    ) ('agentic-security-scanner-child-' + [Guid]::NewGuid().ToString('N'))
    $scannerEnvironment = @{}
    foreach ($environmentName in $InheritedEnvironment.Keys) {
        $scannerEnvironment[$environmentName] =
            $InheritedEnvironment[$environmentName]
    }
    $scannerGitCommand = Get-Command `
        git `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $scannerGitCommand -and
        [IO.Path]::IsPathRooted($scannerGitCommand.Source)) {
        # ambient PATH全体ではなく、検証済みnative Gitのdirectoryだけを渡す。
        $scannerEnvironment['PATH'] =
            Split-Path -Parent $scannerGitCommand.Source
    }
    New-Item -ItemType Directory -Path $isolationRoot | Out-Null
    try {
        return Invoke-PrivateMarkerBoundedProcess `
            -FileName $currentPowerShellExecutable `
            -Arguments $arguments `
            -IsolationRoot $isolationRoot `
            -InheritedEnvironment $scannerEnvironment `
            -TimeoutMilliseconds 60000 `
            -MaxStdoutBytes $MaxStdoutBytes `
            -MaxStderrBytes 65536 `
            -PassThroughGitEnvironment
    }
    finally {
        Remove-TestTree -LiteralPath $isolationRoot
    }
}

function Assert-IntegrityFailure {
    param(
        [object]$Result,
        [string]$Reason,
        [string]$Context
    )

    $text = Get-ResultText -Result $Result
    if (-not (Test-BoundedResultHealthy -Result $Result) -or
        $Result.ExitCode -ne 2 -or
        $text -notmatch (
            'Private marker scan failed closed \(integrity: ' +
            [regex]::Escape($Reason) +
            '\)\.'
        )) {
        Add-Failure "$Context did not fail closed with $Reason."
    }
}

function Import-WorktreeSnapshotTestType {
    if ($null -ne (
        'AgenticCodingSecurityGate.PrivateMarkerWorktreeSnapshot' -as [type]
    )) {
        return
    }

    # scanner内のproduction helperそのものをcompileし、test用のコピーとの
    # driftを作らない。抽出できない場合もskipせずself-test failureにする。
    $scannerSource = [IO.File]::ReadAllText($scanner)
    $typeMatch = [regex]::Match(
        $scannerSource,
        "Add-Type -TypeDefinition @'\r?\n(?<source>using System;" +
            "[\s\S]*?)\r?\n'@"
    )
    if (-not $typeMatch.Success) {
        throw 'Worktree snapshot production helper could not be extracted.'
    }
    Add-Type -TypeDefinition $typeMatch.Groups['source'].Value
}

function Wait-ForTestPath {
    param(
        [string]$LiteralPath,
        [int]$TimeoutMilliseconds = 5000
    )

    $waitClock = [Diagnostics.Stopwatch]::StartNew()
    while ($waitClock.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        if ([IO.File]::Exists($LiteralPath)) {
            return $true
        }
        Start-Sleep -Milliseconds 5
    }
    return $false
}

try {
    Assert-AstValidatorRegressions

    # 親環境を削るdenylistではなく、空mapから構成したOS別allowlistの
    # key集合を完全一致で固定する。明示test経路でもGIT_*以外は渡さない。
    $environmentIsolation = Join-Path $tempRoot 'environment-allowlist'
    $environmentClock = [Diagnostics.Stopwatch]::StartNew()
    # scanner自身がfixtureをscanしても credential assignment と誤認しないよう、
    # unsafe key名のうち detector 対象語を含むものだけbyte列から組み立てる。
    $azureCredentialName = 'AZURE_CLIENT_' +
        [Text.Encoding]::ASCII.GetString([byte[]](83, 69, 67, 82, 69, 84))
    $hostileEnvironment = @{
        LD_PRELOAD = 'synthetic-loader'
        LD_LIBRARY_PATH = 'synthetic-library-path'
        DYLD_INSERT_LIBRARIES = 'synthetic-dyld'
        DOTNET_STARTUP_HOOKS = 'synthetic-runtime-hook'
        BASH_ENV = 'synthetic-shell-startup'
        ENV = 'synthetic-shell-env'
        PSModulePath = 'synthetic-module-path'
        AWS_ACCESS_KEY_ID = 'synthetic-cloud-id'
        GOOGLE_APPLICATION_CREDENTIALS = 'synthetic-cloud-file'
        PATH = 'synthetic-command-path'
        GIT_INDEX_FILE = 'synthetic-index'
    }
    $hostileEnvironment[$azureCredentialName] = 'synthetic-cloud-value'
    $environmentMap = New-PrivateMarkerChildEnvironment `
        -IsolationRoot $environmentIsolation `
        -RequestedEnvironment $hostileEnvironment `
        -OperationStopwatch $environmentClock `
        -OperationDeadlineMilliseconds 10000
    $expectedEnvironmentKeys = @(
        'HOME',
        'USERPROFILE',
        'XDG_CONFIG_HOME',
        'XDG_CACHE_HOME',
        'XDG_DATA_HOME',
        'PSModulePath',
        'DOTNET_EnableDiagnostics',
        'DOTNET_CLI_TELEMETRY_OPTOUT',
        'POWERSHELL_TELEMETRY_OPTOUT',
        'POWERSHELL_UPDATECHECK',
        'GIT_CONFIG_NOSYSTEM',
        'GIT_ATTR_NOSYSTEM',
        'GIT_CONFIG_GLOBAL',
        'GIT_CONFIG_SYSTEM',
        'GIT_TERMINAL_PROMPT',
        'GIT_LFS_SKIP_SMUDGE',
        'GIT_OPTIONAL_LOCKS',
        'GIT_NO_REPLACE_OBJECTS',
        'GIT_NO_LAZY_FETCH',
        'GIT_CONFIG_COUNT',
        'GIT_CONFIG_KEY_0',
        'GIT_CONFIG_VALUE_0',
        'GIT_CONFIG_KEY_1',
        'GIT_CONFIG_VALUE_1',
        'GIT_CONFIG_KEY_2',
        'GIT_CONFIG_VALUE_2',
        'GIT_CONFIG_KEY_3',
        'GIT_CONFIG_VALUE_3',
        'GIT_CONFIG_KEY_4',
        'GIT_CONFIG_VALUE_4',
        'GIT_CONFIG_KEY_5',
        'GIT_CONFIG_VALUE_5',
        'GIT_CONFIG_KEY_6',
        'GIT_CONFIG_VALUE_6'
    )
    if ($runtimeIsWindows) {
        $expectedEnvironmentKeys += @(
            'SystemRoot',
            'WINDIR',
            'SystemDrive',
            'ProgramData',
            'TEMP',
            'TMP',
            'PATHEXT',
            'AGENTIC_CODING_SECURITY_GATE_OWNED_WINDOWS_JOB'
        )
    } else {
        $expectedEnvironmentKeys += @('TMPDIR', 'LANG', 'LC_ALL')
    }
    $environmentKeyDiff = @(
        Compare-Object `
            -ReferenceObject @($expectedEnvironmentKeys | Sort-Object) `
            -DifferenceObject @($environmentMap.Keys | Sort-Object)
    )
    if ($environmentKeyDiff.Count -gt 0) {
        Add-Failure 'Child environment keys did not match the fixed allowlist.'
    }
    foreach ($dangerousName in @(
        'LD_PRELOAD',
        'LD_LIBRARY_PATH',
        'DYLD_INSERT_LIBRARIES',
        'DOTNET_STARTUP_HOOKS',
        'BASH_ENV',
        'ENV',
        'AWS_ACCESS_KEY_ID',
        $azureCredentialName,
        'GOOGLE_APPLICATION_CREDENTIALS',
        'PATH',
        'GIT_INDEX_FILE'
    )) {
        if ($environmentMap.ContainsKey($dangerousName)) {
            Add-Failure "Child environment retained unsafe key $dangerousName."
        }
    }
    if ($environmentMap['PSModulePath'] -eq 'synthetic-module-path') {
        Add-Failure 'Child environment retained ambient PSModulePath.'
    }

    $passThroughIsolation = Join-Path $tempRoot 'environment-pass-through'
    $passThroughClock = [Diagnostics.Stopwatch]::StartNew()
    $passThroughMap = New-PrivateMarkerChildEnvironment `
        -IsolationRoot $passThroughIsolation `
        -RequestedEnvironment $hostileEnvironment `
        -PassThroughGitEnvironment `
        -OperationStopwatch $passThroughClock `
        -OperationDeadlineMilliseconds 10000
    $expectedPassThroughKeys = @(
        'HOME',
        'USERPROFILE',
        'XDG_CONFIG_HOME',
        'XDG_CACHE_HOME',
        'XDG_DATA_HOME',
        'PSModulePath',
        'DOTNET_EnableDiagnostics',
        'DOTNET_CLI_TELEMETRY_OPTOUT',
        'POWERSHELL_TELEMETRY_OPTOUT',
        'POWERSHELL_UPDATECHECK',
        'GIT_INDEX_FILE',
        'PATH'
    )
    if ($runtimeIsWindows) {
        $expectedPassThroughKeys += @(
            'SystemRoot',
            'WINDIR',
            'SystemDrive',
            'ProgramData',
            'TEMP',
            'TMP',
            'PATHEXT',
            'AGENTIC_CODING_SECURITY_GATE_OWNED_WINDOWS_JOB'
        )
    } else {
        $expectedPassThroughKeys += @('TMPDIR', 'LANG', 'LC_ALL')
    }
    $passThroughKeyDiff = @(
        Compare-Object `
            -ReferenceObject @($expectedPassThroughKeys | Sort-Object) `
            -DifferenceObject @($passThroughMap.Keys | Sort-Object)
    )
    if ($passThroughKeyDiff.Count -gt 0) {
        Add-Failure 'Test pass-through environment exceeded its fixed key set.'
    }

    Import-WorktreeSnapshotTestType

    # leaf open直前に同一長の別fileへ置換し、その後元fileを戻す。旧length比較
    # では通ったが、stable file ID/dev+inodeと内容hashの最終照合は拒否する。
    $identityRoot = Join-Path $tempRoot 'stable-identity'
    New-Item -ItemType Directory -Path $identityRoot | Out-Null
    $identityLeaf = Join-Path $identityRoot 'tracked.txt'
    $identityAlternate = Join-Path $identityRoot 'alternate.txt'
    $identityBackup = Join-Path $identityRoot 'original.txt'
    $identityCaptured = Join-Path $identityRoot 'captured.txt'
    [IO.File]::WriteAllText($identityLeaf, 'AAAA')
    [IO.File]::WriteAllText($identityAlternate, 'BBBB')
    $identityReady = Join-Path $tempRoot 'identity-ready'
    $identityRelease = Join-Path $tempRoot 'identity-release'
    [AgenticCodingSecurityGate.PrivateMarkerWorktreeSnapshot]::
        ConfigureSingleTestPauseBeforeLeaf(
            $identityReady,
            $identityRelease,
            5000
        )
    $identityTask =
        [AgenticCodingSecurityGate.PrivateMarkerWorktreeSnapshot]::
            CaptureWithConfiguredTestPauseAsync(
                $identityRoot,
                [string[]]@('tracked.txt'),
                1024
            )
    if (-not (Wait-ForTestPath -LiteralPath $identityReady)) {
        Add-Failure 'Stable identity test did not reach the pre-open pause.'
    } else {
        [IO.File]::Move($identityLeaf, $identityBackup)
        [IO.File]::Move($identityAlternate, $identityLeaf)
        [IO.File]::WriteAllText($identityRelease, 'release')
        try {
            $identitySnapshot = $identityTask.GetAwaiter().GetResult()
            [IO.File]::Move($identityLeaf, $identityCaptured)
            [IO.File]::Move($identityBackup, $identityLeaf)
            if ($identitySnapshot.MatchesCurrent()) {
                Add-Failure 'Same-length worktree replacement was accepted.'
            }
        }
        catch {
            Add-Failure 'Same-length worktree replacement fixture failed.'
        }
    }

    # 同一file ID/dev+inodeの内容をBへ書き換えた後にAへ戻しても、hash一致だけ
    # では受理しない。ChangeTime/ctimeを含むversionの変化を最終照合で拒否する。
    $inPlaceLeaf = Join-Path $identityRoot 'in-place.txt'
    [IO.File]::WriteAllText($inPlaceLeaf, 'AAAA')
    try {
        $inPlaceSnapshot =
            [AgenticCodingSecurityGate.PrivateMarkerWorktreeSnapshot]::Capture(
                $identityRoot,
                [string[]]@('in-place.txt'),
                1024
            )
        [IO.File]::WriteAllText($inPlaceLeaf, 'BBBB')
        [IO.File]::WriteAllText($inPlaceLeaf, 'AAAA')
        if ($inPlaceSnapshot.MatchesCurrent()) {
            Add-Failure 'In-place worktree modification and restore was accepted.'
        }
    }
    catch {
        Add-Failure 'In-place worktree version fixture failed.'
    }

    # 親componentを一時junction/symlinkへ差し替え、release後に元へ戻す。
    # openat/O_NOFOLLOWまたはOPEN_REPARSE_POINT chainが外部targetを読まず拒否する。
    $reparseRoot = Join-Path $tempRoot 'stable-reparse'
    $reparseExternal = Join-Path $tempRoot 'stable-reparse-external'
    $reparseDirectory = Join-Path $reparseRoot 'swap'
    $reparseBackup = Join-Path $reparseRoot 'swap-original'
    New-Item -ItemType Directory -Path $reparseDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $reparseExternal -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $reparseDirectory 'safe.txt'),
        'inside'
    )
    [IO.File]::WriteAllText(
        (Join-Path $reparseExternal 'safe.txt'),
        'outside'
    )
    $reparseReady = Join-Path $tempRoot 'reparse-ready'
    $reparseRelease = Join-Path $tempRoot 'reparse-release'
    [AgenticCodingSecurityGate.PrivateMarkerWorktreeSnapshot]::
        ConfigureSingleTestPauseBeforeLeaf(
            $reparseReady,
            $reparseRelease,
            5000
        )
    $reparseTask =
        [AgenticCodingSecurityGate.PrivateMarkerWorktreeSnapshot]::
            CaptureWithConfiguredTestPauseAsync(
                $reparseRoot,
                [string[]]@('swap', 'safe.txt'),
                1024
            )
    $reparseLinkCreated = $false
    if (-not (Wait-ForTestPath -LiteralPath $reparseReady)) {
        Add-Failure 'Reparse test did not reach the component-open pause.'
    } else {
        [IO.Directory]::Move($reparseDirectory, $reparseBackup)
        try {
            $linkType = if ($runtimeIsWindows) {
                'Junction'
            } else {
                'SymbolicLink'
            }
            [void](New-Item `
                -ItemType $linkType `
                -Path $reparseDirectory `
                -Target $reparseExternal `
                -ErrorAction Stop)
            $reparseLinkCreated = $true
        }
        catch {
            Write-Host 'SKIP transient reparse creation is unavailable on this host.'
        }
        [IO.File]::WriteAllText($reparseRelease, 'release')
        $reparseRejected = $false
        try {
            [void]$reparseTask.GetAwaiter().GetResult()
        }
        catch {
            $reparseRejected = $true
        }
        if ($reparseLinkCreated -and -not $reparseRejected) {
            Add-Failure 'Transient parent reparse path was followed.'
        }
        if ($reparseLinkCreated) {
            Remove-TestDirectoryLink -LiteralPath $reparseDirectory
        }
        if (Test-Path -LiteralPath $reparseBackup -PathType Container) {
            [IO.Directory]::Move($reparseBackup, $reparseDirectory)
        }
    }

    # cleanup実装そのものをsource ASTから取り出し、既知path名の内側に置いた
    # nested junction/symlinkを空targetでも列挙・削除しないことを固定する。
    $scannerTokens = $null
    $scannerParseErrors = $null
    $scannerAst = [Management.Automation.Language.Parser]::ParseFile(
        $scanner,
        [ref]$scannerTokens,
        [ref]$scannerParseErrors
    )
    $cleanupDefinitions = @(
        $scannerAst.FindAll(
            {
                param($node)
                return $node -is
                        [Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Remove-ScannerIsolationDirectory'
            },
            $true
        )
    )
    if ($scannerParseErrors.Count -gt 0 -or
        $cleanupDefinitions.Count -ne 1) {
        Add-Failure 'Isolation cleanup function could not be extracted.'
    } else {
        Invoke-Expression $cleanupDefinitions[0].Extent.Text
        function Assert-ScanDeadline {
        }
        function Stop-ScanIntegrityFailure {
            param([string]$Reason)
            throw "integrity:$Reason"
        }
        $pathComparer = if ($runtimeIsWindows) {
            [StringComparer]::OrdinalIgnoreCase
        } else {
            [StringComparer]::Ordinal
        }
        $TestOnlyCreateCleanupUnknownEntry = $false
        $cleanupReparseRoot = Join-Path $tempRoot 'cleanup-nested-reparse'
        $cleanupDataRoot = Join-Path $cleanupReparseRoot 'data'
        $cleanupPowerShellRoot = Join-Path $cleanupDataRoot 'powershell'
        $cleanupModules = Join-Path $cleanupPowerShellRoot 'Modules'
        $cleanupExternal = Join-Path $tempRoot 'cleanup-empty-external'
        New-Item `
            -ItemType Directory `
            -Path $cleanupPowerShellRoot `
            -Force | Out-Null
        New-Item `
            -ItemType Directory `
            -Path $cleanupExternal `
            -Force | Out-Null
        $cleanupLinkType = if ($runtimeIsWindows) {
            'Junction'
        } else {
            'SymbolicLink'
        }
        $cleanupLinkCreated = $false
        try {
            [void](New-Item `
                -ItemType $cleanupLinkType `
                -Path $cleanupModules `
                -Target $cleanupExternal `
                -Force)
            $cleanupLinkCreated = $true
            $cleanupRejected = $false
            try {
                Remove-ScannerIsolationDirectory `
                    -LiteralPath $cleanupReparseRoot
            }
            catch {
                $cleanupRejected =
                    $_.Exception.Message -eq
                        'integrity:process-boundary-cleanup'
            }
            if (-not $cleanupRejected -or
                -not (Test-Path -LiteralPath $cleanupExternal -PathType Container)) {
                Add-Failure 'Nested cleanup reparse point was not rejected.'
            }
        }
        catch {
            Add-Failure 'Nested cleanup reparse fixture failed.'
        }
        finally {
            if ($cleanupLinkCreated -and
                (Test-Path -LiteralPath $cleanupModules)) {
                Remove-TestDirectoryLink -LiteralPath $cleanupModules
            }
        }
    }

    # stream cleanupの2段waitが同じbudgetを再利用して倍化しないことを固定する。
    $pendingCompletion =
        New-Object 'System.Threading.Tasks.TaskCompletionSource[bool]'
    $pendingStream = New-Object System.IO.MemoryStream
    $cleanupClock = [Diagnostics.Stopwatch]::StartNew()
    $cleanupCompleted = Complete-PrivateMarkerAtomicStreams `
        -Streams @($pendingStream) `
        -Tasks @($pendingCompletion.Task) `
        -WaitMilliseconds 100
    $cleanupClock.Stop()
    if ($cleanupCompleted -or $cleanupClock.ElapsedMilliseconds -ge 400) {
        Add-Failure 'Atomic stream cleanup reused its bounded wait budget.'
    }

    $selfSource = [IO.File]::ReadAllText($selfTestScriptPath)
    if (-not (Test-FirstBoundedInvocationIsRawTransport -Source $selfSource)) {
        Add-Failure 'Raw binary transport is not the first executable bounded helper invocation.'
    }

    # helper欠落のbootstrap failureもpath/exceptionを再生せず固定reasonへ畳む。
    $missingHelperRoot = Join-Path $tempRoot 'missing-process-helper'
    New-Item -ItemType Directory -Path $missingHelperRoot | Out-Null
    $isolatedScanner = Join-Path $missingHelperRoot 'scan-private-markers.ps1'
    Copy-Item -LiteralPath $scanner -Destination $isolatedScanner
    $missingHelperResult = Invoke-BoundaryScanner `
        -ScanPath $tempRoot `
        -ScanMode worktree `
        -ScannerPath $isolatedScanner
    Assert-IntegrityFailure `
        -Result $missingHelperResult `
        -Reason 'process-boundary-setup' `
        -Context 'Missing bounded process helper'
    if ($missingHelperResult.Output.Contains($missingHelperRoot) -or
        $missingHelperResult.Output.Contains($isolatedScanner)) {
        Add-Failure 'Process helper bootstrap failure replayed a local path.'
    }

    $gitCommands = @(
        Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    )
    if ($gitCommands.Count -eq 0) {
        Add-Failure 'Native Git is required for scanner boundary tests.'
    } else {
        $gitPath = $gitCommands[0].Source
        $gitRoot = Join-Path $tempRoot 'git-fixture'
        $gitIsolation = Join-Path $tempRoot 'git-isolation'
        New-Item -ItemType Directory -Path $gitRoot | Out-Null
        New-Item -ItemType Directory -Path $gitIsolation | Out-Null

        # Git child setupそのものをoperation deadlineへ含め、遅延/failureの
        # どちらでもprocess起動前に短いwall-clock上限でfail closedする。
        $setupDelayObserved = $false
        $setupDelayClock = [Diagnostics.Stopwatch]::StartNew()
        try {
            [void](Invoke-PrivateMarkerBoundedProcess `
                -FileName $gitPath `
                -Arguments @('--version') `
                -IsolationRoot (Join-Path $tempRoot 'setup-delay-isolation') `
                -TimeoutMilliseconds 125 `
                -ForceSetupDelayMilliseconds 1000)
        }
        catch {
            $setupDelayObserved =
                $_.Exception.Message -match 'operation deadline'
        }
        $setupDelayClock.Stop()
        if (-not $setupDelayObserved -or
            $setupDelayClock.ElapsedMilliseconds -ge 750) {
            Add-Failure 'Git child setup delay escaped the operation deadline.'
        }

        $setupFailureRoot = Join-Path $tempRoot 'setup-root-file'
        [IO.File]::WriteAllText(
            $setupFailureRoot,
            'not-a-directory',
            [Text.UTF8Encoding]::new($false)
        )
        $setupFailureObserved = $false
        $setupFailureClock = [Diagnostics.Stopwatch]::StartNew()
        try {
            [void](Invoke-PrivateMarkerBoundedProcess `
                -FileName $gitPath `
                -Arguments @('--version') `
                -IsolationRoot $setupFailureRoot `
                -TimeoutMilliseconds 500)
        }
        catch {
            $setupFailureObserved = $true
        }
        $setupFailureClock.Stop()
        if (-not $setupFailureObserved -or
            $setupFailureClock.ElapsedMilliseconds -ge 750) {
            Add-Failure 'Git child setup failure was not bounded.'
        }

        $initResult = Invoke-IsolatedGit `
            -GitPath $gitPath `
            -WorkingDirectory $gitRoot `
            -IsolationRoot $gitIsolation `
            -Arguments @('init', '-q')
        if (-not (Test-BoundedResultHealthy -Result $initResult) -or
            $initResult.ExitCode -ne 0) {
            Add-Failure 'Git fixture initialization failed.'
        } else {
            # unknown cleanup entryでは深い再帰へ進まず、同じscan deadline内に
            # path-free固定理由でexit 2へ畳む。
            $cleanupBoundaryClock = [Diagnostics.Stopwatch]::StartNew()
            $cleanupBoundaryResult = Invoke-BoundaryScanner `
                -ScanPath $gitRoot `
                -ScanMode tracked `
                -ScanDeadlineMilliseconds 15000 `
                -TestOnlyCreateCleanupUnknownEntry
            $cleanupBoundaryClock.Stop()
            Assert-IntegrityFailure `
                -Result $cleanupBoundaryResult `
                -Reason 'process-boundary-cleanup' `
                -Context 'Bounded isolation cleanup'
            if ($cleanupBoundaryClock.ElapsedMilliseconds -ge 15000 -or
                $cleanupBoundaryResult.Output.Contains($gitRoot)) {
                Add-Failure 'Isolation cleanup exceeded its deadline or leaked a path.'
            }

            # 実git cat-file batchを通し、PS5.1でもBOMなしの完全binary responseを固定する。
            $blobBytes = [byte[]]@(0, 128, 255, 10, 13, 1, 2)
            [IO.File]::WriteAllBytes(
                (Join-Path $gitRoot 'blob.bin'),
                $blobBytes
            )
            $hashResult = Invoke-IsolatedGit `
                -GitPath $gitPath `
                -WorkingDirectory $gitRoot `
                -IsolationRoot $gitIsolation `
                -Arguments @('hash-object', '-w', '--', 'blob.bin')
            $objectId = [Text.Encoding]::ASCII.GetString(
                $hashResult.StdoutBytes
            ).Trim()
            if (-not (Test-BoundedResultHealthy -Result $hashResult) -or
                $hashResult.ExitCode -ne 0 -or
                $objectId -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
                Add-Failure 'Git binary object fixture creation failed.'
            } else {
                $encodingBefore = [Console]::InputEncoding
                $batchInput = [Text.Encoding]::ASCII.GetBytes("$objectId`n")
                $batchResult = Invoke-IsolatedGit `
                    -GitPath $gitPath `
                    -WorkingDirectory $gitRoot `
                    -IsolationRoot $gitIsolation `
                    -Arguments @('cat-file', '--batch') `
                    -StandardInputBytes $batchInput
                $headerBytes = [Text.Encoding]::ASCII.GetBytes(
                    "$objectId blob $($blobBytes.Length)`n"
                )
                $expectedBatch = [byte[]](
                    @($headerBytes) + @($blobBytes) + @(10)
                )
                if (-not (Test-BoundedResultHealthy -Result $batchResult) -or
                    $batchResult.ExitCode -ne 0 -or
                    $batchResult.StderrBytes.Length -ne 0 -or
                    [Convert]::ToBase64String($batchResult.StdoutBytes) -ne
                        [Convert]::ToBase64String($expectedBatch)) {
                    Add-Failure 'Git cat-file batch transport was not byte-exact.'
                }
                if ([Console]::InputEncoding.CodePage -ne
                    $encodingBefore.CodePage -or
                    [Convert]::ToBase64String(
                        [Console]::InputEncoding.GetPreamble()
                    ) -ne
                    [Convert]::ToBase64String(
                        $encodingBefore.GetPreamble()
                    )) {
                    Add-Failure 'Raw stdin transport changed caller console encoding.'
                }
            }

            # staged-onlyとworktree-onlyを別provenanceで検出する。
            $trackedPath = Join-Path $gitRoot 'tracked.txt'
            [IO.File]::WriteAllText(
                $trackedPath,
                'safe fixture',
                [Text.UTF8Encoding]::new($false)
            )
            $addResult = Invoke-IsolatedGit `
                -GitPath $gitPath `
                -WorkingDirectory $gitRoot `
                -IsolationRoot $gitIsolation `
                -Arguments @('add', '--', 'tracked.txt')
            if ($addResult.ExitCode -ne 0) {
                Add-Failure 'Git staged fixture setup failed.'
            }

            $syntheticMarker = ('g' + 'hp_') + ('A' * 24)
            [IO.File]::WriteAllText(
                $trackedPath,
                $syntheticMarker,
                [Text.UTF8Encoding]::new($false)
            )
            [void](Invoke-IsolatedGit `
                -GitPath $gitPath `
                -WorkingDirectory $gitRoot `
                -IsolationRoot $gitIsolation `
                -Arguments @('add', '--', 'tracked.txt'))
            [IO.File]::WriteAllText(
                $trackedPath,
                'safe worktree fixture',
                [Text.UTF8Encoding]::new($false)
            )
            $stagedResult = Invoke-BoundaryScanner `
                -ScanPath $gitRoot `
                -ScanMode tracked
            $stagedText = Get-ResultText -Result $stagedResult
            if (-not (Test-BoundedResultHealthy -Result $stagedResult) -or
                $stagedResult.ExitCode -ne 1 -or
                $stagedText -notmatch 'github-classic-token-prefix' -or
                $stagedText -notmatch '\[index\]' -or
                $stagedText.Contains($syntheticMarker)) {
                Add-Failure 'Staged-only marker detection or redaction failed.'
            }

            [void](Invoke-IsolatedGit `
                -GitPath $gitPath `
                -WorkingDirectory $gitRoot `
                -IsolationRoot $gitIsolation `
                -Arguments @('add', '--', 'tracked.txt'))
            [IO.File]::WriteAllText(
                $trackedPath,
                $syntheticMarker,
                [Text.UTF8Encoding]::new($false)
            )
            $worktreeResult = Invoke-BoundaryScanner `
                -ScanPath $gitRoot `
                -ScanMode tracked
            $worktreeText = Get-ResultText -Result $worktreeResult
            if (-not (Test-BoundedResultHealthy -Result $worktreeResult) -or
                $worktreeResult.ExitCode -ne 1 -or
                $worktreeText -notmatch 'github-classic-token-prefix' -or
                $worktreeText -notmatch '\[worktree\]' -or
                $worktreeText.Contains($syntheticMarker)) {
                Add-Failure 'Worktree-only marker detection or redaction failed.'
            }

            # hostile ambient Git redirectはscanner内部のhermetic childへ継承しない。
            $hostileResult = Invoke-BoundaryScanner `
                -ScanPath $gitRoot `
                -ScanMode tracked `
                -InheritedEnvironment @{
                    GIT_INDEX_FILE = Join-Path $tempRoot 'foreign-index'
                    GIT_CONFIG_COUNT = '1'
                    GIT_CONFIG_KEY_0 = 'protocol.allow'
                    GIT_CONFIG_VALUE_0 = 'always'
                }
            $hostileText = Get-ResultText -Result $hostileResult
            if ($hostileResult.ExitCode -ne 1 -or
                $hostileText -notmatch 'github-classic-token-prefix') {
                Add-Failure 'Ambient Git redirects changed the trusted scan target.'
            }

            [IO.File]::WriteAllText(
                $trackedPath,
                'safe final fixture',
                [Text.UTF8Encoding]::new($false)
            )
            [void](Invoke-IsolatedGit `
                -GitPath $gitPath `
                -WorkingDirectory $gitRoot `
                -IsolationRoot $gitIsolation `
                -Arguments @('add', '--', 'tracked.txt'))
            $successResult = Invoke-BoundaryScanner `
                -ScanPath $gitRoot `
                -ScanMode tracked
            $successText = Get-ResultText -Result $successResult
            if (-not (Test-BoundedResultHealthy -Result $successResult) -or
                $successResult.ExitCode -ne 0 -or
                $successText.Contains($gitRoot) -or
                -not $successText.EndsWith([Environment]::NewLine) -or
                ($successResult.StdoutBytes.Length -ge 3 -and
                    $successResult.StdoutBytes[0] -eq 239 -and
                    $successResult.StdoutBytes[1] -eq 187 -and
                    $successResult.StdoutBytes[2] -eq 191)) {
                Add-Failure 'Success output leaked an absolute path or was not atomic BOM-less UTF-8.'
            }

            # linked worktreeの有効`.git` gitfileをmetadata ancestorとして認識し、
            # 通常のGit index scanへ進めることを実repositoryで固定する。
            $commitResult = Invoke-IsolatedGit `
                -GitPath $gitPath `
                -WorkingDirectory $gitRoot `
                -IsolationRoot $gitIsolation `
                -Arguments @(
                    '-c',
                    'user.name=Boundary Test',
                    '-c',
                    'user.email=bot@example.com',
                    'commit',
                    '-q',
                    '-m',
                    'boundary fixture'
                )
            $linkedRoot = Join-Path $tempRoot 'linked-worktree'
            $linkedAddResult = if ($commitResult.ExitCode -eq 0) {
                Invoke-IsolatedGit `
                    -GitPath $gitPath `
                    -WorkingDirectory $gitRoot `
                    -IsolationRoot $gitIsolation `
                    -Arguments @(
                        'worktree',
                        'add',
                        '--detach',
                        $linkedRoot,
                        'HEAD'
                    )
            } else {
                $null
            }
            if ($null -eq $linkedAddResult -or
                $linkedAddResult.ExitCode -ne 0 -or
                -not (Test-Path `
                    -LiteralPath (Join-Path $linkedRoot '.git') `
                    -PathType Leaf)) {
                Add-Failure 'Linked worktree gitfile fixture setup failed.'
            } else {
                $linkedResult = Invoke-BoundaryScanner `
                    -ScanPath $linkedRoot `
                    -ScanMode auto
                if (-not (Test-BoundedResultHealthy -Result $linkedResult) -or
                    $linkedResult.ExitCode -ne 0) {
                    Add-Failure 'Valid linked worktree gitfile was not scanned.'
                }
            }
        }
    }

    $missingPath = Join-Path $tempRoot 'does-not-exist'
    $missingResult = Invoke-BoundaryScanner `
        -ScanPath $missingPath `
        -ScanMode worktree
    $missingText = Get-ResultText -Result $missingResult
    Assert-IntegrityFailure `
        -Result $missingResult `
        -Reason 'scan-root-missing' `
        -Context 'Missing root'
    if ($missingText.Contains($missingPath)) {
        Add-Failure 'Missing root diagnostic replayed the supplied path.'
    }

    # public parameterの範囲外値もPowerShell既定binding errorへ落とさず固定出力に畳む。
    $invalidArgumentResult = Invoke-BoundaryScanner `
        -ScanPath $tempRoot `
        -ScanMode worktree `
        -ScanDeadlineMilliseconds 0
    Assert-IntegrityFailure `
        -Result $invalidArgumentResult `
        -Reason 'argument-validation' `
        -Context 'Public argument validation'
    if ($invalidArgumentResult.Output -match
        'ValidateRange|ParameterBinding|ScanDeadlineMilliseconds') {
        Add-Failure 'Public argument validation replayed binding details.'
    }

    if (-not $runtimeIsWindows) {
        # POSIXでは`.GIT`は通常fileであり、PowerShellのcase-insensitive
        # `-eq`でWindows用`.git`除外へ巻き込まない。
        $upperGitRoot = Join-Path $tempRoot 'upper-git-leaf'
        New-Item -ItemType Directory -Path $upperGitRoot | Out-Null
        $upperGitMarker = ('g' + 'hp_') + ('B' * 24)
        [IO.File]::WriteAllText(
            (Join-Path $upperGitRoot '.GIT'),
            $upperGitMarker,
            [Text.UTF8Encoding]::new($false)
        )
        $upperGitResult = Invoke-BoundaryScanner `
            -ScanPath $upperGitRoot `
            -ScanMode worktree
        $upperGitText = Get-ResultText -Result $upperGitResult
        if (-not (Test-BoundedResultHealthy -Result $upperGitResult) -or
            $upperGitResult.ExitCode -ne 1 -or
            $upperGitText -notmatch 'github-classic-token-prefix' -or
            $upperGitText -notmatch '\.GIT' -or
            $upperGitText.Contains($upperGitMarker)) {
            Add-Failure 'POSIX .GIT leaf was incorrectly excluded or unredacted.'
        }
    }

    # root/ancestor × file/directoryの4形態を固定し、Git probe失敗をcleanへ落とさない。
    foreach ($shape in @(
        'root-file',
        'root-directory',
        'ancestor-file',
        'ancestor-directory'
    )) {
        $shapeRoot = Join-Path $tempRoot $shape
        $scanRoot = $shapeRoot
        New-Item -ItemType Directory -Path $shapeRoot | Out-Null
        if ($shape.StartsWith('ancestor-')) {
            $scanRoot = Join-Path $shapeRoot 'child'
            New-Item -ItemType Directory -Path $scanRoot | Out-Null
        }
        $markerParent = if ($shape.StartsWith('ancestor-')) {
            $shapeRoot
        } else {
            $scanRoot
        }
        $gitMarker = Join-Path $markerParent '.git'
        if ($shape.EndsWith('-directory')) {
            New-Item -ItemType Directory -Path $gitMarker | Out-Null
        } else {
            [IO.File]::WriteAllText(
                $gitMarker,
                'gitdir: missing',
                [Text.UTF8Encoding]::new($false)
            )
        }
        [IO.File]::WriteAllText(
            (Join-Path $scanRoot 'safe.txt'),
            'safe',
            [Text.UTF8Encoding]::new($false)
        )
        $shapeResult = Invoke-BoundaryScanner `
            -ScanPath $scanRoot `
            -ScanMode auto
        Assert-IntegrityFailure `
            -Result $shapeResult `
            -Reason 'git-probe' `
            -Context ".git ancestry $shape"
    }

    # dangling metadata entryもentry名で検出する。作成不能hostは明示skipする。
    $danglingRoot = Join-Path $tempRoot 'dangling-git'
    $danglingTarget = Join-Path $tempRoot 'dangling-target'
    New-Item -ItemType Directory -Path $danglingRoot | Out-Null
    New-Item -ItemType Directory -Path $danglingTarget | Out-Null
    $danglingCreated = $false
    try {
        $linkType = if ($runtimeIsWindows) { 'Junction' } else { 'SymbolicLink' }
        [void](New-Item `
            -ItemType $linkType `
            -Path (Join-Path $danglingRoot '.git') `
            -Target $danglingTarget `
            -ErrorAction Stop)
        Remove-Item -LiteralPath $danglingTarget -Force
        $danglingCreated = $true
    }
    catch {
        Write-Host 'SKIP dangling .git link creation is unavailable on this host.'
    }
    if ($danglingCreated) {
        $danglingResult = Invoke-BoundaryScanner `
            -ScanPath $danglingRoot `
            -ScanMode auto
        Assert-IntegrityFailure `
            -Result $danglingResult `
            -Reason 'git-probe' `
            -Context 'Dangling .git ancestry'
    }

    $deadlineRoot = Join-Path $tempRoot 'deadline'
    New-Item -ItemType Directory -Path $deadlineRoot | Out-Null
    1..64 | ForEach-Object {
        [IO.File]::WriteAllText(
            (Join-Path $deadlineRoot "file-$_.txt"),
            'safe',
            [Text.UTF8Encoding]::new($false)
        )
    }
    $deadlineResult = Invoke-BoundaryScanner `
        -ScanPath $deadlineRoot `
        -ScanMode worktree `
        -ScanDeadlineMilliseconds 1
    Assert-IntegrityFailure `
        -Result $deadlineResult `
        -Reason 'scan-deadline' `
        -Context 'Scan-wide lower-only deadline'

    $invalidUtf8Root = Join-Path $tempRoot 'invalid-utf8'
    New-Item -ItemType Directory -Path $invalidUtf8Root | Out-Null
    [IO.File]::WriteAllBytes(
        (Join-Path $invalidUtf8Root 'invalid.txt'),
        [byte[]]@(255, 254, 128)
    )
    $invalidUtf8Result = Invoke-BoundaryScanner `
        -ScanPath $invalidUtf8Root `
        -ScanMode worktree
    Assert-IntegrityFailure `
        -Result $invalidUtf8Result `
        -Reason 'scan-target-encoding' `
        -Context 'Invalid UTF-8 text'

    # 多数の長いsanitized pathでreport byte capを超え、partial tableを出さない。
    $reportRoot = Join-Path $tempRoot 'report-overflow'
    New-Item -ItemType Directory -Path $reportRoot | Out-Null
    $reportMarker = ('g' + 'hp_') + ('B' * 24)
    1..100 | ForEach-Object {
        $longName = (('f' * 150) + ('{0:D3}.txt' -f $_))
        [IO.File]::WriteAllText(
            (Join-Path $reportRoot $longName),
            $reportMarker,
            [Text.UTF8Encoding]::new($false)
        )
    }
    $reportResult = Invoke-BoundaryScanner `
        -ScanPath $reportRoot `
        -ScanMode worktree
    $reportText = Get-ResultText -Result $reportResult
    Assert-IntegrityFailure `
        -Result $reportResult `
        -Reason 'finding-output-budget' `
        -Context 'Atomic finding report'
    if ($reportText -match "File`tLine`tRule`tValue" -or
        $reportText.Contains($reportMarker)) {
        Add-Failure 'Finding report overflow emitted a partial table or raw value.'
    }

    # direct child timeout後もpipeを握るgrandchildと遅延sentinelを有限に回収する。
    $timeoutSentinel = Join-Path $tempRoot 'grandchild-survived'
    $escapedSentinel = $timeoutSentinel.Replace("'", "''")
    $timeoutTargetDelayMilliseconds = if ($runtimeIsWindows) {
        1500
    } else {
        6000
    }
    $timeoutBudgetMilliseconds = if ($runtimeIsWindows) {
        1100
    } else {
        4000
    }
    $timeoutWallClockLimitMilliseconds = if ($runtimeIsWindows) {
        1500
    } else {
        5000
    }
    $grandchildScript = @"
Start-Sleep -Milliseconds $timeoutTargetDelayMilliseconds
[IO.File]::WriteAllText('$escapedSentinel', 'survived')
"@
    $grandchildEncoded = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($grandchildScript)
    )
    $escapedPwsh = $currentPowerShellExecutable.Replace("'", "''")
    $parentScript = @"
& '$escapedPwsh' -NoProfile -EncodedCommand '$grandchildEncoded'
Start-Sleep -Seconds 30
"@
    $parentEncoded = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($parentScript)
    )
    $timeoutArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $timeoutArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $timeoutArguments += @('-EncodedCommand', $parentEncoded)
    $timeoutClock = [Diagnostics.Stopwatch]::StartNew()
    $timeoutResult = Invoke-PrivateMarkerBoundedProcess `
        -FileName $currentPowerShellExecutable `
        -Arguments $timeoutArguments `
        -IsolationRoot (Join-Path $tempRoot 'timeout-isolation') `
        -TimeoutMilliseconds $timeoutBudgetMilliseconds `
        -DrainTimeoutMilliseconds 3000
    $timeoutClock.Stop()
    for ($sentinelAttempt = 0;
        $sentinelAttempt -lt 25;
        $sentinelAttempt++) {
        if (Test-Path -LiteralPath $timeoutSentinel) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $timeoutResult.TimedOut -or
        -not $timeoutResult.TreeStopped -or
        -not $timeoutResult.StreamsDrained -or
        $timeoutClock.ElapsedMilliseconds -ge
            $timeoutWallClockLimitMilliseconds -or
        (Test-Path -LiteralPath $timeoutSentinel)) {
        Add-Failure 'Timeout cleanup did not stop and drain the owned process tree.'
    }

    if (-not $runtimeIsWindows) {
        $posixModes = @(
            [pscustomobject]@{ Name = 'native'; ForceNative = $true }
        )
        if ((Test-Path -LiteralPath '/usr/bin/setsid' -PathType Leaf) -or
            (Test-Path -LiteralPath '/bin/setsid' -PathType Leaf)) {
            $posixModes += [pscustomobject]@{
                Name = 'external'
                ForceNative = $false
            }
        } else {
            Write-Host 'SKIP external setsid is unavailable on this host.'
        }

        # external/nativeの双方で、readiness前はPGIDを所有したことにせず
        # direct wrapperだけをdeadline内に回収し、targetを一度もreleaseしない。
        foreach ($posixMode in $posixModes) {
            $posixReadySentinel = Join-Path `
                $tempRoot `
                "posix-ready-target-ran-$($posixMode.Name)"
            $escapedPosixReadySentinel =
                $posixReadySentinel.Replace("'", "''")
            $posixTargetScript = @"
[IO.File]::WriteAllText('$escapedPosixReadySentinel', 'ran')
Start-Sleep -Seconds 30
"@
            $posixTargetEncoded = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($posixTargetScript)
            )
            $posixGateIsolation = Join-Path `
                $tempRoot `
                "posix-ready-isolation-$($posixMode.Name)"
            $posixReadyFailureObserved = $false
            $posixReadyClock = [Diagnostics.Stopwatch]::StartNew()
            try {
                [void](Invoke-PrivateMarkerBoundedProcess `
                    -FileName $currentPowerShellExecutable `
                    -Arguments @(
                        '-NoProfile',
                        '-EncodedCommand',
                        $posixTargetEncoded
                    ) `
                    -IsolationRoot $posixGateIsolation `
                    -TimeoutMilliseconds 500 `
                    -DrainTimeoutMilliseconds 1000 `
                    -ForceNativePosixSessionGate:$posixMode.ForceNative `
                    -ForceNativePosixReadyDelayMilliseconds 3000)
            }
            catch {
                $posixReadyFailureObserved =
                    $_.Exception.Message -match 'POSIX session gate'
            }
            $posixReadyClock.Stop()
            Start-Sleep -Milliseconds 600
            $remainingGateFiles = @(
                Get-ChildItem `
                    -LiteralPath $posixGateIsolation `
                    -Filter 'posix-session-*' `
                    -File `
                    -ErrorAction SilentlyContinue
            )
            if (-not $posixReadyFailureObserved -or
                $posixReadyClock.ElapsedMilliseconds -ge 1000 -or
                (Test-Path -LiteralPath $posixReadySentinel) -or
                $remainingGateFiles.Count -gt 0) {
                Add-Failure (
                    "$($posixMode.Name) POSIX readiness escaped " +
                    'the operation deadline.'
                )
            }
        }

        # native fallbackでもanchorのSIGKILL codeではなくtargetのexit codeと
        # byte列を返す。external経路はtop-level raw transportで同じ契約を通る。
        $nativeRawResult = Invoke-PrivateMarkerBoundedProcess `
            -FileName $currentPowerShellExecutable `
            -Arguments $rawArguments `
            -IsolationRoot (Join-Path $tempRoot 'native-raw-isolation') `
            -StandardInputBytes $rawInput `
            -TimeoutMilliseconds 5000 `
            -MaxStdoutBytes 64 `
            -MaxStderrBytes 64 `
            -ForceNativePosixSessionGate
        if (-not (Test-BoundedResultHealthy -Result $nativeRawResult) -or
            $nativeRawResult.ExitCode -ne 37 -or
            [Convert]::ToBase64String($nativeRawResult.StdoutBytes) -ne
                [Convert]::ToBase64String($rawInput) -or
            [Convert]::ToBase64String($nativeRawResult.StderrBytes) -ne
                [Convert]::ToBase64String($expectedRawStderr)) {
            Add-Failure 'Native POSIX anchor did not preserve raw transport.'
        }

        # targetが正常終了した後もanchorをliveに保ち、遅延descendantをgroup
        # cleanupしてからtarget codeを返す。
        foreach ($posixMode in $posixModes) {
            $normalSentinel = Join-Path `
                $tempRoot `
                "posix-normal-descendant-$($posixMode.Name)"
            $escapedNormalSentinel = $normalSentinel.Replace("'", "''")
            $descendantScript = @"
Start-Sleep -Milliseconds 1200
[IO.File]::WriteAllText('$escapedNormalSentinel', 'survived')
"@
            $descendantEncoded = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($descendantScript)
            )
            $escapedPosixPwsh =
                $currentPowerShellExecutable.Replace("'", "''")
            $normalTargetScript = @"
`$info = [Diagnostics.ProcessStartInfo]::new()
`$info.FileName = '$escapedPosixPwsh'
`$info.UseShellExecute = `$false
`$info.ArgumentList.Add('-NoProfile')
`$info.ArgumentList.Add('-EncodedCommand')
`$info.ArgumentList.Add('$descendantEncoded')
[void][Diagnostics.Process]::Start(`$info)
exit 23
"@
            $normalTargetEncoded = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($normalTargetScript)
            )
            $normalResult = Invoke-PrivateMarkerBoundedProcess `
                -FileName $currentPowerShellExecutable `
                -Arguments @(
                    '-NoProfile',
                    '-EncodedCommand',
                    $normalTargetEncoded
                ) `
                -IsolationRoot (
                    Join-Path `
                        $tempRoot `
                        "posix-normal-isolation-$($posixMode.Name)"
                ) `
                -TimeoutMilliseconds 5000 `
                -ForceNativePosixSessionGate:$posixMode.ForceNative
            Start-Sleep -Milliseconds 1400
            if (-not (Test-BoundedResultHealthy -Result $normalResult) -or
                $normalResult.ExitCode -ne 23 -or
                (Test-Path -LiteralPath $normalSentinel)) {
                Add-Failure (
                    "$($posixMode.Name) POSIX anchor did not preserve " +
                    'target exit or stop descendants.'
                )
            }
        }

        # reap済みownerの数値PID/PGIDへnegative signalを送らない契約を固定する。
        $shortProcess = [Diagnostics.Process]::Start('/bin/true')
        [void]$shortProcess.WaitForExit(5000)
        $emptyJobHandle = [IntPtr]::Zero
        $staleCleanupResult = Stop-PrivateMarkerOwnedProcessTreeBounded `
            -Process $shortProcess `
            -WindowsJobHandle ([ref]$emptyJobHandle) `
            -PosixProcessGroupId $shortProcess.Id `
            -WaitMilliseconds 100
        if ($staleCleanupResult) {
            Add-Failure 'Reaped POSIX owner was accepted for group cleanup.'
        }
        $shortProcess.Dispose()
    }

    if ($runtimeIsWindows) {
        # assign/resume失敗ではsuspended targetを一度も実行せずPIDを回収する。
        foreach ($launchFailureMode in @('assign', 'resume')) {
            $launchSentinel = Join-Path `
                $tempRoot `
                "launch-$launchFailureMode-ran"
            $escapedLaunchSentinel = $launchSentinel.Replace("'", "''")
            $launchScript = @"
[IO.File]::WriteAllText('$escapedLaunchSentinel', 'ran')
"@
            $launchEncoded = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($launchScript)
            )
            $launchObserved = $false
            $launchClock = [Diagnostics.Stopwatch]::StartNew()
            try {
                [void](Invoke-PrivateMarkerBoundedProcess `
                    -FileName $currentPowerShellExecutable `
                    -Arguments @(
                        '-NoProfile',
                        '-ExecutionPolicy',
                        'Bypass',
                        '-EncodedCommand',
                        $launchEncoded
                    ) `
                    -IsolationRoot (
                        Join-Path $tempRoot "launch-$launchFailureMode"
                    ) `
                    -TimeoutMilliseconds 10000 `
                    -ForceWindowsLaunchFailure $launchFailureMode)
            }
            catch {
                $launchObserved = $true
            }
            $launchClock.Stop()
            $launchPid =
                [AgenticSecurityGateContainedProcess]::
                    LastSyntheticFailureProcessId
            $processGone = $false
            for ($pidAttempt = 0; $pidAttempt -lt 20; $pidAttempt++) {
                if ($launchPid -gt 0 -and
                    $null -eq (Get-Process `
                        -Id $launchPid `
                        -ErrorAction SilentlyContinue)) {
                    $processGone = $true
                    break
                }
                Start-Sleep -Milliseconds 50
            }
            if (-not $launchObserved -or
                $launchPid -le 0 -or
                -not $processGone -or
                $launchClock.ElapsedMilliseconds -ge 6000 -or
                (Test-Path -LiteralPath $launchSentinel)) {
                Add-Failure "$launchFailureMode launch failure lifecycle was not bounded."
            }
        }

        # CloseHandle faultでもJob handleを保持し、retry/Job terminate/direct
        # terminate/Disposeの全段を有限に通してdescendantを残さない。
        $closeSentinel = Join-Path $tempRoot 'close-failure-descendant-ran'
        $escapedCloseSentinel = $closeSentinel.Replace("'", "''")
        $closeGrandchildScript = @"
Start-Sleep -Milliseconds 1500
[IO.File]::WriteAllText('$escapedCloseSentinel', 'ran')
"@
        $closeGrandchildEncoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($closeGrandchildScript)
        )
        $closeParentScript = @"
& '$escapedPwsh' -NoProfile -ExecutionPolicy Bypass -EncodedCommand '$closeGrandchildEncoded'
Start-Sleep -Seconds 30
"@
        $closeParentEncoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($closeParentScript)
        )
        $closeFailureObserved = $false
        $closeFailureText = ''
        $closeClock = [Diagnostics.Stopwatch]::StartNew()
        try {
            [void](Invoke-PrivateMarkerBoundedProcess `
                -FileName $currentPowerShellExecutable `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy',
                    'Bypass',
                    '-EncodedCommand',
                    $closeParentEncoded
                ) `
                -IsolationRoot (Join-Path $tempRoot 'close-failure') `
                -TimeoutMilliseconds 500 `
                -DrainTimeoutMilliseconds 3000 `
                -ForceWindowsLaunchFailure close)
        }
        catch {
            $closeFailureObserved = $true
            $closeFailureText = $_.Exception.ToString()
        }
        $closeClock.Stop()
        $closePid =
            [AgenticSecurityGateContainedProcess]::LastSyntheticFailureProcessId
        $closeProcessGone = $false
        for ($closePidAttempt = 0;
            $closePidAttempt -lt 20;
            $closePidAttempt++) {
            if ($closePid -gt 0 -and
                $null -eq (Get-Process `
                    -Id $closePid `
                    -ErrorAction SilentlyContinue)) {
                $closeProcessGone = $true
                break
            }
            Start-Sleep -Milliseconds 50
        }
        for ($closeSentinelAttempt = 0;
            $closeSentinelAttempt -lt 25;
            $closeSentinelAttempt++) {
            if (Test-Path -LiteralPath $closeSentinel) {
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $closeFailureObserved -or
            $closeFailureText -notmatch
                'Contained child execution and cleanup failed' -or
            $closeFailureText -notmatch 'Synthetic Job close failure' -or
            $closePid -le 0 -or
            -not $closeProcessGone -or
            $closeClock.ElapsedMilliseconds -ge 8000 -or
            (Test-Path -LiteralPath $closeSentinel)) {
            Add-Failure 'Job close failure lifecycle was not bounded and aggregated.'
        }

        # normal returnのfinallyで初回CloseJobだけが失敗しても、Dispose内で
        # direct fallbackと再closeを行い、成功後だけdisposedを確定する。
        $disposeSentinel = Join-Path $tempRoot 'dispose-descendant-ran'
        $disposeOut = Join-Path $tempRoot 'dispose-descendant.out'
        $disposeErr = Join-Path $tempRoot 'dispose-descendant.err'
        $escapedDisposeSentinel = $disposeSentinel.Replace("'", "''")
        $escapedDisposeOut = $disposeOut.Replace("'", "''")
        $escapedDisposeErr = $disposeErr.Replace("'", "''")
        $disposeGrandchildScript = @"
Start-Sleep -Milliseconds 1500
[IO.File]::WriteAllText('$escapedDisposeSentinel', 'ran')
"@
        $disposeGrandchildEncoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($disposeGrandchildScript)
        )
        $disposeParentScript = @"
Start-Process -FilePath '$escapedPwsh' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand','$disposeGrandchildEncoded') -WindowStyle Hidden -RedirectStandardOutput '$escapedDisposeOut' -RedirectStandardError '$escapedDisposeErr'
"@
        $disposeParentEncoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($disposeParentScript)
        )
        $disposeFailureObserved = $false
        $disposeFailureText = ''
        $disposeClock = [Diagnostics.Stopwatch]::StartNew()
        try {
            [void](Invoke-PrivateMarkerBoundedProcess `
                -FileName $currentPowerShellExecutable `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy',
                    'Bypass',
                    '-EncodedCommand',
                    $disposeParentEncoded
                ) `
                -IsolationRoot (Join-Path $tempRoot 'dispose-failure') `
                -TimeoutMilliseconds 10000 `
                -DrainTimeoutMilliseconds 3000 `
                -ForceWindowsLaunchFailure dispose)
        }
        catch {
            $disposeFailureObserved = $true
            $disposeFailureText = $_.Exception.ToString()
        }
        $disposeClock.Stop()
        $disposePid =
            [AgenticSecurityGateContainedProcess]::LastSyntheticFailureProcessId
        $disposeAttempts =
            [AgenticSecurityGateContainedProcess]::
                LastSyntheticJobCloseAttemptCount
        $disposeProcessGone = $false
        for ($disposePidAttempt = 0;
            $disposePidAttempt -lt 20;
            $disposePidAttempt++) {
            if ($disposePid -gt 0 -and
                $null -eq (Get-Process `
                    -Id $disposePid `
                    -ErrorAction SilentlyContinue)) {
                $disposeProcessGone = $true
                break
            }
            Start-Sleep -Milliseconds 50
        }
        for ($disposeSentinelAttempt = 0;
            $disposeSentinelAttempt -lt 25;
            $disposeSentinelAttempt++) {
            if (Test-Path -LiteralPath $disposeSentinel) {
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $disposeFailureObserved -or
            $disposeFailureText -notmatch 'Synthetic Job close failure' -or
            $disposeAttempts -ne 2 -or
            $disposePid -le 0 -or
            -not $disposeProcessGone -or
            $disposeClock.ElapsedMilliseconds -ge 8000 -or
            (Test-Path -LiteralPath $disposeSentinel)) {
            Add-Failure 'Normal-return Dispose did not retry and close the Job.'
        }
    }
}
finally {
    Remove-TestTree -LiteralPath $tempRoot
}

if ($failures.Count -gt 0) {
    Write-Host 'Scanner boundary self-test failed:'
    foreach ($failure in $failures) {
        Write-Host "- $failure"
    }
    exit 1
}

Write-Host 'Scanner boundary self-test passed.'
exit 0
