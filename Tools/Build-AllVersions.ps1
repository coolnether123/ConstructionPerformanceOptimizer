param(
    [string[]]$Versions,
    [switch]$SkipPolicyTests,
    [switch]$SkipApiSurfaceTest
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$project = Join-Path $projectRoot 'Source\ConstructionPerformanceOptimizer.csproj'
$cascadeManifest = Get-Content -Raw -LiteralPath (
    Join-Path $PSScriptRoot 'CascadeManifest.json') | ConvertFrom-Json
$sourceVersion = [string]$cascadeManifest.sourceVersion
$sourceBranch = [string]$cascadeManifest.sourceBranch
if ($null -eq $Versions -or $Versions.Count -eq 0)
{
    $Versions = @($sourceVersion)
}
$unsupportedVersions = @($Versions | Where-Object { $_ -ne $sourceVersion })
if ($unsupportedVersions.Count -gt 0)
{
    throw (
        "The $sourceBranch source tree targets RimWorld $sourceVersion only. " +
        "Build historical versions from their Support/<version> branches through " +
        "Invoke-SupportCascade.ps1. Requested here: " +
        ($unsupportedVersions -join ', '))
}

if (-not $SkipPolicyTests)
{
    & dotnet run --project (Join-Path $projectRoot 'Tests\ConstructionPerformanceOptimizer.Tests.csproj') -c Release
    if ($LASTEXITCODE -ne 0)
    {
        throw "Policy tests failed with exit code $LASTEXITCODE"
    }
}

foreach ($version in $Versions)
{
    Write-Host "== Building RimWorld $sourceVersion from $sourceBranch =="
    & dotnet build $project -c $version
    if ($LASTEXITCODE -ne 0)
    {
        throw "RimWorld $version build failed with exit code $LASTEXITCODE"
    }
}

if (-not $SkipApiSurfaceTest)
{
    & (Join-Path $PSScriptRoot 'Test-ApiSurface.ps1') -Versions $Versions
}
