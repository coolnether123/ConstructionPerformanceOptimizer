param(
    [Parameter(Mandatory = $true)][string]$Configuration
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$projectPath = Join-Path $projectRoot 'Source\ConstructionPerformanceOptimizer.csproj'
$policyProjectPath = Join-Path $projectRoot 'Tests\ConstructionPerformanceOptimizer.Tests.csproj'
$apiAuditPath = Join-Path $PSScriptRoot 'Test-ApiSurface.ps1'
$cascadeManifest = Get-Content -Raw -LiteralPath (
    Join-Path $PSScriptRoot 'CascadeManifest.json') | ConvertFrom-Json

if ($Configuration -eq [string]$cascadeManifest.sourceVersion)
{
    & dotnet run --project $policyProjectPath -c Release
    if ($LASTEXITCODE -ne 0)
    {
        throw "CPO policy tests failed with exit code $LASTEXITCODE."
    }
}

& dotnet build $projectPath -c $Configuration
if ($LASTEXITCODE -ne 0)
{
    throw "CPO RimWorld $Configuration build failed with exit code $LASTEXITCODE."
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $apiAuditPath `
    -Versions $Configuration
if ($LASTEXITCODE -ne 0)
{
    throw "CPO RimWorld $Configuration API audit failed with exit code $LASTEXITCODE."
}
