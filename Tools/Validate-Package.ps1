param(
    [Parameter(Mandatory = $true)]
    [string]$PackageRoot,

    [string]$TargetVersion = '1.6',

    [switch]$Distribution
)

$ErrorActionPreference = 'Stop'

function Assert-Condition
{
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition)
    {
        throw $Message
    }
}

function Get-RequiredPath
{
    param([string]$RelativePath)

    $path = Join-Path $PackageRoot $RelativePath
    Assert-Condition (Test-Path -LiteralPath $path) "Required package path is missing: $RelativePath"
    return $path
}

$PackageRoot = [System.IO.Path]::GetFullPath($PackageRoot)
$aboutPath = Get-RequiredPath 'About\About.xml'
$previewPath = Get-RequiredPath 'About\Preview.png'
$loadFoldersPath = Get-RequiredPath 'LoadFolders.xml'
$allowedVersions = @($TargetVersion)
[xml]$about = Get-Content -LiteralPath $aboutPath -Raw
$metadata = $about.ModMetaData
Assert-Condition ($null -ne $metadata) 'About.xml must have ModMetaData as its root element.'
$supportedVersions = @($metadata.supportedVersions.li | ForEach-Object { [string]$_ })
Assert-Condition ($supportedVersions.Count -gt 0) 'About.xml must declare at least one supported RimWorld version.'
foreach ($supportedVersion in $supportedVersions)
{
    Assert-Condition ($allowedVersions -contains $supportedVersion) "About.xml declares an unsupported version: $supportedVersion"
}
$assemblyPaths = @{}
foreach ($supportedVersion in $supportedVersions)
{
    $assemblyPaths[$supportedVersion] = Get-RequiredPath "$supportedVersion\Assemblies\Construction Performance Optimizer.dll"
    if ($supportedVersion -eq '1.5' -or $supportedVersion -eq '1.6')
    {
        $null = Get-RequiredPath "$supportedVersion\Assemblies\0MultiplayerAPI.dll"
    }
}
$null = Get-RequiredPath 'LICENSE'
$null = Get-RequiredPath 'README.md'
$null = Get-RequiredPath 'CHANGELOG.md'

[xml]$loadFolders = Get-Content -LiteralPath $loadFoldersPath -Raw

Assert-Condition ($metadata.name -eq 'Construction Performance Optimizer') 'Unexpected mod name in About.xml.'
Assert-Condition ($metadata.author -eq 'Coolnether123') 'Unexpected author in About.xml.'
Assert-Condition ($metadata.packageId -eq 'coolnether123.constructionperformanceoptimizer') 'Unexpected packageId in About.xml.'
Assert-Condition ($metadata.modVersion -match '^\d+\.\d+\.\d+$') 'modVersion must use semantic version format (major.minor.patch).'
foreach ($supportedVersion in $supportedVersions)
{
    Assert-Condition ($metadata.supportedVersions.li -contains $supportedVersion) "About.xml must explicitly support RimWorld $supportedVersion."
}
Assert-Condition ($metadata.modDependencies.li.packageId -contains 'brrainz.harmony') 'Harmony must be declared as a dependency.'
Assert-Condition ($metadata.incompatibleWith.li -contains 'coolnether123.constructionqueueoptimizer') 'Legacy package incompatibility is missing.'
foreach ($supportedVersion in $supportedVersions)
{
    $loadFolder = $loadFolders.loadFolders.("v$supportedVersion")
    Assert-Condition ($loadFolder.li -contains '/') "LoadFolders.xml must load the package root for $supportedVersion."
    if ($supportedVersion -ne '1.0')
    {
        Assert-Condition ($loadFolder.li -contains $supportedVersion) "LoadFolders.xml must load the $supportedVersion runtime folder."
    }

    $assemblyPath = $assemblyPaths[$supportedVersion]
    Assert-Condition ((Get-Item -LiteralPath $assemblyPath).Length -gt 0) "RimWorld $supportedVersion assembly is empty."
    $assemblyVersion = [System.Reflection.AssemblyName]::GetAssemblyName($assemblyPath).Version
    Assert-Condition ($assemblyVersion.ToString(3) -eq [string]$metadata.modVersion) "RimWorld $supportedVersion assembly version must match About.xml modVersion."

    if ($supportedVersion -eq '1.0')
    {
        $rootAssemblyPath = Get-RequiredPath 'Assemblies\Construction Performance Optimizer.dll'
        Assert-Condition ((Get-FileHash -LiteralPath $rootAssemblyPath -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $assemblyPath -Algorithm SHA256).Hash) 'RimWorld 1.0 root and versioned assemblies must be identical.'
    }
}
Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $PackageRoot 'About\ModIcon.png'))) 'ModIcon.png must not be included in this icon-free package.'

Add-Type -AssemblyName System.Drawing
$preview = [System.Drawing.Image]::FromFile($previewPath)
try
{
    Assert-Condition ($preview.Width -ge 300 -and $preview.Height -ge 300) 'Preview.png must be at least 300x300.'
}
finally
{
    $preview.Dispose()
}

if ($Distribution)
{
    foreach ($excludedPath in 'Source', 'Tests', 'Tools', 'Comparisons', 'Docs', 'Releases', '.release-staging')
    {
        Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $excludedPath))) "Development-only path leaked into distribution: $excludedPath"
    }

    $pdbFiles = @(Get-ChildItem -LiteralPath $PackageRoot -Filter '*.pdb' -File -Recurse -ErrorAction SilentlyContinue)
    Assert-Condition ($pdbFiles.Count -eq 0) 'Debug symbols must not be included in the public runtime archive.'
}

Write-Output "Package validation passed: $PackageRoot (version $($metadata.modVersion), RimWorld $($supportedVersions -join ', ') assemblies)"
