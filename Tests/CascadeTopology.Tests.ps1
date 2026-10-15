$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureRoot = Join-Path 'H:\Dev\Temp' (
    'cpo-cascade-topology-contract-' + [Guid]::NewGuid().ToString('N'))
$toolsRoot = Join-Path $fixtureRoot 'Tools'
New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null

function Invoke-FixtureGit
{
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & git -C $fixtureRoot @Arguments
    if ($LASTEXITCODE -ne 0)
    {
        throw "Fixture git command failed: git $($Arguments -join ' ')"
    }
}

function Write-FixtureFile
{
    param([string]$RelativePath, [string]$Content)
    $path = Join-Path $fixtureRoot $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [System.IO.File]::WriteAllText($path, $Content)
}

$manifest = @'
{
  "schemaVersion": 1,
  "id": "cpo-topology-contract-fixture",
  "strategy": "support-branches",
  "allowRealExecution": true,
  "sourceBranch": "main",
  "sourceVersion": "1.6",
  "supportVersions": ["1.5", "1.4", "1.3", "1.2", "1.1", "1.0"],
  "payloadRoots": ["1.6/Assemblies", "1.5/Assemblies", "1.4/Assemblies", "1.3/Assemblies", "1.2/Assemblies", "1.1/Assemblies", "1.0/Assemblies"],
  "copyBackPaths": [],
  "build": {
    "project": "Tools/Build-CascadeVersion.ps1",
    "configurationTemplate": "{version}",
    "expectedAssembly": "fixture.dll"
  },
  "hooks": [],
  "additionalActions": [],
  "copyBack": false,
  "push": false,
  "restoreSource": false
}
'@

Write-FixtureFile 'Tools/CascadeManifest.json' $manifest
Copy-Item -LiteralPath (Join-Path $projectRoot 'Tools\Invoke-SupportCascade.ps1') -Destination (Join-Path $toolsRoot 'Invoke-SupportCascade.ps1')
Copy-Item -LiteralPath (Join-Path $projectRoot 'Tools\Test-CascadeTopology.ps1') -Destination (Join-Path $toolsRoot 'Test-CascadeTopology.ps1')
Write-FixtureFile 'Tools/Build-CascadeVersion.ps1' 'param([string]$Configuration)'
Write-FixtureFile 'Tools/CascadeHooks.ps1' 'param([string]$Phase, [string]$Version)'
Write-FixtureFile 'Source/ConstructionPerformanceOptimizer.csproj' 'fixture-main-1.6'
Write-FixtureFile '1.6/Assemblies/fixture.dll' 'fixture-payload'

Invoke-FixtureGit init -b main
Invoke-FixtureGit config user.name 'CPO topology contract'
Invoke-FixtureGit config user.email 'cpo-topology-contract@example.invalid'
Invoke-FixtureGit add -- .
Invoke-FixtureGit commit -m 'fixture main'

$previous = 'main'
foreach ($version in @('1.5', '1.4', '1.3', '1.2', '1.1', '1.0'))
{
    Invoke-FixtureGit checkout -b "Support/$version" $previous
    Write-FixtureFile 'Source/ConstructionPerformanceOptimizer.csproj' "fixture-support-$version"
    Write-FixtureFile "$version/Assemblies/fixture.dll" "fixture-payload-$version"
    Invoke-FixtureGit add -- .
    Invoke-FixtureGit commit -m "fixture Support/$version"
    $previous = "Support/$version"
}
Invoke-FixtureGit checkout main

$env:RWT_CASCADE_TOOLING_ROOT = 'H:\Dev\RimWorld\Worktrees\RimWorld-Tooling\phase-a'
$safePlan = Join-Path $fixtureRoot 'safe-plan.json'
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $toolsRoot 'Invoke-SupportCascade.ps1') `
    -OutputPath $safePlan
if ($LASTEXITCODE -ne 0)
{
    throw 'CPO cascade topology contract rejected a safe fixture.'
}
$safePlanInfo = Get-Content -Raw -LiteralPath $safePlan | ConvertFrom-Json
if (-not [bool]$safePlanInfo.Executable)
{
    throw 'CPO cascade topology contract produced a blocked safe plan.'
}

Invoke-FixtureGit branch -f Support/1.5 main
$unsafePlan = Join-Path $fixtureRoot 'unsafe-plan.json'
$unsafeStdout = Join-Path $fixtureRoot 'unsafe.stdout.log'
$unsafeStderr = Join-Path $fixtureRoot 'unsafe.stderr.log'
$unsafeProcess = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Join-Path $toolsRoot 'Invoke-SupportCascade.ps1'),
        '-OutputPath',
        $unsafePlan) `
    -WorkingDirectory $fixtureRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $unsafeStdout `
    -RedirectStandardError $unsafeStderr `
    -PassThru `
    -Wait
$unsafeOutput = (
    (Get-Content -Raw -LiteralPath $unsafeStdout -ErrorAction SilentlyContinue) +
    (Get-Content -Raw -LiteralPath $unsafeStderr -ErrorAction SilentlyContinue))
if ($unsafeProcess.ExitCode -eq 0 -or $unsafeOutput -notmatch 'CPO-CASCADE-TOPOLOGY-SOURCE-ANCESTOR')
{
    throw 'CPO cascade topology contract failed to reject a source-ancestor support ref.'
}

Write-Output 'CPO cascade topology contract tests passed: safe planner accepted; source-ancestor ref rejected.'
