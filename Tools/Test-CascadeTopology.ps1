param(
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'CascadeManifest.json')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repository = [System.IO.Path]::GetFullPath($Repository)
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json

function Invoke-CpoGit
{
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = @(& git -C $repository @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    [PSCustomObject]@{
        Output = $output
        ExitCode = $exitCode
    }
}

function Get-CpoRefCommit
{
    param([Parameter(Mandatory = $true)][string]$Ref)
    $probe = Invoke-CpoGit @('rev-parse', '--verify', "refs/heads/$Ref")
    if ($probe.ExitCode -ne 0)
    {
        throw "CPO-CASCADE-TOPOLOGY-REF-MISSING: $Ref"
    }
    return ($probe.Output -join "`n").Trim()
}

function Assert-CpoRefAncestor
{
    param(
        [Parameter(Mandatory = $true)][string]$Ancestor,
        [Parameter(Mandatory = $true)][string]$Descendant,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $probe = Invoke-CpoGit @('merge-base', '--is-ancestor', $Ancestor, $Descendant)
    if ($probe.ExitCode -ne 0)
    {
        throw $Message
    }
}

$sourceBranch = [string]$manifest.sourceBranch
$sourceCommit = Get-CpoRefCommit -Ref $sourceBranch
$sourceProject = (
    Invoke-CpoGit @(
        'rev-parse',
        "${sourceCommit}:Source/ConstructionPerformanceOptimizer.csproj")
).Output -join "`n"
$previousRef = $sourceBranch
$checked = 0

foreach ($versionValue in @($manifest.supportVersions))
{
    $version = [string]$versionValue
    $supportRef = "Support/$version"
    $supportCommit = Get-CpoRefCommit -Ref $supportRef

    $ancestorProbe = Invoke-CpoGit @(
        'merge-base', '--is-ancestor', $supportRef, $sourceBranch)
    if ($ancestorProbe.ExitCode -eq 0)
    {
        throw (
            "CPO-CASCADE-TOPOLOGY-SOURCE-ANCESTOR: $supportRef is an " +
            "ancestor of $sourceBranch; merging the source branch would " +
            "replace the historical source tree.")
    }

    $supportProject = (
        Invoke-CpoGit @(
            'rev-parse',
            "${supportCommit}:Source/ConstructionPerformanceOptimizer.csproj")
    ).Output -join "`n"
    if ($supportProject.Trim() -eq $sourceProject.Trim())
    {
        throw (
            "CPO-CASCADE-TOPOLOGY-SOURCE-COLLAPSED: $supportRef uses the " +
            "source branch project tree.")
    }

    foreach ($requiredPath in @(
        'Tools/Build-CascadeVersion.ps1',
        'Tools/CascadeHooks.ps1',
        'Tools/CascadeManifest.json'))
    {
        $probe = Invoke-CpoGit @('cat-file', '-e', "${supportCommit}:$requiredPath")
        if ($probe.ExitCode -ne 0)
        {
            throw (
                "CPO-CASCADE-TOPOLOGY-TOOLS-MISSING: $supportRef lacks " +
                $requiredPath)
        }
    }

    Assert-CpoRefAncestor `
        -Ancestor $previousRef `
        -Descendant $supportRef `
        -Message (
            "CPO-CASCADE-TOPOLOGY-CHAIN: $previousRef must be an ancestor " +
            "of $supportRef so the reviewed merge preserves the target " +
            'historical source tree.')

    $previousRef = $supportRef
    $checked++
}

Write-Output "CPO cascade topology verified: $checked support refs preserve historical source trees and cascade ancestry."
