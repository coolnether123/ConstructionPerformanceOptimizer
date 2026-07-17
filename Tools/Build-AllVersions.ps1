param(
    [string[]]$Versions = @('1.6'),
    [switch]$SkipPolicyTests,
    [switch]$SkipApiSurfaceTest
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$project = Join-Path $projectRoot 'Source\ConstructionPipelineOptimizer.csproj'
$unsupportedVersions = @($Versions | Where-Object { $_ -ne '1.6' })
if ($unsupportedVersions.Count -gt 0)
{
    throw (
        "The Dev source tree targets RimWorld 1.6 only. " +
        "Build historical versions from their Support/<version> branches through " +
        "Invoke-SupportCascade.ps1. Requested here: " +
        ($unsupportedVersions -join ', '))
}

if (-not $SkipPolicyTests)
{
    & dotnet run --project (Join-Path $projectRoot 'Tests\ConstructionPipelineOptimizer.Tests.csproj') -c Release
    if ($LASTEXITCODE -ne 0)
    {
        throw "Policy tests failed with exit code $LASTEXITCODE"
    }
}

foreach ($version in $Versions)
{
    Write-Host '== Building RimWorld 1.6 from Dev =='
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
