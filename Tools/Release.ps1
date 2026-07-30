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

$cascadeManifest = Get-Content -Raw -LiteralPath (
    Join-Path $PSScriptRoot 'CascadeManifest.json') | ConvertFrom-Json
$modernVersions = @(
    @($cascadeManifest.supportVersions | ForEach-Object { [string]$_ }) +
    [string]$cascadeManifest.sourceVersion |
        Sort-Object { [version]$_ })
$multiplayerVersions = @('1.5', '1.6')

# main owns the current 1.6 source. Historical DLLs are deliberately built on
# their Support/* branches and collected in main by the support cascade.
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

New-Item -ItemType Directory -Force -Path $stagedPackage, $releaseDirectory | Out-Null

try
{
    Copy-Item -LiteralPath (Join-Path $projectRoot 'About') -Destination $stagedPackage -Recurse
    foreach ($modernVersion in $modernVersions)
    {
        Copy-VersionAssembly -RimWorldVersion $modernVersion -Destination (Join-Path $stagedPackage "$modernVersion\Assemblies")
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'LoadFolders.xml') -Destination $stagedPackage
    Copy-CommonReleaseFiles -Destination $stagedPackage

    & (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot $stagedPackage -Distribution
    if ($LASTEXITCODE -ne 0)
    {
        throw "Modern distribution validation failed with exit code $LASTEXITCODE."
    }
    New-Item -ItemType Directory -Force -Path $releaseVersionRoot | Out-Null
    Copy-Item -LiteralPath $stagedPackage -Destination $releaseVersionRoot -Recurse

    $installGuide = @"
Construction Performance Optimizer $releaseLabel

RimWorld 1.0-1.6:
Install the ConstructionPerformanceOptimizer folder. It selects the matching build automatically.

Multiplayer support is limited to RimWorld 1.5 and 1.6. RimWorld 1.0-1.4 builds are single-player only.
Harmony is required for every version.
"@
    [System.IO.File]::WriteAllText((Join-Path $releaseVersionRoot 'INSTALL.txt'), $installGuide)

    & (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot $publishFolder -Distribution
    if ($LASTEXITCODE -ne 0)
    {
        throw "Persistent publish-folder validation failed with exit code $LASTEXITCODE."
    }
    $hash = New-ReleaseArchive -Source $publishFolder -Destination $archivePath
    Write-Output "Workshop-ready folder (RimWorld 1.0-1.6): $publishFolder"
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
