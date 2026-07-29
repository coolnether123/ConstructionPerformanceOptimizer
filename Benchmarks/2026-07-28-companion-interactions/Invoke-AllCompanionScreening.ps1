[CmdletBinding()]
param(
    [ValidateRange(1, 9)]
    [int]$Blocks = 1,

    [ValidateRange(10, 180)]
    [int]$DurationSeconds = 30,

    [ValidateRange(0, 60)]
    [int]$WarmupSeconds = 5,

    [int]$Seed = 280726,

    [switch]$AllowConcurrentRimWorld,

    [string[]]$ExcludeCompanion = @(),

    [string]$ResultRoot
)

$ErrorActionPreference = 'Stop'
$suiteRoot = $PSScriptRoot
$runner = Join-Path $suiteRoot 'Invoke-CompanionInteraction.ps1'
$analyzer = Join-Path $suiteRoot 'Analyze-CompanionInteraction.ps1'
$excludedSlugs = @(
    $ExcludeCompanion -split '[,;]' |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) })
$registry = Import-Csv -LiteralPath (
    Join-Path $suiteRoot 'CompanionMods.csv') |
    Where-Object {
        $_.status -eq 'available' -and
        $_.slug -notin $excludedSlugs
    }

if ([string]::IsNullOrWhiteSpace($ResultRoot)) {
    $ResultRoot = Join-Path $suiteRoot (
        'Results\Screening-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$ResultRoot = [IO.Path]::GetFullPath($ResultRoot)
New-Item -ItemType Directory -Force -Path $ResultRoot | Out-Null

$master = @()
foreach ($companion in $registry) {
    $companionRoot = Join-Path $ResultRoot $companion.slug
    $output = & $runner `
        -Companion $companion.slug `
        -Blocks $Blocks `
        -RunsPerArmPerBlock 1 `
        -DurationSeconds $DurationSeconds `
        -WarmupSeconds $WarmupSeconds `
        -Seed ($Seed + [Array]::IndexOf(@($registry.slug), $companion.slug)) `
        -AllowConcurrentRimWorld:$AllowConcurrentRimWorld `
        -ResultRoot $companionRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Interaction runner failed for $($companion.name)."
    }
    $summary = & $analyzer -ResultRoot $companionRoot
    $master += [pscustomobject]@{
        Slug = $companion.slug
        Name = $companion.name
        ResultRoot = $companionRoot
        Blocks = $summary.Blocks
        CpuBenefitWithoutCompanionPercent =
            $summary.CpuBenefitWithoutCompanionPercent
        CpuBenefitWithCompanionPercent =
            $summary.CpuBenefitWithCompanionPercent
        CpuInteraction = $summary.CpuInteraction
        CpuRatioOfRatios = $summary.CpuRatioOfRatios
    }
    $master | Export-Csv -LiteralPath (
        Join-Path $ResultRoot 'master-summary.csv') `
        -NoTypeInformation `
        -Encoding UTF8
}

Write-Output "screening.results=$ResultRoot"
