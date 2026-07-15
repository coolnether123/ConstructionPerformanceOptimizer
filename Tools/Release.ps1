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

# The public 1.0.0 package supports RimWorld 1.6 only. Older API builds remain
# repository engineering fixtures and are deliberately excluded from this archive.
$modernVersions = @('1.6')
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-AllVersions.ps1') -Versions $modernVersions
if ($LASTEXITCODE -ne 0)
{
    throw "Build workflow failed with exit code $LASTEXITCODE."
}

[xml]$about = Get-Content -LiteralPath (Join-Path $projectRoot 'About\About.xml') -Raw
$version = [string]$about.ModMetaData.modVersion
$releaseDirectory = Join-Path $projectRoot 'Releases'
$packageName = 'ConstructionPipelineOptimizer'
$stagedPackage = Join-Path $stagingBase $packageName
$releaseVersionRoot = [System.IO.Path]::GetFullPath((Join-Path $releaseDirectory "$packageName-$version"))
$releaseDirectoryPrefix = [System.IO.Path]::GetFullPath($releaseDirectory).TrimEnd('\') + '\'
if (-not $releaseVersionRoot.StartsWith($releaseDirectoryPrefix, [System.StringComparison]::OrdinalIgnoreCase))
{
    throw "Unsafe release folder resolved outside the project release directory: $releaseVersionRoot"
}
$publishFolder = Join-Path $releaseVersionRoot $packageName
$archivePath = Join-Path $releaseDirectory "$packageName-$version.zip"
$checksumPath = "$archivePath.sha256"

if (((Test-Path -LiteralPath $archivePath) -or (Test-Path -LiteralPath $releaseVersionRoot)) -and -not $Force)
{
    throw "Release artifacts already exist for version $version. Pass -Force to replace them."
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
        $stagedAssemblies = Join-Path $stagedPackage "$modernVersion\Assemblies"
        New-Item -ItemType Directory -Force -Path $stagedAssemblies | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot "$modernVersion\Assemblies\Construction Pipeline Optimizer.dll") -Destination $stagedAssemblies
    }

    foreach ($relativePath in 'LoadFolders.xml', 'LICENSE', 'README.md', 'CHANGELOG.md')
    {
        Copy-Item -LiteralPath (Join-Path $projectRoot $relativePath) -Destination $stagedPackage
    }

    & (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot $stagedPackage -Distribution
    if ($LASTEXITCODE -ne 0)
    {
        throw "Distribution validation failed with exit code $LASTEXITCODE."
    }

    New-Item -ItemType Directory -Force -Path $releaseVersionRoot | Out-Null
    Copy-Item -LiteralPath $stagedPackage -Destination $releaseVersionRoot -Recurse
    & (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot $publishFolder -Distribution
    if ($LASTEXITCODE -ne 0)
    {
        throw "Persistent publish-folder validation failed with exit code $LASTEXITCODE."
    }

    if (Test-Path -LiteralPath $archivePath)
    {
        Remove-Item -LiteralPath $archivePath -Force
    }
    if (Test-Path -LiteralPath $checksumPath)
    {
        Remove-Item -LiteralPath $checksumPath -Force
    }

    Compress-Archive -LiteralPath $stagedPackage -DestinationPath $archivePath -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    [System.IO.File]::WriteAllText($checksumPath, "$hash  $([System.IO.Path]::GetFileName($archivePath))`n")

    Write-Output "Workshop-ready folder: $publishFolder"
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
