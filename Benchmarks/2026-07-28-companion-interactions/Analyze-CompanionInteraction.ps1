[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResultRoot
)

$ErrorActionPreference = 'Stop'
$ResultRoot = [IO.Path]::GetFullPath($ResultRoot)
$progressPath = Join-Path $ResultRoot 'progress.csv'
$manifestPath = Join-Path $ResultRoot 'manifest.txt'
if (!(Test-Path -LiteralPath $progressPath) -or
    !(Test-Path -LiteralPath $manifestPath)) {
    throw "Interaction result is missing progress or manifest: $ResultRoot"
}

$progress = @(Import-Csv -LiteralPath $progressPath)
$incomplete = @($progress | Where-Object Status -ne 'complete')
if ($incomplete.Count -gt 0) {
    throw "Cannot analyze $($incomplete.Count) incomplete trials."
}

function Get-ProbeMetric {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProbePath,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [ValidateSet('First', 'Last')]
        [string]$Occurrence = 'Last'
    )

    $prefix = "$Key="
    $matchingLines = @(
        Get-Content -LiteralPath $ProbePath |
        Where-Object {
            $_.StartsWith($prefix, [StringComparison]::Ordinal)
        })
    $line = if ($Occurrence -eq 'First') {
        $matchingLines | Select-Object -First 1
    }
    else {
        $matchingLines | Select-Object -Last 1
    }
    if (!$line) {
        throw "Metric $Key not found in $ProbePath"
    }
    [double]::Parse(
        $line.Substring($prefix.Length),
        [Globalization.CultureInfo]::InvariantCulture)
}

function Get-MeasurementForeignObservationCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProbePath
    )

    @(
        Get-Content -LiteralPath $ProbePath |
            Where-Object {
                $_.IndexOf(
                    '|measurement-',
                    [StringComparison]::Ordinal) -ge 0
            }
    ).Count
}

$observations = @()
foreach ($entry in $progress) {
    $probePath = Join-Path $entry.ResultPath 'run-01-probe.txt'
    $blueprintsBefore = Get-ProbeMetric `
        -ProbePath $probePath `
        -Key 'constructionFixture.total' `
        -Occurrence First
    $blueprintsAfter = Get-ProbeMetric `
        -ProbePath $probePath `
        -Key 'constructionFixture.total' `
        -Occurrence Last
    $observations += [pscustomobject]@{
        Trial = [int]$entry.Trial
        Block = [int]$entry.Block
        Sequence = [int]$entry.Sequence
        Arm = $entry.Arm
        CpuMillisecondsPerTick = Get-ProbeMetric `
            -ProbePath $probePath `
            -Key 'performanceProbe.processCpuMillisecondsPerTick'
        WallMillisecondsPerTick = Get-ProbeMetric `
            -ProbePath $probePath `
            -Key 'performanceProbe.wallMillisecondsPerTick'
        TPS = Get-ProbeMetric `
            -ProbePath $probePath `
            -Key 'performanceProbe.tps'
        FPS = Get-ProbeMetric `
            -ProbePath $probePath `
            -Key 'performanceProbe.fps'
        BlueprintsBefore = $blueprintsBefore
        BlueprintsAfter = $blueprintsAfter
        BlueprintsCompleted = $blueprintsBefore - $blueprintsAfter
        MeasurementForeignObservationCount =
            Get-MeasurementForeignObservationCount -ProbePath $probePath
        ResultPath = $entry.ResultPath
    }
}
$excludedBlocks = @(
    $observations |
        Where-Object MeasurementForeignObservationCount -gt 0 |
        Select-Object -ExpandProperty Block -Unique |
        Sort-Object)
foreach ($observation in $observations) {
    $included = $observation.Block -notin $excludedBlocks
    $observation | Add-Member `
        -NotePropertyName Included `
        -NotePropertyValue $included
    $observation | Add-Member `
        -NotePropertyName ExclusionReason `
        -NotePropertyValue $(if ($included) {
            ''
        }
        else {
            'block contains a foreign RimWorld observation during measurement'
        })
}
$observations |
    Sort-Object Trial |
    Export-Csv -LiteralPath (
        Join-Path $ResultRoot 'observations.csv') `
        -NoTypeInformation `
        -Encoding UTF8

