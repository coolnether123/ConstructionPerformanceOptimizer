param(
    [ValidateSet('1.6')]
    [string]$Version = '1.6'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

dotnet run --project (Join-Path $projectRoot 'Tests\ConstructionPipelineOptimizer.Tests.csproj') -c Release
if ($LASTEXITCODE -ne 0)
{
    throw "Deterministic policy tests failed with exit code $LASTEXITCODE."
}

dotnet build (Join-Path $projectRoot 'Source\ConstructionPipelineOptimizer.csproj') -c $Version
if ($LASTEXITCODE -ne 0)
{
    throw "Mod build failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot 'Test-ApiSurface.ps1') -Versions $Version
if ($LASTEXITCODE -ne 0)
{
    throw "RimWorld $Version API-shape audit failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot 'Validate-Package.ps1') -PackageRoot $projectRoot
if ($LASTEXITCODE -ne 0)
{
    throw "Package validation failed with exit code $LASTEXITCODE."
}
