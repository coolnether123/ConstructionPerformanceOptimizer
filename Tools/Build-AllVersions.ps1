param(
    [string[]]$Versions = @(
        'Alpha4', '0.13', '0.14', '0.15', '0.16', '0.17', '0.18', '0.19',
        '1.0', '1.1', '1.2', '1.3', '1.4', '1.5', '1.6'),
    [switch]$SkipPolicyTests,
    [switch]$SkipApiSurfaceTest
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$project = Join-Path $projectRoot 'Source\ConstructionPerformanceOptimizer.csproj'

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
    Write-Host "== Building RimWorld $version =="
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