$includedObservations = @($observations | Where-Object Included)
if ($includedObservations.Count -lt 4) {
    throw "No complete uncontaminated interaction block remains after excluding blocks: $($excludedBlocks -join ', ')."
}

$blockInteractions = @()
foreach ($block in $includedObservations.Block | Sort-Object -Unique) {
    $blockRows = @($includedObservations | Where-Object Block -eq $block)
    $means = @{}
    foreach ($arm in @('00', '10', '01', '11')) {
        $armRows = @($blockRows | Where-Object Arm -eq $arm)
        if ($armRows.Count -lt 1) {
            throw "Block $block has no observations for arm $arm."
        }
        $means[$arm] = @{
            Cpu = ($armRows.CpuMillisecondsPerTick |
                Measure-Object -Average).Average
            Wall = ($armRows.WallMillisecondsPerTick |
                Measure-Object -Average).Average
            TPS = ($armRows.TPS | Measure-Object -Average).Average
        }
    }
    $blockInteractions += [pscustomobject]@{
        Block = $block
        CpuCpoEffectWithoutCompanion =
            $means['10'].Cpu - $means['00'].Cpu
        CpuCpoEffectWithCompanion =
            $means['11'].Cpu - $means['01'].Cpu
        CpuInteraction =
            ($means['11'].Cpu - $means['01'].Cpu) -
            ($means['10'].Cpu - $means['00'].Cpu)
        CpuRatioOfRatios =
            ($means['11'].Cpu / $means['01'].Cpu) /
            ($means['10'].Cpu / $means['00'].Cpu)
        WallInteraction =
            ($means['11'].Wall - $means['01'].Wall) -
            ($means['10'].Wall - $means['00'].Wall)
        TpsInteraction =
            ($means['11'].TPS - $means['01'].TPS) -
            ($means['10'].TPS - $means['00'].TPS)
    }
}
$blockInteractions | Export-Csv -LiteralPath (
    Join-Path $ResultRoot 'block-interactions.csv') `
    -NoTypeInformation `
    -Encoding UTF8

$armMeans = @{}
foreach ($arm in @('00', '10', '01', '11')) {
    $rows = @($includedObservations | Where-Object Arm -eq $arm)
    $armMeans[$arm] = @{
        Cpu = ($rows.CpuMillisecondsPerTick | Measure-Object -Average).Average
        Wall = ($rows.WallMillisecondsPerTick | Measure-Object -Average).Average
        TPS = ($rows.TPS | Measure-Object -Average).Average
        BlueprintsCompleted =
            ($rows.BlueprintsCompleted | Measure-Object -Average).Average
    }
}
$cpuWithout = $armMeans['10'].Cpu - $armMeans['00'].Cpu
$cpuWith = $armMeans['11'].Cpu - $armMeans['01'].Cpu
$cpuInteraction = $cpuWith - $cpuWithout
$cpuInteractionValues = @($blockInteractions.CpuInteraction)
$interactionMean =
    ($cpuInteractionValues | Measure-Object -Average).Average
$sumSquares = 0.0
foreach ($value in $cpuInteractionValues) {
    $sumSquares += [Math]::Pow($value - $interactionMean, 2)
}
$interactionSd = if ($cpuInteractionValues.Count -gt 1) {
    [Math]::Sqrt($sumSquares / ($cpuInteractionValues.Count - 1))
}
else {
    [double]::NaN
}
$tCritical = switch ($cpuInteractionValues.Count) {
    2 { 12.706 }
    3 { 4.303 }
    4 { 3.182 }
    5 { 2.776 }
    6 { 2.571 }
    7 { 2.447 }
    8 { 2.365 }
    9 { 2.306 }
    default { 1.96 }
}
$margin = if ($cpuInteractionValues.Count -gt 1) {
    $tCritical * $interactionSd / [Math]::Sqrt($cpuInteractionValues.Count)
}
else {
    [double]::NaN
}

