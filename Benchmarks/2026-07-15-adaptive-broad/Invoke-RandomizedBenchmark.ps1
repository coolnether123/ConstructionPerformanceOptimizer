param(
    [ValidateRange(1, 20)]
    [int]$Blocks = 3,

    [ValidateRange(1, 20)]
    [int]$RunsPerArmPerBlock = 1,

    [ValidateRange(10, 600)]
    [int]$DurationSeconds = 60,

    [int]$Seed = 160715,

    [string]$SaveName = "SGTLMathews Story Colony - SP 12000 Tilled Soil Stress 1.6.4871",

    [string]$RimWorldPath = "D:\Steam Library\steamapps\common\RimWorld\RimWorldCPOBenchmark.exe",

    [ValidateSet("normal", "fast", "superfast", "ultrafast")]
    [string]$GameSpeed = "superfast",

    [string]$OldSafeDll,

    [string]$NewFastDll,

    [string]$DataRoot,

    [string]$ResultRoot
)

$ErrorActionPreference = "Stop"
$runner = Join-Path $PSScriptRoot "Invoke-Variant.ps1"
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($OldSafeDll)) {
    $OldSafeDll = Join-Path $repositoryRoot (
        "Releases\ConstructionPerformanceOptimizer-1.0\ConstructionPerformanceOptimizer" +
        "\1.6\Assemblies\Construction Performance Optimizer.dll")
}
if ([string]::IsNullOrWhiteSpace($NewFastDll)) {
    $NewFastDll = Join-Path $repositoryRoot "1.6\Assemblies\Construction Performance Optimizer.dll"
}
if ([string]::IsNullOrWhiteSpace($ResultRoot)) {
    $ResultRoot = Join-Path $PSScriptRoot ("Randomized-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = Join-Path $PSScriptRoot "Runtime\Data\randomized-clean"
}

$OldSafeDll = [IO.Path]::GetFullPath($OldSafeDll)
$NewFastDll = [IO.Path]::GetFullPath($NewFastDll)
$ResultRoot = [IO.Path]::GetFullPath($ResultRoot)
$DataRoot = [IO.Path]::GetFullPath($DataRoot)

foreach ($requiredPath in @($runner, $RimWorldPath, $OldSafeDll, $NewFastDll)) {
    if (!(Test-Path -LiteralPath $requiredPath)) {
        throw "Required benchmark input not found: $requiredPath"
    }
}

$arms = [ordered]@{
    "baseline" = @{
        Variant = "baseline"
        CandidateDll = ""
        CandidateSha256 = ""
    }
    "old-safe" = @{
        Variant = "current-adaptive"
        CandidateDll = $OldSafeDll
        CandidateSha256 = (Get-FileHash -LiteralPath $OldSafeDll -Algorithm SHA256).Hash
    }
    "new-fast" = @{
        Variant = "current-adaptive"
        CandidateDll = $NewFastDll
        CandidateSha256 = (Get-FileHash -LiteralPath $NewFastDll -Algorithm SHA256).Hash
    }
}

$schedulePath = Join-Path $ResultRoot "schedule.csv"
$manifestPath = Join-Path $ResultRoot "manifest.txt"
New-Item -ItemType Directory -Force -Path $ResultRoot | Out-Null
New-Item -ItemType Directory -Force -Path $DataRoot | Out-Null

if (!(Test-Path -LiteralPath $schedulePath)) {
    $schedule = @()
    $trial = 0
    for ($block = 1; $block -le $Blocks; $block++) {
        $order = @()
        foreach ($arm in $arms.Keys) {
            for ($repeat = 1; $repeat -le $RunsPerArmPerBlock; $repeat++) {
                $order += $arm
            }
        }

        Get-Random -SetSeed ($Seed + $block) | Out-Null
        for ($index = $order.Count - 1; $index -gt 0; $index--) {
            $swap = Get-Random -Minimum 0 -Maximum ($index + 1)
            $temporary = $order[$index]
            $order[$index] = $order[$swap]
            $order[$swap] = $temporary
        }

        for ($sequence = 0; $sequence -lt $order.Count; $sequence++) {
            $trial++
            $arm = $order[$sequence]
            $schedule += [pscustomobject]@{
                Trial = $trial
                Block = $block
                Sequence = $sequence + 1
                Arm = $arm
                CandidateSha256 = $arms[$arm].CandidateSha256
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
        "runsPerArmPerBlock=$RunsPerArmPerBlock"
        "durationSeconds=$DurationSeconds"
        "seed=$Seed"
        "gameSpeed=$GameSpeed"
        "probeMode=performance"
        "rimWorldPath=$RimWorldPath"
        "rimWorldSha256=$((Get-FileHash -LiteralPath $RimWorldPath -Algorithm SHA256).Hash)"
        "oldSafeDll=$OldSafeDll"
        "oldSafeDllSha256=$($arms['old-safe'].CandidateSha256)"
        "newFastDll=$NewFastDll"
        "newFastDllSha256=$($arms['new-fast'].CandidateSha256)"
        "dataRoot=$DataRoot"
    ) | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

$schedule = @(Import-Csv -LiteralPath $schedulePath)
foreach ($entry in $schedule | Where-Object Status -ne "complete" | Sort-Object { [int]$_.Trial }) {
    $arm = $arms[$entry.Arm]
    if (!$arm) {
        throw "Unknown benchmark arm in schedule: $($entry.Arm)"
    }
    if ($arm.CandidateDll) {
        $actualHash = (Get-FileHash -LiteralPath $arm.CandidateDll -Algorithm SHA256).Hash
        if ($actualHash -ne $entry.CandidateSha256) {
            throw "Candidate DLL changed during the benchmark for arm $($entry.Arm). " +
                "Expected $($entry.CandidateSha256), found $actualHash."
        }
    }

    $runningGameProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ExecutablePath -and
                [IO.Path]::GetDirectoryName($_.ExecutablePath) -ieq
                    [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($RimWorldPath)) -and
                $_.Name -like "RimWorld*.exe"
            })
    if ($runningGameProcesses.Count -gt 0) {
        throw "A RimWorld process is already running before trial $($entry.Trial)."
    }

    Write-Host ("Trial {0}/{1}: block {2}, sequence {3}, arm {4}" -f
        $entry.Trial, $schedule.Count, $entry.Block, $entry.Sequence, $entry.Arm)
    $arguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner,
        "-Variant", $arm.Variant,
        "-Runs", "1",
        "-DurationSeconds", $DurationSeconds,
        "-SaveName", $SaveName,
        "-RimWorldPath", $RimWorldPath,
        "-GameSpeed", $GameSpeed,
        "-ProbeMode", "performance",
        "-Instance", ("clean-{0:D3}-{1}" -f [int]$entry.Trial, $entry.Arm),
        "-DataFolder", (Join-Path $DataRoot $entry.Arm)
    )
    if ($arm.CandidateDll) {
        $arguments += @("-CandidateDll", $arm.CandidateDll)
    }

    $output = & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Benchmark trial $($entry.Trial) failed with exit code $LASTEXITCODE."
    }

    $resultLine = @($output | Where-Object { $_ -like "benchmark.results=*" }) | Select-Object -Last 1
    if (!$resultLine) {
        throw "Benchmark trial $($entry.Trial) did not report its result folder."
    }

    $entry.ResultPath = $resultLine.Substring("benchmark.results=".Length)
    $entry.Status = "complete"
    $schedule | Export-Csv -LiteralPath $schedulePath -NoTypeInformation -Encoding UTF8
}

Write-Output "randomizedBenchmark.results=$ResultRoot"
