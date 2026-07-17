<#
.SYNOPSIS
Builds and validates the Construction Pipeline Optimizer support-branch cascade.

.DESCRIPTION
The cascade follows the same direction as Better Work Tab:

  Dev -> Support/1.5 -> ... -> Support/0.13 -> Support/Alpha4

Dev contains only RimWorld 1.6 source and build references. Each Support/<version>
branch owns the source and project adaptations for its historical API. The cascade
merges modern changes downward, builds and audits on the owning branch, and copies
only rebuilt versioned DLL folders back to Dev. Nothing is pushed unless -Push is
provided explicitly.
#>
param(
    [string]$SourceBranch = 'Dev',
    [string]$Remote = 'origin',
    [string]$ReleaseLabel = 'v1.0',
    [string[]]$SupportVersions = @(
        '1.5', '1.4', '1.3', '1.2', '1.1', '1.0', '0.19', '0.18',
        '0.17', '0.16', '0.15', '0.14', '0.13', 'Alpha4'),
    [switch]$SkipSourceBuild,
    [switch]$SkipPayloadCopyBackToDev,
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$projectPath = Join-Path $projectRoot 'Source\ConstructionPipelineOptimizer.csproj'
$payloadName = 'Construction Pipeline Optimizer.dll'

function Invoke-Git
{
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    Write-Host ">> git $($Arguments -join ' ')"
    & git @Arguments
    if ($LASTEXITCODE -ne 0)
    {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Get-GitOutput
{
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git @Arguments)
    if ($LASTEXITCODE -ne 0)
    {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }

    return $output
}

function Assert-CleanWorktree
{
    $status = @(Get-GitOutput status --porcelain)
    if ($status.Count -gt 0)
    {
        throw "The support cascade requires a clean worktree:`n$($status -join [Environment]::NewLine)"
    }
}

function Test-BranchExists
{
    param([string]$Branch)
    & git show-ref --verify --quiet "refs/heads/$Branch"
    return $LASTEXITCODE -eq 0
}

function Merge-SupportSource
{
    param(
        [string]$PreviousBranch,
        [string]$Version,
        [string]$Message
    )

    Write-Host ">> git merge --no-ff $PreviousBranch"
    & git merge --no-ff $PreviousBranch -m $Message
    if ($LASTEXITCODE -eq 0)
    {
        return
    }

    $unmerged = @(Get-GitOutput diff --name-only --diff-filter=U)
    $versionedPayload = "$Version/Assemblies/$payloadName"
    $allowed = @($unmerged | Where-Object {
        $_ -eq 'About/About.xml' -or
        $_ -eq 'Assemblies/Construction Pipeline Optimizer.dll' -or
        $_ -eq $versionedPayload
    })
    $unexpected = @($unmerged | Where-Object { $_ -notin $allowed })
    if ($unmerged.Count -eq 0 -or $unexpected.Count -gt 0)
    {
        throw "Merge from $PreviousBranch stopped at non-payload conflicts:`n$($unexpected -join [Environment]::NewLine)"
    }

    # Legacy support branches intentionally retain their own metadata and root
    # payload until the target API is rebuilt immediately after this merge.
    Invoke-Git checkout --ours -- @allowed
    Invoke-Git add -- @allowed
    Invoke-Git commit -m $Message -m "Retain RimWorld $Version legacy metadata/root payload; the cascade rebuild follows immediately."
}

function Build-Version
{
    param([string]$Version)

    Write-Host "== Building RimWorld $Version =="
    & dotnet build $projectPath -c $Version
    if ($LASTEXITCODE -ne 0)
    {
        throw "RimWorld $Version build failed with exit code $LASTEXITCODE"
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-ApiSurface.ps1') -Versions $Version
    if ($LASTEXITCODE -ne 0)
    {
        throw "RimWorld $Version API-shape audit failed with exit code $LASTEXITCODE"
    }
}

function Set-LegacyAbout
{
    param([string]$Version)

    $targetVersions = @{
        '0.18' = '0.18.1722'
        '0.17' = '0.17.1557'
        '0.16' = '0.16.1393'
        '0.15' = '0.15.1284'
        '0.14' = '0.14.1249'
        '0.13' = '0.13.1137'
        'Alpha4' = '0.4.460'
    }

    if (-not $targetVersions.ContainsKey($Version))
    {
        return
    }

    $targetVersion = $targetVersions[$Version]
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<ModMetaData>
  <name>Construction Pipeline Optimizer</name>
  <author>Coolnether123</author>
  <targetVersion>$targetVersion</targetVersion>
  <description>Reduces repeated active construction validation and redundant zero-cost terrain work selection. Requires Harmony. No settings or save data.</description>
</ModMetaData>
"@
    [System.IO.File]::WriteAllText((Join-Path $projectRoot 'About\About.xml'), $xml)
}

function Sync-BranchPayload
{
    param([string]$Version)

    $versionedPayload = Join-Path $projectRoot "$Version\Assemblies\$payloadName"
    if (-not (Test-Path -LiteralPath $versionedPayload))
    {
        throw "Built payload is missing: $versionedPayload"
    }

    if ($Version -eq 'Alpha4' -or $Version.StartsWith('0.'))
    {
        $rootAssemblies = Join-Path $projectRoot 'Assemblies'
        New-Item -ItemType Directory -Force -Path $rootAssemblies | Out-Null
        Copy-Item -LiteralPath $versionedPayload -Destination (Join-Path $rootAssemblies $payloadName) -Force
    }

    if ($Version -eq 'Alpha4')
    {
        $sourceDef = Join-Path $projectRoot 'Alpha4\Defs\ConstructionPipelineOptimizerBootstrap.xml'
        $rootDefs = Join-Path $projectRoot 'Defs\ConstructionPipelineOptimizerBootstrap'
        New-Item -ItemType Directory -Force -Path $rootDefs | Out-Null
        Copy-Item -LiteralPath $sourceDef -Destination (Join-Path $rootDefs 'ConstructionPipelineOptimizerBootstrap.xml') -Force
    }

    Set-LegacyAbout $Version
}

function Commit-BranchPayload
{
    param([string]$Version)

    $paths = @("$Version/Assemblies")
    if ($Version -eq 'Alpha4' -or $Version.StartsWith('0.'))
    {
        $paths += 'Assemblies'
    }
    if ($Version -in @('0.18', '0.17', '0.16', '0.15', '0.14', '0.13', 'Alpha4'))
    {
        $paths += 'About/About.xml'
    }
    if ($Version -eq 'Alpha4')
    {
        $paths += 'Defs/ConstructionPipelineOptimizerBootstrap'
    }

    Invoke-Git add -- @paths
    $changes = @(Get-GitOutput status --porcelain -- @paths)
    if ($changes.Count -eq 0)
    {
        Write-Host "No payload changes to commit for RimWorld $Version."
        return
    }

    Invoke-Git commit -m "Build RimWorld $Version payload for $ReleaseLabel" -m "Build and API-audit the version-specific construction optimization payload."
}

Set-Location $projectRoot
Assert-CleanWorktree

& dotnet run --project (Join-Path $projectRoot 'Tests\ConstructionPipelineOptimizer.Tests.csproj') -c Release
if ($LASTEXITCODE -ne 0)
{
    throw "Shared policy tests failed with exit code $LASTEXITCODE"
}

Invoke-Git checkout $SourceBranch
if (-not $SkipSourceBuild)
{
    Build-Version '1.6'
    Commit-BranchPayload '1.6'
    Assert-CleanWorktree
}

$previousBranch = $SourceBranch
foreach ($version in $SupportVersions)
{
    $branch = "Support/$version"
    if (-not (Test-BranchExists $branch))
    {
        throw (
            "Missing branch $branch. Historical API source must be created and reviewed " +
            "on its own Support/<version> branch; the cascade will not synthesize it from " +
            "$previousBranch.")
    }

    Invoke-Git checkout $branch
    Assert-CleanWorktree
    Merge-SupportSource `
        -PreviousBranch $previousBranch `
        -Version $version `
        -Message "Merge $previousBranch into RimWorld $version support for $ReleaseLabel"

    Build-Version $version
    Sync-BranchPayload $version
    Commit-BranchPayload $version
    Assert-CleanWorktree
    $previousBranch = $branch
}

if (-not $SkipPayloadCopyBackToDev)
{
    Invoke-Git checkout $SourceBranch
    Assert-CleanWorktree
    foreach ($version in $SupportVersions)
    {
        Invoke-Git checkout "Support/$version" -- "$version/Assemblies"
    }

    $payloadPaths = @($SupportVersions | ForEach-Object { "$_/Assemblies" })
    $statusArguments = @('status', '--porcelain', '--') + $payloadPaths
    $payloadChanges = @(Get-GitOutput @statusArguments)
    if ($payloadChanges.Count -gt 0)
    {
        Invoke-Git add -- @payloadPaths
        Invoke-Git commit -m "Update $SourceBranch support payloads for $ReleaseLabel" -m 'Copy only rebuilt versioned assemblies back from the completed support cascade.'
    }
}

if ($Push)
{
    $branches = @($SourceBranch) + ($SupportVersions | ForEach-Object { "Support/$_" })
    Invoke-Git push $Remote @branches
}

Invoke-Git checkout $SourceBranch
Assert-CleanWorktree
Write-Host 'Construction Pipeline Optimizer support cascade complete.'
