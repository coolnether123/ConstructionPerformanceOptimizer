param(
    [ValidateRange(1, 20)]
    [int]$Blocks = 3,

    [ValidateRange(1, 20)]
    [int]$RunsPerVariantPerBlock = 3,

    [ValidateRange(10, 600)]
    [int]$DurationSeconds = 60,

    [int]$Seed = 160715,

    [string]$SaveName = "SGTLMathews Story Colony - SP 12000 Tilled Soil Stress 1.6.4871",

    [string]$ResultRoot
)

$ErrorActionPreference = "Stop"
$variants = @("baseline", "legacy-broad", "current-adaptive")
$runner = Join-Path $PSScriptRoot "Invoke-Variant.ps1"
$currentDll = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "1.6\Assemblies\Construction Performance Optimizer.dll"

if ([string]::IsNullOrWhiteSpace($ResultRoot))
{
    $ResultRoot = Join-Path $PSScriptRoot ("Randomized-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}
$ResultRoot = [IO.Path]::GetFullPath($ResultRoot)
$schedulePath = Join-Path $ResultRoot "schedule.csv"
$manifestPath = Join-Path $ResultRoot "manifest.txt"

New-Item -ItemType Directory -Force -Path $ResultRoot | Out-Null
if (!(Test-Path -LiteralPath $schedulePath))
{
    $schedule = @()
    $trial = 0
    for ($block = 1; $block -le $Blocks; $block++)
    {
        $order = @()
        foreach ($variant in $variants)
        {
            for ($repeat = 1; $repeat -le $RunsPerVariantPerBlock; $repeat++)
            {
                $order += $variant
            }
        }

        Get-Random -SetSeed ($Seed + $block) | Out-Null
        for ($index = $order.Count - 1; $index -gt 0; $index--)
        {
            $swap = Get-Random -Minimum 0 -Maximum ($index + 1)
            $temporary = $order[$index]
            $order[$index] = $order[$swap]
            $order[$swap] = $temporary
        }

        for ($sequence = 0; $sequence -lt $order.Count; $sequence++)
        {
            $trial++
            $schedule += [pscustomobject]@{
                Trial = $trial
                Block = $block
                Sequence = $sequence + 1
                Variant = $order[$sequence]
                Status = "pending"
                ResultPath = ""
            }
        }
    }

    $schedule | Export-Csv -LiteralPath $schedulePath -NoTypeInformation -Encoding UTF8
    @(
        "createdUtc=$([DateTime]::UtcNow.ToString('o'))"
        "saveName=$SaveName"
        "blocks=$Blocks"
        "runsPerVariantPerBlock=$RunsPerVariantPerBlock"
        "durationSeconds=$DurationSeconds"
        "seed=$Seed"
        "currentDllSha256=$((Get-FileHash -LiteralPath $currentDll -Algorithm SHA256).Hash)"
    ) | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

$expectedHash = ((Get-Content -LiteralPath $manifestPath) |
    Where-Object { $_ -like "currentDllSha256=*" } |
    Select-Object -First 1).Split('=', 2)[1]
$schedule = @(Import-Csv -LiteralPath $schedulePath)
foreach ($entry in $schedule | Where-Object Status -ne "complete" | Sort-Object { [int]$_.Trial })
{
    $actualHash = (Get-FileHash -LiteralPath $currentDll -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash)
    {
        throw "Current DLL changed during the randomized benchmark. Expected $expectedHash, found $actualHash."
    }

    Write-Host ("Trial {0}/{1}: block {2}, sequence {3}, variant {4}" -f
        $entry.Trial, $schedule.Count, $entry.Block, $entry.Sequence, $entry.Variant)
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $runner `
        -Variant $entry.Variant `
        -Runs 1 `
        -DurationSeconds $DurationSeconds `
        -SaveName $SaveName
    if ($LASTEXITCODE -ne 0)
    {
        throw "Benchmark trial $($entry.Trial) failed with exit code $LASTEXITCODE."
    }

    $resultLine = @($output | Where-Object { $_ -like "benchmark.results=*" }) | Select-Object -Last 1
    if (!$resultLine)
    {
        throw "Benchmark trial $($entry.Trial) did not report its result folder."
    }

    $entry.ResultPath = $resultLine.Substring("benchmark.results=".Length)
    $entry.Status = "complete"
    $schedule | Export-Csv -LiteralPath $schedulePath -NoTypeInformation -Encoding UTF8
}

Write-Output "randomizedBenchmark.results=$ResultRoot"