$summary = [pscustomobject]@{
    Blocks = $blockInteractions.Count
    Observations = $includedObservations.Count
    TotalObservations = $observations.Count
    ExcludedObservations = $observations.Count - $includedObservations.Count
    ExcludedBlocks = $excludedBlocks -join ';'
    CpuArm00 = $armMeans['00'].Cpu
    CpuArm10 = $armMeans['10'].Cpu
    CpuArm01 = $armMeans['01'].Cpu
    CpuArm11 = $armMeans['11'].Cpu
    BlueprintsCompletedArm00 = $armMeans['00'].BlueprintsCompleted
    BlueprintsCompletedArm10 = $armMeans['10'].BlueprintsCompleted
    BlueprintsCompletedArm01 = $armMeans['01'].BlueprintsCompleted
    BlueprintsCompletedArm11 = $armMeans['11'].BlueprintsCompleted
    CpuCpoEffectWithoutCompanion = $cpuWithout
    CpuCpoEffectWithCompanion = $cpuWith
    CpuBenefitWithoutCompanionPercent =
        100.0 * ($armMeans['00'].Cpu - $armMeans['10'].Cpu) /
        $armMeans['00'].Cpu
    CpuBenefitWithCompanionPercent =
        100.0 * ($armMeans['01'].Cpu - $armMeans['11'].Cpu) /
        $armMeans['01'].Cpu
    CpuInteraction = $cpuInteraction
    CpuInteractionBlockMean = $interactionMean
    CpuInteractionBlockSd = $interactionSd
    CpuInteractionCiLow = $interactionMean - $margin
    CpuInteractionCiHigh = $interactionMean + $margin
    CpuRatioOfRatios =
        ($armMeans['11'].Cpu / $armMeans['01'].Cpu) /
        ($armMeans['10'].Cpu / $armMeans['00'].Cpu)
    WallInteraction =
        ($armMeans['11'].Wall - $armMeans['01'].Wall) -
        ($armMeans['10'].Wall - $armMeans['00'].Wall)
    TpsInteraction =
        ($armMeans['11'].TPS - $armMeans['01'].TPS) -
        ($armMeans['10'].TPS - $armMeans['00'].TPS)
}
$summary | Export-Csv -LiteralPath (
    Join-Path $ResultRoot 'summary.csv') `
    -NoTypeInformation `
    -Encoding UTF8

$manifest = @{}
foreach ($line in Get-Content -LiteralPath $manifestPath) {
    $separator = $line.IndexOf('=')
    if ($separator -gt 0) {
        $manifest[$line.Substring(0, $separator)] =
            $line.Substring($separator + 1)
    }
}
$report = @"
# $($manifest.companion) interaction screening

- Blocks: $($summary.Blocks)
- Included observations: $($summary.Observations) of $($summary.TotalObservations)
- Excluded blocks: $(if ($summary.ExcludedBlocks) { $summary.ExcludedBlocks } else { 'none' })
- Primary endpoint: process CPU milliseconds per simulated tick
- CPO benefit without companion: $($summary.CpuBenefitWithoutCompanionPercent.ToString('F2'))%
- CPO benefit with companion: $($summary.CpuBenefitWithCompanionPercent.ToString('F2'))%
- Difference-in-differences: $($summary.CpuInteraction.ToString('F4')) ms/tick
- Ratio of ratios: $($summary.CpuRatioOfRatios.ToString('F4'))
- 95% interval from block interactions: [$($summary.CpuInteractionCiLow.ToString('F4')), $($summary.CpuInteractionCiHigh.ToString('F4'))]
- Mean blueprints completed by arm (00/10/01/11): $($summary.BlueprintsCompletedArm00.ToString('F1')) / $($summary.BlueprintsCompletedArm10.ToString('F1')) / $($summary.BlueprintsCompletedArm01.ToString('F1')) / $($summary.BlueprintsCompletedArm11.ToString('F1'))

A negative difference-in-differences means the companion increased CPO's CPU-time
savings. A positive value means it reduced those savings. One block is preliminary,
three balanced blocks are screening evidence, and nine balanced blocks are required
for a final estimate.
"@
$report | Set-Content -LiteralPath (
    Join-Path $ResultRoot 'SUMMARY.md') -Encoding UTF8

$summary
