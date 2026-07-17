param(
    [string[]]$Versions = @(
        'Alpha4', '0.13', '0.14', '0.15', '0.16', '0.17', '0.18', '0.19',
        '1.0', '1.1', '1.2', '1.3', '1.4', '1.5', '1.6')
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$bwtRoot = 'A:\Dev\GitHub\Coolnether123\Better-Work-Tab'
$rimWorldRoot = Join-Path $bwtRoot 'Decompiled\RimWorld'
$cecilPath = Join-Path $bwtRoot 'Decompiled\Tools\ilspycmd\.store\ilspycmd\9.1.0.7988\ilspycmd\9.1.0.7988\tools\net8.0\any\Mono.Cecil.dll'

if (-not (Test-Path -LiteralPath $cecilPath))
{
    throw "Mono.Cecil was not found at $cecilPath"
}

Add-Type -Path $cecilPath

function Get-AllTypes
{
    param([Mono.Cecil.ModuleDefinition]$Module)

    $result = [System.Collections.Generic.List[Mono.Cecil.TypeDefinition]]::new()
    function Add-TypeAndNested
    {
        param([Mono.Cecil.TypeDefinition]$Type)
        $result.Add($Type)
        foreach ($nested in $Type.NestedTypes)
        {
            Add-TypeAndNested $nested
        }
    }

    foreach ($type in $Module.Types)
    {
        Add-TypeAndNested $type
    }

    return $result
}

function Get-LegacyAssemblyPath
{
    param([string]$Version)

    if ($Version -eq 'Alpha4')
    {
        return Join-Path $rimWorldRoot 'SteamInstall_Alpha4\RimWorldWin_Data\Managed\Assembly-CSharp.dll'
    }

    $dataFolder = if ([version]$Version -le [version]'0.16') { 'RimWorldWin_Data' } else { 'RimWorldWin64_Data' }
    return Join-Path $rimWorldRoot "SteamInstall_$Version\$dataFolder\Managed\Assembly-CSharp.dll"
}

function Get-ModernAssemblyPath
{
    param([string]$Version)

    if ($Version -eq '1.6')
    {
        return 'D:\Steam Library\steamapps\common\RimWorld\RimWorldWin64_Data\Managed\Assembly-CSharp.dll'
    }

    $referenceVersions = @{
        '1.0' = '1.0.2559'
        '1.1' = '1.1.2654'
        '1.2' = '1.2.3062'
        '1.3' = '1.3.3389'
        '1.4' = '1.4.3901'
        '1.5' = '1.5.4409'
    }
    $packageVersion = $referenceVersions[$Version]
    return Join-Path $env:USERPROFILE ".nuget\packages\krafs.rimworld.ref\$packageVersion\ref\net472\Assembly-CSharp.dll"
}

function Get-AssemblyPath
{
    param([string]$Version)
    if ($Version -eq 'Alpha4' -or $Version.StartsWith('0.'))
    {
        return Get-LegacyAssemblyPath $Version
    }

    return Get-ModernAssemblyPath $Version
}

function Get-Calls
{
    param(
        [Mono.Cecil.TypeDefinition]$RootType,
        [string]$CalledMethodName
    )

    $types = [System.Collections.Generic.List[Mono.Cecil.TypeDefinition]]::new()
    function Add-Nested
    {
        param([Mono.Cecil.TypeDefinition]$Type)
        foreach ($nested in $Type.NestedTypes)
        {
            $types.Add($nested)
            Add-Nested $nested
        }
    }

    Add-Nested $RootType
    $calls = @()
    foreach ($type in $types)
    {
        foreach ($method in $type.Methods)
        {
            if (-not $method.HasBody)
            {
                continue
            }

            foreach ($instruction in $method.Body.Instructions)
            {
                if ($instruction.Operand -is [Mono.Cecil.MethodReference] -and
                    $instruction.Operand.Name -eq $CalledMethodName)
                {
                    $calls += [pscustomobject]@{
                        Caller = $method
                        Called = $instruction.Operand
                    }
                }
            }
        }
    }

    return $calls
}

function Assert-Condition
{
    param([bool]$Condition, [string]$Message)
    if (-not $Condition)
    {
        throw $Message
    }
}

$results = @()
foreach ($version in $Versions)
{
    $assemblyPath = Get-AssemblyPath $version
    Assert-Condition (Test-Path -LiteralPath $assemblyPath) "RimWorld $version reference is missing: $assemblyPath"

    $module = [Mono.Cecil.ModuleDefinition]::ReadModule($assemblyPath)
    try
    {
        $allTypes = Get-AllTypes $module
        $driverName = if ($version -eq 'Alpha4') { 'Verse.AI.JobDriver_ConstructFinishFrame' } else { 'RimWorld.JobDriver_ConstructFinishFrame' }
        $placeName = if ($version -eq 'Alpha4') { 'Verse.AI.JobDriver_PlaceNoCostFrame' } else { 'RimWorld.JobDriver_PlaceNoCostFrame' }
        $driver = $allTypes | Where-Object FullName -eq $driverName | Select-Object -First 1
        $placeDriver = $allTypes | Where-Object FullName -eq $placeName | Select-Object -First 1

        Assert-Condition ($null -ne $driver) "RimWorld $version is missing $driverName"
        Assert-Condition ($null -ne $placeDriver) "RimWorld $version is missing $placeName"
        Assert-Condition (($placeDriver.Methods | Where-Object Name -eq 'MakeNewToils').Count -eq 1) "RimWorld $version has an unexpected PlaceNoCostFrame MakeNewToils shape"

        $expectsThrottle = $version -notin @('Alpha4', '0.13', '0.14', '0.15', '0.16', '0.17')
        $genConstruct = if ($expectsThrottle) { $allTypes | Where-Object FullName -eq 'RimWorld.GenConstruct' | Select-Object -First 1 } else { $null }
        if ($expectsThrottle)
        {
            Assert-Condition ($null -ne $genConstruct) "RimWorld $version is missing RimWorld.GenConstruct"
        }
        $hasRuntimeBodies = $version -notin @('1.0', '1.1', '1.2', '1.3', '1.4', '1.5')
        $completionCalls = @()
        $validationCalls = @()
        if ($hasRuntimeBodies)
        {
            $completionCalls = @(Get-Calls $driver 'CompleteConstruction')
            Assert-Condition ($completionCalls.Count -eq 1) "RimWorld $version expected one FinishFrame completion call; found $($completionCalls.Count)"

            $validationCalls = @(Get-Calls $driver 'CanConstruct')
            $expectedValidationCount = if ($expectsThrottle) { 1 } else { 0 }
            Assert-Condition ($validationCalls.Count -eq $expectedValidationCount) "RimWorld $version expected $expectedValidationCount FinishFrame CanConstruct call(s); found $($validationCalls.Count)"

            if ($expectsThrottle)
            {
                $expectedCanConstructParameters = if ($version -eq '0.18') { 3 } elseif ($version -in @('0.19', '1.0', '1.1', '1.2', '1.3', '1.4')) { 4 } else { 5 }
                Assert-Condition ($validationCalls[0].Called.Parameters.Count -eq $expectedCanConstructParameters) "RimWorld $version FinishFrame calls a $($validationCalls[0].Called.Parameters.Count)-parameter CanConstruct overload; expected $expectedCanConstructParameters"
            }
        }

        if ($expectsThrottle)
        {
            $expectedCanConstructParameters = if ($version -eq '0.18') { 3 } elseif ($version -in @('0.19', '1.0', '1.1', '1.2', '1.3', '1.4')) { 4 } else { 5 }
            $matchingCanConstruct = @($genConstruct.Methods | Where-Object {
                $_.Name -eq 'CanConstruct' -and
                $_.Parameters.Count -eq $expectedCanConstructParameters -and
                $_.Parameters[0].ParameterType.FullName -eq 'Verse.Thing' -and
                $_.Parameters[1].ParameterType.FullName -eq 'Verse.Pawn' -and
                $_.Parameters[2].ParameterType.FullName -eq 'System.Boolean'
            })
            Assert-Condition ($matchingCanConstruct.Count -eq 1) "RimWorld $version expected one boolean CanConstruct overload with $expectedCanConstructParameters parameters; found $($matchingCanConstruct.Count)"
        }

        $payload = Join-Path $projectRoot "$version\Assemblies\Construction Pipeline Optimizer.dll"
        Assert-Condition (Test-Path -LiteralPath $payload) "The mod payload for RimWorld $version has not been built: $payload"

        $results += [pscustomobject]@{
            Version = $version
            Continuation = 'verified'
            ValidationThrottle = if (-not $hasRuntimeBodies) { 'compile surface only' } elseif ($expectsThrottle) { 'verified' } else { 'not present in vanilla' }
            CompletionCall = if ($hasRuntimeBodies) { $completionCalls[0].Caller.FullName } else { 'runtime IL unavailable locally' }
            GameAssembly = $assemblyPath
        }
    }
    finally
    {
        $module.Dispose()
    }
}

$results | Format-Table Version, Continuation, ValidationThrottle -AutoSize
Write-Output "RimWorld construction API surface verified for $($results.Count) versions."
