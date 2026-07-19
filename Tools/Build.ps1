param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

dotnet run --project (Join-Path $projectRoot 'Tests\ConstructionPerformanceOptimizer.Tests.csproj') -c $Configuration
if ($LASTEXITCODE -ne 0)
{
    throw "Deterministic policy tests failed with exit code $LASTEXITCODE."
}

dotnet build (Join-Path $projectRoot 'Source\ConstructionPerformanceOptimizer.csproj') -c $Configuration
if ($LASTEXITCODE -ne 0)
{
    throw "Mod build failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot $projectRoot
if ($LASTEXITCODE -ne 0)
{
    throw "Package validation failed with exit code $LASTEXITCODE."
}
