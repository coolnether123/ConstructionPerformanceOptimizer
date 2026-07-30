<#
.SYNOPSIS
Builds and validates the Construction Performance Optimizer support-branch cascade.

.DESCRIPTION
The cascade follows this direction:

  main -> Support/1.5 -> ... -> Support/1.0

The source branch contains only RimWorld 1.6 source and build references. `main`
is the canonical source branch; callers may explicitly select `Dev` if the
repository later adopts that name. There is no `Support/1.6` branch. Each
Support/<version> branch owns the source and project adaptations for an older
API. The cascade merges modern changes downward, builds and audits on the owning
branch, and copies only rebuilt versioned DLL folders back to the source branch.
Nothing is pushed unless -Push is provided explicitly.
#>
param(
    [string]$SourceBranch,
    [string]$Remote = 'origin',
    [string]$ReleaseLabel = 'v1.0',
    [switch]$SkipSourceBuild,
    [Alias('SkipPayloadCopyBackToDev')]
    [switch]$SkipPayloadCopyBackToSource,
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$projectPath = Join-Path $projectRoot 'Source\ConstructionPerformanceOptimizer.csproj'
$payloadName = 'Construction Performance Optimizer.dll'
$cascadeManifestPath = Join-Path $PSScriptRoot 'CascadeManifest.json'
$cascadeManifest = Get-Content -Raw -LiteralPath $cascadeManifestPath |
    ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($SourceBranch))
{
    $SourceBranch = [string]$cascadeManifest.sourceBranch
}
if (@($cascadeManifest.allowedSourceBranches) -notcontains $SourceBranch)
{
    throw (
        "SourceBranch '$SourceBranch' is not allowed by CascadeManifest.json. " +
        "Allowed branches: $(@($cascadeManifest.allowedSourceBranches) -join ', ').")
}
$SourceVersion = [string]$cascadeManifest.sourceVersion
$SupportVersions = @($cascadeManifest.supportVersions | ForEach-Object {
    [string]$_
})
if ($SupportVersions -contains $SourceVersion)
{
    throw 'CascadeManifest.json cannot list the source version as a support branch.'
}

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
        $_ -eq 'LoadFolders.xml' -or
        $_ -eq 'Assemblies/Construction Performance Optimizer.dll' -or
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

