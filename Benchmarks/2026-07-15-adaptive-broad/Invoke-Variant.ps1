param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("baseline", "legacy-broad", "current-safe", "current-adaptive", "current-conflict")]
    [string]$Variant,

    [ValidateRange(1, 20)]
    [int]$Runs = 3,

    [ValidateRange(5, 600)]
    [int]$DurationSeconds = 30,

    [string]$SaveName = "SGTLMathews Story Colony - SP Performance Frozen Fixture 1.6.4871",

    [string]$BaseProfile = "$env:USERPROFILE\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml.codex-before-cqo-optimized-20260713-132032",

    [string]$RimWorldPath = "D:\Steam Library\steamapps\common\RimWorld\RimWorldWin64.exe",

    [switch]$LeaveRunning
)

$ErrorActionPreference = "Stop"
$benchmarkRoot = $PSScriptRoot
$agentRoot = "A:\Dev\GitHub\Coolnether123\RimWorld-Agent"
$measureScript = Join-Path $agentRoot "Tools\Measure-ConstructionProbe.ps1"
$configPath = "$env:USERPROFILE\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml"
$modsRoot = Join-Path (Split-Path -Parent $RimWorldPath) "Mods"
$legacySource = Join-Path $benchmarkRoot "Variants\LegacyBroad"
$conflictSource = Join-Path $benchmarkRoot "Variants\ForeignValidationOwner"
$legacyInstall = Join-Path $modsRoot "Construction Pipeline Optimizer - Legacy Broad Benchmark"
$conflictInstall = Join-Path $modsRoot "CPO Foreign Validation Owner - Benchmark Only"
$currentInstall = Join-Path $modsRoot "Construction Pipeline Optimizer"
$playerLog = "$env:USERPROFILE\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultRoot = Join-Path $benchmarkRoot "Results\$timestamp-$Variant"
$preRunConfig = Join-Path $resultRoot "ModsConfig.pre-run.xml"

function Set-BenchmarkProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$SelectedVariant
    )

    [xml]$profile = Get-Content -LiteralPath $SourcePath -Raw
    $activeMods = $profile.ModsConfigData.activeMods
    $removeIds = @(
        "coolnether123.betterworktab",
        "coolnether123.constructionqueueoptimizer",
        "coolnether123.constructionpipelineoptimizer",
        "coolnether123.constructionpipelineoptimizer.benchmarklegacy",
        "benchmark.cpo.foreignvalidationowner"
    )

    @($activeMods.SelectNodes("li")) |
        Where-Object { $removeIds -contains $_.InnerText.ToLowerInvariant() } |
        ForEach-Object { [void]$activeMods.RemoveChild($_) }

    foreach ($requiredId in @("dubwise.dubsperformanceanalyzer.steam", "coolnether123.rimworldagent")) {
        $exists = @($activeMods.SelectNodes("li")) | Where-Object { $_.InnerText -ieq $requiredId }
        if (!$exists) {
            $node = $profile.CreateElement("li")
            $node.InnerText = $requiredId
            [void]$activeMods.AppendChild($node)
        }
    }

    $variantPackageIds = switch ($SelectedVariant) {
        "legacy-broad" { "coolnether123.constructionpipelineoptimizer.benchmarklegacy" }
        { $_ -in @("current-safe", "current-adaptive") } { "coolnether123.constructionpipelineoptimizer" }
        "current-conflict" { "benchmark.cpo.foreignvalidationowner"; "coolnether123.constructionpipelineoptimizer" }
        default { @() }
    }
    foreach ($variantPackageId in $variantPackageIds) {
        $node = $profile.CreateElement("li")
        $node.InnerText = $variantPackageId
        [void]$activeMods.AppendChild($node)
    }

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $writer = [System.Xml.XmlWriter]::Create($DestinationPath, $settings)
    try {
        $profile.Save($writer)
    }
    finally {
        $writer.Dispose()
    }
}

function Copy-VariantRuntime {
    New-Item -ItemType Directory -Force -Path $legacyInstall | Out-Null
    Copy-Item -Path (Join-Path $legacySource "*") -Destination $legacyInstall -Recurse -Force
    New-Item -ItemType Directory -Force -Path $conflictInstall | Out-Null
    Copy-Item -Path (Join-Path $conflictSource "*") -Destination $conflictInstall -Recurse -Force

    if (!(Test-Path -LiteralPath (Join-Path $currentInstall "1.6\Assemblies\Construction Pipeline Optimizer.dll"))) {
        throw "Current optimizer runtime is not installed at $currentInstall"
    }
}

if (Get-Process RimWorldWin64 -ErrorAction SilentlyContinue) {
    throw "Close RimWorld before starting a controlled benchmark arm."
}
if ($LeaveRunning -and $Runs -ne 1) {
    throw "-LeaveRunning requires -Runs 1 so later runs cannot collide with the live process."
}
foreach ($requiredPath in @($BaseProfile, $measureScript, $configPath, $legacySource, $conflictSource, $RimWorldPath)) {
    if (!(Test-Path -LiteralPath $requiredPath)) {
        throw "Required benchmark input was not found: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $resultRoot | Out-Null
Copy-Item -LiteralPath $configPath -Destination $preRunConfig
try {
    Copy-VariantRuntime
    Set-BenchmarkProfile -SourcePath $BaseProfile -DestinationPath $configPath -SelectedVariant $Variant
    Copy-Item -LiteralPath $configPath -Destination (Join-Path $resultRoot "ModsConfig.benchmark.xml")

    $manifest = @(
        "variant=$Variant"
        "saveName=$SaveName"
        "durationSeconds=$DurationSeconds"
        "runs=$Runs"
        "rimWorldSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $RimWorldPath).Hash)"
        "saveSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath "$env:USERPROFILE\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Saves\$SaveName.rws").Hash)"
        "legacyDllSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $legacyInstall "1.6\Assemblies\Construction Pipeline Optimizer.dll")).Hash)"
        "currentDllSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $currentInstall "1.6\Assemblies\Construction Pipeline Optimizer.dll")).Hash)"
        "conflictDllSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $conflictInstall "1.6\Assemblies\CPO Foreign Validation Owner.dll")).Hash)"
    )
    $manifest | Set-Content -LiteralPath (Join-Path $resultRoot "manifest.txt") -Encoding UTF8

    for ($run = 1; $run -le $Runs; $run++) {
        $reportPath = Join-Path $resultRoot ("run-{0:D2}-probe.txt" -f $run)
        $measureArguments = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $measureScript,
            "-SaveName", $SaveName,
            "-DurationSeconds", $DurationSeconds,
            "-RimWorldPath", $RimWorldPath,
            "-ResultPath", $reportPath
        )
        if ($LeaveRunning) {
            $measureArguments += "-LeaveRunning"
        }
        & powershell @measureArguments

        if (Test-Path -LiteralPath $playerLog) {
            Copy-Item -LiteralPath $playerLog -Destination (Join-Path $resultRoot ("run-{0:D2}-Player.log" -f $run))
        }
    }
}
finally {
    Copy-Item -LiteralPath $preRunConfig -Destination $configPath -Force
}

Write-Output "benchmark.results=$resultRoot"
