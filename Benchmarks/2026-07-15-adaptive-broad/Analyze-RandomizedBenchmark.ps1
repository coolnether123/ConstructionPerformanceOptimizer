param(
    [Parameter(Mandatory = $true)]
    [string]$ResultRoot
)

$ErrorActionPreference = "Stop"
$ResultRoot = [IO.Path]::GetFullPath($ResultRoot)
$schedulePath = Join-Path $ResultRoot "schedule.csv"
if (!(Test-Path -LiteralPath $schedulePath)) {
    throw "Benchmark schedule not found: $schedulePath"
}

$metricDefinitions = [ordered]@{
    "FPS" = @{ Key = "performanceProbe.fps"; HigherIsBetter = $true }
    "TPS" = @{ Key = "performanceProbe.tps"; HigherIsBetter = $true }
    "FrameMilliseconds" = @{ Key = "performanceProbe.frameMilliseconds"; HigherIsBetter = $false }
    "WallMillisecondsPerTick" = @{ Key = "performanceProbe.wallMillisecondsPerTick"; HigherIsBetter = $false }
    "CpuMillisecondsPerTick" = @{ Key = "performanceProbe.processCpuMillisecondsPerTick"; HigherIsBetter = $false }
}

function Get-ProbeMetric {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProbePath,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $prefix = "$Key="
    $line = Get-Content -LiteralPath $ProbePath |
        Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) } |
        Select-Object -Last 1
    if (!$line) {
        throw "Metric $Key not found in $ProbePath"
    }

    return [double]::Parse(
        $line.Substring($prefix.Length),
        [Globalization.CultureInfo]::InvariantCulture)
}

function Get-SampleStatistics {
    param(
        [Parameter(Mandatory = $true)]
        [double[]]$Values
    )

    $ordered = @($Values | Sort-Object)
    $count = $ordered.Count
    $mean = ($ordered | Measure-Object -Average).Average
    $median = if ($count % 2 -eq 1) {
        $ordered[[int][Math]::Floor($count / 2)]
    }
    else {
        ($ordered[$count / 2 - 1] + $ordered[$count / 2]) / 2
    }
    $sumSquares = 0.0
    foreach ($value in $ordered) {
        $sumSquares += [Math]::Pow($value - $mean, 2)
    }
    $standardDeviation = if ($count -gt 1) {
        [Math]::Sqrt($sumSquares / ($count - 1))
    }
    else {
        0.0
    }

    return @{
        Count = $count
        Mean = $mean
        Median = $median
        StandardDeviation = $standardDeviation
        Minimum = $ordered[0]
        Maximum = $ordered[-1]
    }
}

$observations = @()
foreach ($entry in Import-Csv -LiteralPath $schedulePath) {
    if ($entry.Status -ne "complete") {
        continue
    }

    $probePath = Join-Path $entry.ResultPath "run-01-probe.txt"
    if (!(Test-Path -LiteralPath $probePath)) {
        throw "Completed trial $($entry.Trial) has no probe report: $probePath"
    }

    $observation = [ordered]@{
        Trial = [int]$entry.Trial
        Block = [int]$entry.Block
        Sequence = [int]$entry.Sequence
        Arm = $entry.Arm
        CandidateSha256 = $entry.CandidateSha256
        ResultPath = $entry.ResultPath
    }
    foreach ($metric in $metricDefinitions.GetEnumerator()) {
        $observation[$metric.Key] = Get-ProbeMetric -ProbePath $probePath -Key $metric.Value.Key
    }
    $observations += [pscustomobject]$observation
}
if ($observations.Count -eq 0) {
    throw "No completed benchmark observations were found."
}

$observationsPath = Join-Path $ResultRoot "observations.csv"
$observations | Sort-Object Trial |
    Export-Csv -LiteralPath $observationsPath -NoTypeInformation -Encoding UTF8

$baselineMeans = @{}
foreach ($metric in $metricDefinitions.Keys) {
    $values = @($observations | Where-Object Arm -eq "baseline" | ForEach-Object { [double]$_.$metric })
    if ($values.Count -gt 0) {
        $baselineMeans[$metric] = (Get-SampleStatistics -Values $values).Mean
    }
}

