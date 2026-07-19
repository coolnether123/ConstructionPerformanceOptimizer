param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$stagingBase = [System.IO.Path]::GetFullPath((Join-Path $projectRoot '.release-staging'))
$expectedStagingBase = $projectRoot.TrimEnd('\') + '\.release-staging'
if (-not $stagingBase.Equals($expectedStagingBase, [System.StringComparison]::OrdinalIgnoreCase))
{
    throw "Unsafe staging path resolved outside the expected project location: $stagingBase"
}

$modernVersions = @('1.0', '1.1', '1.2', '1.3', '1.4', '1.5', '1.6')
$legacyVersions = @('Alpha4', '0.13', '0.14', '0.15', '0.16', '0.17', '0.18', '0.19')
$multiplayerVersions = @('1.5', '1.6')
$targetVersions = @{
    'Alpha4' = '0.4.460'
    '0.13' = '0.13.1137'
    '0.14' = '0.14.1249'
    '0.15' = '0.15.1284'
    '0.16' = '0.16.1393'
    '0.17' = '0.17.1557'
    '0.18' = '0.18.1722'
    '0.19' = '0.19.2009'
}

# Dev owns the current 1.6 source. Historical DLLs are deliberately built on their
# Support/* branches and collected in Dev by the support cascade.
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-AllVersions.ps1') -Versions 1.6
if ($LASTEXITCODE -ne 0)
{
    throw "Current-version build workflow failed with exit code $LASTEXITCODE."
}

[xml]$about = Get-Content -LiteralPath (Join-Path $projectRoot 'About\About.xml') -Raw
$version = [string]$about.ModMetaData.modVersion
$releaseLabel = if ($version -match '^(\d+\.\d+)\.0$') { $Matches[1] } else { $version }
$releaseDirectory = Join-Path $projectRoot 'Releases'
$packageName = 'ConstructionPerformanceOptimizer'
$stagedPackage = Join-Path $stagingBase $packageName
$stagedLegacyRoot = Join-Path $stagingBase 'Legacy'
$releaseVersionRoot = [System.IO.Path]::GetFullPath((Join-Path $releaseDirectory "$packageName-$releaseLabel"))
$releaseDirectoryPrefix = [System.IO.Path]::GetFullPath($releaseDirectory).TrimEnd('\') + '\'
if (-not $releaseVersionRoot.StartsWith($releaseDirectoryPrefix, [System.StringComparison]::OrdinalIgnoreCase))
{
    throw "Unsafe release folder resolved outside the project release directory: $releaseVersionRoot"
}
$publishFolder = Join-Path $releaseVersionRoot $packageName
$archivePath = Join-Path $releaseDirectory "$packageName-$releaseLabel.zip"

if (((Test-Path -LiteralPath $archivePath) -or (Test-Path -LiteralPath $releaseVersionRoot)) -and -not $Force)
{
    throw "Release artifacts already exist for version $version. Pass -Force to replace them."
}

function Copy-CommonReleaseFiles
{
    param([string]$Destination)

    foreach ($relativePath in 'LICENSE', 'README.md', 'CHANGELOG.md')
    {
        Copy-Item -LiteralPath (Join-Path $projectRoot $relativePath) -Destination $Destination
    }
}

function Copy-VersionAssembly
{
    param(
        [string]$RimWorldVersion,
        [string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot "$RimWorldVersion\Assemblies\Construction Performance Optimizer.dll") -Destination $Destination
    if ($multiplayerVersions -contains $RimWorldVersion)
    {
        Copy-Item -LiteralPath (Join-Path $projectRoot "$RimWorldVersion\Assemblies\0MultiplayerAPI.dll") -Destination $Destination
    }
}

function New-LegacyAbout
{
    param(
        [string]$RimWorldVersion,
        [string]$Destination
    )

    $aboutDirectory = Join-Path $Destination 'About'
    New-Item -ItemType Directory -Force -Path $aboutDirectory | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'About\Preview.png') -Destination $aboutDirectory

    $displayVersion = if ($RimWorldVersion -eq 'Alpha4') { 'Alpha 4' } else { $RimWorldVersion }
    $benefit = 'CPO avoids an unnecessary global job search when a pawn can continue eligible zero-cost terrain construction.'

    $description = "Construction Performance Optimizer 1.0. $benefit The benefit is largest in construction-heavy colonies and with terrain-building mods. It does not change construction speed or bypass normal gameplay rules. Supports RimWorld $displayVersion single-player only; Multiplayer is not supported on this version. Requires Harmony. No settings or save data. Do not enable this with Construction Queue Optimizer because that legacy package contains the same patches."
    $legacyAbout = @"
<?xml version="1.0" encoding="utf-8"?>
<ModMetaData>
  <name>Construction Performance Optimizer</name>
  <author>Coolnether123</author>
  <targetVersion>$($targetVersions[$RimWorldVersion])</targetVersion>
  <description>$description</description>
</ModMetaData>
"@
    [System.IO.File]::WriteAllText((Join-Path $aboutDirectory 'About.xml'), $legacyAbout)
}

function New-ReleaseArchive
{
    param(
        [string]$Source,
        [string]$Destination
    )

    $checksumPath = "$Destination.sha256"
    if (Test-Path -LiteralPath $Destination)
    {
        Remove-Item -LiteralPath $Destination -Force
    }
    if (Test-Path -LiteralPath $checksumPath)
    {
        Remove-Item -LiteralPath $checksumPath -Force
    }

    Compress-Archive -LiteralPath $Source -DestinationPath $Destination -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    [System.IO.File]::WriteAllText($checksumPath, "$hash  $([System.IO.Path]::GetFileName($Destination))`n")
    return $hash
}

if (Test-Path -LiteralPath $stagingBase)
{
    Remove-Item -LiteralPath $stagingBase -Recurse -Force
}
if (Test-Path -LiteralPath $releaseVersionRoot)
{
    Remove-Item -LiteralPath $releaseVersionRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $stagedPackage, $stagedLegacyRoot, $releaseDirectory | Out-Null

try
{
    Copy-Item -LiteralPath (Join-Path $projectRoot 'About') -Destination $stagedPackage -Recurse
    foreach ($modernVersion in $modernVersions)
    {
        Copy-VersionAssembly -RimWorldVersion $modernVersion -Destination (Join-Path $stagedPackage "$modernVersion\Assemblies")
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'LoadFolders.xml') -Destination $stagedPackage
    Copy-CommonReleaseFiles -Destination $stagedPackage

    foreach ($legacyVersion in $legacyVersions)
    {
        $legacyPackage = Join-Path $stagedLegacyRoot "$legacyVersion\$packageName"
        New-Item -ItemType Directory -Force -Path $legacyPackage | Out-Null
        New-LegacyAbout -RimWorldVersion $legacyVersion -Destination $legacyPackage
        Copy-VersionAssembly -RimWorldVersion $legacyVersion -Destination (Join-Path $legacyPackage 'Assemblies')
        Copy-CommonReleaseFiles -Destination $legacyPackage
    }

    & (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot $stagedPackage -Distribution
    if ($LASTEXITCODE -ne 0)
    {
        throw "Modern distribution validation failed with exit code $LASTEXITCODE."
    }
    foreach ($legacyVersion in $legacyVersions)
    {
        & (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot (Join-Path $stagedLegacyRoot "$legacyVersion\$packageName") -LegacyVersion $legacyVersion -Distribution
        if ($LASTEXITCODE -ne 0)
        {
            throw "RimWorld $legacyVersion distribution validation failed with exit code $LASTEXITCODE."
        }
    }

    New-Item -ItemType Directory -Force -Path $releaseVersionRoot | Out-Null
    Copy-Item -LiteralPath $stagedPackage -Destination $releaseVersionRoot -Recurse
    Copy-Item -LiteralPath $stagedLegacyRoot -Destination $releaseVersionRoot -Recurse

    $legacyArchiveRoot = Join-Path $releaseVersionRoot 'LegacyArchives'
    New-Item -ItemType Directory -Force -Path $legacyArchiveRoot | Out-Null
    foreach ($legacyVersion in $legacyVersions)
    {
        $legacyArchive = Join-Path $legacyArchiveRoot "$packageName-$releaseLabel-rw$legacyVersion.zip"
        $null = New-ReleaseArchive -Source (Join-Path $releaseVersionRoot "Legacy\$legacyVersion\$packageName") -Destination $legacyArchive
    }

    $installGuide = @"
Construction Performance Optimizer $releaseLabel

RimWorld 1.0-1.6:
Install the ConstructionPerformanceOptimizer folder. It selects the matching build automatically.

RimWorld Alpha 4-0.19:
Open Legacy, choose your exact game version, and install the ConstructionPerformanceOptimizer folder inside it.
Ready-to-share ZIPs for those versions are also in LegacyArchives.

Multiplayer support is limited to RimWorld 1.5 and 1.6. All older builds are single-player only.
Harmony is required for every version.
"@
    [System.IO.File]::WriteAllText((Join-Path $releaseVersionRoot 'INSTALL.txt'), $installGuide)

    & (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot $publishFolder -Distribution
    if ($LASTEXITCODE -ne 0)
    {
        throw "Persistent publish-folder validation failed with exit code $LASTEXITCODE."
    }
    foreach ($legacyVersion in $legacyVersions)
    {
        & (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot (Join-Path $releaseVersionRoot "Legacy\$legacyVersion\$packageName") -LegacyVersion $legacyVersion -Distribution
        if ($LASTEXITCODE -ne 0)
        {
            throw "Published RimWorld $legacyVersion package validation failed with exit code $LASTEXITCODE."
        }
    }

    $hash = New-ReleaseArchive -Source $publishFolder -Destination $archivePath
    Write-Output "Workshop-ready folder (RimWorld 1.0-1.6): $publishFolder"
    Write-Output "Legacy single-version packages (Alpha 4-0.19): $(Join-Path $releaseVersionRoot 'Legacy')"
    Write-Output "Release archive: $archivePath"
    Write-Output "SHA-256: $hash"
}
finally
{
    if (Test-Path -LiteralPath $stagingBase)
    {
        Remove-Item -LiteralPath $stagingBase -Recurse -Force
    }
}
