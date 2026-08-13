param(
    [string]$OutputPath,
    [string]$PlanPath,
    [switch]$Execute,
    [string]$JournalPath,
    [string]$ConfirmPlanSha256,
    [switch]$AllowPush
)

$ErrorActionPreference = 'Stop'

$repository = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$topologyScript = Join-Path $repository 'Tools\Test-CascadeTopology.ps1'
if (-not (Test-Path -LiteralPath $topologyScript -PathType Leaf))
{
    throw "CPO cascade topology contract is missing: $topologyScript"
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $topologyScript `
    -Repository $repository `
    -ManifestPath (Join-Path $repository 'Tools\CascadeManifest.json')
if ($LASTEXITCODE -ne 0)
{
    throw 'CPO cascade topology preflight failed.'
}

$toolingRoot = [Environment]::GetEnvironmentVariable('RWT_CASCADE_TOOLING_ROOT')
if ([string]::IsNullOrWhiteSpace($toolingRoot))
{
    $toolingRoot = 'A:\Dev\RimWorld\Worktrees\RimWorld-Tooling\phase-a'
}
$centralScript = Join-Path $toolingRoot 'tools\Invoke-RimWorldCascade.ps1'
if (-not (Test-Path -LiteralPath $centralScript -PathType Leaf))
{
    throw "Central cascade script is missing: $centralScript"
}

$arguments = @(
    '-Manifest', (Join-Path $repository 'Tools\CascadeManifest.json'),
    '-Repository', $repository)
if (-not [string]::IsNullOrWhiteSpace($OutputPath))
{
    $arguments += @('-OutputPath', $OutputPath)
}
if (-not [string]::IsNullOrWhiteSpace($PlanPath))
{
    $arguments += @('-PlanPath', $PlanPath)
}
if ($Execute)
{
    if ([string]::IsNullOrWhiteSpace($JournalPath) -or
        [string]::IsNullOrWhiteSpace($ConfirmPlanSha256))
    {
        throw 'CPO cascade execution requires JournalPath and ConfirmPlanSha256.'
    }
    $arguments += @(
        '-Execute',
        '-JournalPath', $JournalPath,
        '-ConfirmPlanSha256', $ConfirmPlanSha256)
    if ($AllowPush)
    {
        $arguments += '-AllowPush'
    }
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $centralScript @arguments
exit $LASTEXITCODE