$summary = @()
foreach ($arm in @($observations.Arm | Sort-Object -Unique)) {
    foreach ($metric in $metricDefinitions.GetEnumerator()) {
        $values = @(
            $observations |
                Where-Object Arm -eq $arm |
                ForEach-Object { [double]$_.$($metric.Key) })
        $statistics = Get-SampleStatistics -Values $values
        $change = 0.0
        if ($arm -ne "baseline" -and $baselineMeans.ContainsKey($metric.Key)) {
            $baseline = $baselineMeans[$metric.Key]
            $change = if ($metric.Value.HigherIsBetter) {
                (($statistics.Mean / $baseline) - 1) * 100
            }
            else {
                (($baseline - $statistics.Mean) / $baseline) * 100
            }
        }

        $summary += [pscustomobject]@{
            Arm = $arm
            Metric = $metric.Key
            N = $statistics.Count
            Mean = [Math]::Round($statistics.Mean, 4)
            Median = [Math]::Round($statistics.Median, 4)
            StandardDeviation = [Math]::Round($statistics.StandardDeviation, 4)
            Minimum = [Math]::Round($statistics.Minimum, 4)
            Maximum = [Math]::Round($statistics.Maximum, 4)
            ImprovementVsBaselinePercent = [Math]::Round($change, 2)
        }
    }
}

$summaryPath = Join-Path $ResultRoot "summary.csv"
$summary | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8

$pairedSummary = @()
foreach ($arm in @($observations.Arm | Where-Object { $_ -ne "baseline" } | Sort-Object -Unique)) {
    foreach ($metric in $metricDefinitions.GetEnumerator()) {
        $blockImprovements = @()
        foreach ($block in @($observations.Block | Sort-Object -Unique)) {
            $baselineValues = @(
                $observations |
                    Where-Object { $_.Block -eq $block -and $_.Arm -eq "baseline" } |
                    ForEach-Object { [double]$_.$($metric.Key) })
            $armValues = @(
                $observations |
                    Where-Object { $_.Block -eq $block -and $_.Arm -eq $arm } |
                    ForEach-Object { [double]$_.$($metric.Key) })
            if ($baselineValues.Count -eq 0 -or $armValues.Count -eq 0) {
                continue
            }

            $baselineMean = (Get-SampleStatistics -Values $baselineValues).Mean
            $armMean = (Get-SampleStatistics -Values $armValues).Mean
            $blockImprovements += if ($metric.Value.HigherIsBetter) {
                (($armMean / $baselineMean) - 1) * 100
            }
            else {
                (($baselineMean - $armMean) / $baselineMean) * 100
            }
        }
        if ($blockImprovements.Count -eq 0) {
            continue
        }

        $pairedStatistics = Get-SampleStatistics -Values $blockImprovements
        $pairedSummary += [pscustomobject]@{
            Arm = $arm
            Metric = $metric.Key
            Blocks = $pairedStatistics.Count
            MeanPairedImprovementPercent = [Math]::Round($pairedStatistics.Mean, 2)
            MedianPairedImprovementPercent = [Math]::Round($pairedStatistics.Median, 2)
            StandardDeviation = [Math]::Round($pairedStatistics.StandardDeviation, 2)
            Minimum = [Math]::Round($pairedStatistics.Minimum, 2)
            Maximum = [Math]::Round($pairedStatistics.Maximum, 2)
        }
    }
}
$pairedSummaryPath = Join-Path $ResultRoot "paired-summary.csv"
$pairedSummary | Export-Csv -LiteralPath $pairedSummaryPath -NoTypeInformation -Encoding UTF8

$markdown = @(
    "# Clean randomized construction benchmark"
    ""
    "Positive percentages mean better performance than the no-CPO baseline. " +
        "Time and CPU metrics are expressed as reductions."
    ""
    "| Arm | Metric | n | Mean | Median | SD | Min | Max | Improvement vs baseline |"
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|"
)
foreach ($row in $summary) {
    $markdown += "| $($row.Arm) | $($row.Metric) | $($row.N) | $($row.Mean) | " +
        "$($row.Median) | $($row.StandardDeviation) | $($row.Minimum) | " +
        "$($row.Maximum) | $($row.ImprovementVsBaselinePercent)% |"
}
$markdown += @(
    ""
    "## Paired block improvements"
    ""
    "| Arm | Metric | Blocks | Mean | Median | SD | Min | Max |"
    "|---|---:|---:|---:|---:|---:|---:|---:|"
)
foreach ($row in $pairedSummary) {
    $markdown += "| $($row.Arm) | $($row.Metric) | $($row.Blocks) | " +
        "$($row.MeanPairedImprovementPercent)% | $($row.MedianPairedImprovementPercent)% | " +
        "$($row.StandardDeviation) | $($row.Minimum)% | $($row.Maximum)% |"
}
$markdown += @(
    ""
    "Raw per-trial observations: `observations.csv`."
    "Exact inputs and hashes: `manifest.txt`."
)
$reportPath = Join-Path $ResultRoot "SUMMARY.md"
$markdown | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Output "benchmarkAnalysis.summary=$summaryPath"
Write-Output "benchmarkAnalysis.pairedSummary=$pairedSummaryPath"
Write-Output "benchmarkAnalysis.report=$reportPath"