function Set-BranchMetadata
{
    param([string]$Version)

    $aboutPath = Join-Path $projectRoot 'About\About.xml'
    $loadFoldersPath = Join-Path $projectRoot 'LoadFolders.xml'
    $multiplayerText = if ($Version -eq '1.5')
    {
        'Includes the RimWorld 1.5 Multiplayer API 0.5 bridge. Every peer must use the same CPO build and mod list.'
    }
    else
    {
        'This build supports single-player. Multiplayer support begins with the separate RimWorld 1.5 build.'
    }

    $modVersionElement = if ($Version -eq '1.4' -or $Version -eq '1.5')
    {
        '  <modVersion>1.0.0</modVersion>'
    }
    else
    {
        ''
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<ModMetaData>
  <name>Construction Performance Optimizer</name>
  <author>Coolnether123</author>
  <packageId>coolnether123.constructionperformanceoptimizer</packageId>
$modVersionElement
  <supportedVersions>
    <li>$Version</li>
  </supportedVersions>
  <description><![CDATA[Helps construction-heavy colonies run more smoothly by reducing repeated construction work while preserving normal RimWorld behavior.

Version 1.0. The branch is compiled against RimWorld $Version. $multiplayerText

Requires Harmony. No settings or save data.]]></description>
  <modDependencies>
    <li>
      <packageId>brrainz.harmony</packageId>
      <displayName>Harmony</displayName>
      <steamWorkshopUrl>steam://url/CommunityFilePage/2009463077</steamWorkshopUrl>
      <downloadUrl>https://github.com/pardeike/HarmonyRimWorld/releases/latest</downloadUrl>
    </li>
  </modDependencies>
  <loadAfter>
    <li>brrainz.harmony</li>
    <li>ludeon.rimworld</li>
    <li>gt.sam.tilledsoil</li>
  </loadAfter>
  <incompatibleWith>
    <li>coolnether123.constructionqueueoptimizer</li>
  </incompatibleWith>
</ModMetaData>
"@
    [System.IO.File]::WriteAllText($aboutPath, $xml)

    $loadFolders = @"
<?xml version="1.0" encoding="utf-8"?>
<loadFolders>
  <v$Version>
    <li>/</li>
  </v$Version>
</loadFolders>
"@
    [System.IO.File]::WriteAllText($loadFoldersPath, $loadFolders)
}

function Sync-BranchPayload
{
    param([string]$Version)

    $versionedPayload = Join-Path $projectRoot "$Version\Assemblies\$payloadName"
    if (-not (Test-Path -LiteralPath $versionedPayload))
    {
        throw "Built payload is missing: $versionedPayload"
    }

    $rootAssemblies = Join-Path $projectRoot 'Assemblies'
    New-Item -ItemType Directory -Force -Path $rootAssemblies | Out-Null
    Copy-Item -LiteralPath $versionedPayload -Destination (Join-Path $rootAssemblies $payloadName) -Force

    $rootMultiplayerApi = Join-Path $rootAssemblies '0MultiplayerAPI.dll'
    $versionedMultiplayerApi = Join-Path $projectRoot "$Version\Assemblies\0MultiplayerAPI.dll"
    if (Test-Path -LiteralPath $versionedMultiplayerApi)
    {
        Copy-Item -LiteralPath $versionedMultiplayerApi -Destination $rootMultiplayerApi -Force
    }
    elseif (Test-Path -LiteralPath $rootMultiplayerApi)
    {
        Remove-Item -LiteralPath $rootMultiplayerApi -Force
    }

    Set-BranchMetadata $Version
}

function Commit-BranchPayload
{
    param([string]$Version)

    $paths = @("$Version/Assemblies")
    if ($Version -ne $SourceVersion)
    {
        $paths += @(
            'Assemblies',
            'About/About.xml',
            'LoadFolders.xml')
    }
    $stagePaths = @($paths | Where-Object {
        if (Test-Path -LiteralPath $_)
        {
            return $true
        }

        $tracked = @(& git ls-files -- $_)
        return $tracked.Count -gt 0
    })
    if ($stagePaths.Count -gt 0)
    {
        Invoke-Git add -- @stagePaths
    }

    $changes = @(
        if ($stagePaths.Count -gt 0)
        {
            Get-GitOutput status --porcelain -- @stagePaths
        }
    )
    if ($changes.Count -eq 0)
    {
        Write-Host "No payload changes to commit for RimWorld $Version."
        return
    }

    Invoke-Git commit -m "Build RimWorld $Version payload for $ReleaseLabel" -m "Build and API-audit the version-specific construction optimization payload."
}

function Copy-SupportPayloadsBackToSource
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

Set-Location $projectRoot
Assert-CleanWorktree

& dotnet run --project (Join-Path $projectRoot 'Tests\ConstructionPerformanceOptimizer.Tests.csproj') -c Release
if ($LASTEXITCODE -ne 0)
{
    throw "Shared policy tests failed with exit code $LASTEXITCODE"
}

Invoke-Git checkout $SourceBranch
if (-not $SkipSourceBuild)
{
    Build-Version $SourceVersion
    Commit-BranchPayload $SourceVersion
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

    Assert-CleanWorktree
    Build-Version $version
    Sync-BranchPayload $version
    Commit-BranchPayload $version
    Assert-CleanWorktree
    $previousBranch = $branch
}

if (-not $SkipPayloadCopyBackToSource)
{
    Copy-SupportPayloadsBackToSource
}

if ($Push)
{
    $branches = @($SourceBranch) + ($SupportVersions | ForEach-Object { "Support/$_" })
    Invoke-Git push $Remote @branches
}

Invoke-Git checkout $SourceBranch
Assert-CleanWorktree
Write-Host 'Construction Performance Optimizer support cascade complete.'
