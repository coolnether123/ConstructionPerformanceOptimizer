param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [ValidateSet('1.0')]
    [string]$Version = '1.0'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

dotnet run --project (Join-Path $projectRoot 'Tests\ConstructionPerformanceOptimizer.Tests.csproj') -c $Configuration
if ($LASTEXITCODE -ne 0)
{
    throw "Deterministic policy tests failed with exit code $LASTEXITCODE."
}

dotnet build (Join-Path $projectRoot 'Source\ConstructionPerformanceOptimizer.csproj') -c $Version
if ($LASTEXITCODE -ne 0)
{
    throw "Mod build failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot 'Test-ApiSurface.ps1') -Versions $Version
if ($LASTEXITCODE -ne 0)
{
    throw "API surface validation failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot $projectRoot -TargetVersion $Version
if ($LASTEXITCODE -ne 0)
{
    throw "Package validation failed with exit code $LASTEXITCODE."
}
