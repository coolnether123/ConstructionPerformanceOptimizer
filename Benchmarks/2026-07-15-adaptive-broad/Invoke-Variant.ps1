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

    [string]$Instance = "default",

    [string]$DataFolder,

    [ValidateSet("normal", "fast", "superfast", "ultrafast")]
    [string]$GameSpeed = "ultrafast",

    [ValidateSet("diagnostic", "performance")]
    [string]$ProbeMode = "performance",

    [string]$CandidateDll,

    [switch]$AllowConcurrentGameProcesses,

    [switch]$LeaveRunning
)

$ErrorActionPreference = "Stop"
$benchmarkRoot = $PSScriptRoot
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $benchmarkRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($CandidateDll)) {
    $CandidateDll = Join-Path $projectRoot '1.6\Assemblies\Construction Performance Optimizer.dll'
}
$agentRoot = "A:\Dev\RimWorld\Infrastructure\AgenticHarness\RimWorld-Agent"
$measureScript = Join-Path $agentRoot "Tools\Measure-ConstructionProbe.ps1"
$normalDataFolder = "$env:USERPROFILE\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios"
$sourceSavePath = Join-Path $normalDataFolder "Saves\$SaveName.rws"
if ([string]::IsNullOrWhiteSpace($DataFolder)) {
    $activeDataFolder = $normalDataFolder
}
else {
    $activeDataFolder = [System.IO.Path]::GetFullPath($DataFolder)
    New-Item -ItemType Directory -Force -Path (Join-Path $activeDataFolder 'Config'), (Join-Path $activeDataFolder 'Saves') | Out-Null
    Copy-Item -LiteralPath $sourceSavePath -Destination (Join-Path $activeDataFolder "Saves\$SaveName.rws") -Force
    Copy-Item -LiteralPath $BaseProfile -Destination (Join-Path $activeDataFolder 'Config\ModsConfig.xml') -Force
}
$configPath = Join-Path $activeDataFolder 'Config\ModsConfig.xml'
$modsRoot = Join-Path (Split-Path -Parent $RimWorldPath) "Mods"
$legacySource = Join-Path $benchmarkRoot "Variants\LegacyBroad"
$conflictSource = Join-Path $benchmarkRoot "Variants\ForeignValidationOwner"
$benchmarkAgentSource = Join-Path $benchmarkRoot "Runtime\RimWorld Agent - CPO Benchmark"
$legacyInstall = Join-Path $modsRoot "Construction Performance Optimizer - Legacy Broad Benchmark"
$conflictInstall = Join-Path $modsRoot "CPO Foreign Validation Owner - Benchmark Only"
$benchmarkAgentInstall = Join-Path $modsRoot "RimWorld Agent - CPO Benchmark"
$candidateInstall = Join-Path $modsRoot "Construction Performance Optimizer - Current Benchmark"
$playerLog = Join-Path $activeDataFolder 'Player.log'
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
        "coolnether123.constructionperformanceoptimizer",
        "coolnether123.constructionperformanceoptimizer.benchmarkcurrent",
        "coolnether123.constructionperformanceoptimizer.benchmarklegacy",
        "benchmark.cpo.foreignvalidationowner",
        "dubwise.dubsperformanceanalyzer.steam",
        "coolnether123.rimworldagent",
        "coolnether123.rimworldagent.cpobenchmark"
    )

    @($activeMods.SelectNodes("li")) |
        Where-Object { $removeIds -contains $_.InnerText.ToLowerInvariant() } |
        ForEach-Object { [void]$activeMods.RemoveChild($_) }

    foreach ($requiredId in @("coolnether123.rimworldagent.cpobenchmark")) {
        $exists = @($activeMods.SelectNodes("li")) | Where-Object { $_.InnerText -ieq $requiredId }
        if (!$exists) {
            $node = $profile.CreateElement("li")
            $node.InnerText = $requiredId
            [void]$activeMods.AppendChild($node)
        }
    }

    $variantPackageIds = switch ($SelectedVariant) {
        "legacy-broad" { "coolnether123.constructionperformanceoptimizer.benchmarklegacy" }
        { $_ -in @("current-safe", "current-adaptive") } { "coolnether123.constructionperformanceoptimizer.benchmarkcurrent" }
        "current-conflict" { "benchmark.cpo.foreignvalidationowner"; "coolnether123.constructionperformanceoptimizer.benchmarkcurrent" }
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
    New-Item -ItemType Directory -Force -Path $benchmarkAgentInstall | Out-Null
    $staleBenchmarkAgent = Join-Path $benchmarkAgentInstall '1.6\Assemblies\RimWorld Agent.dll'
    if (Test-Path -LiteralPath $staleBenchmarkAgent) {
        Remove-Item -LiteralPath $staleBenchmarkAgent -Force
    }
    Copy-Item -Path (Join-Path $benchmarkAgentSource "*") -Destination $benchmarkAgentInstall -Recurse -Force

    New-Item -ItemType Directory -Force -Path (Join-Path $candidateInstall 'About'), (Join-Path $candidateInstall '1.6\Assemblies') | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'About\Preview.png') -Destination (Join-Path $candidateInstall 'About\Preview.png') -Force
    [xml]$candidateAbout = Get-Content -LiteralPath (Join-Path $projectRoot 'About\About.xml') -Raw
    $candidateAbout.ModMetaData.name = 'Construction Performance Optimizer - Current Benchmark'
    $candidateAbout.ModMetaData.packageId = 'coolnether123.constructionperformanceoptimizer.benchmarkcurrent'
    $candidateAbout.Save((Join-Path $candidateInstall 'About\About.xml'))
    Copy-Item -LiteralPath (Join-Path $projectRoot 'LoadFolders.xml') -Destination (Join-Path $candidateInstall 'LoadFolders.xml') -Force
    Copy-Item -LiteralPath $CandidateDll -Destination (Join-Path $candidateInstall '1.6\Assemblies\Construction Performance Optimizer.dll') -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot '1.6\Assemblies\0MultiplayerAPI.dll') -Destination (Join-Path $candidateInstall '1.6\Assemblies\0MultiplayerAPI.dll') -Force
}

$benchmarkProcessName = [System.IO.Path]::GetFileNameWithoutExtension($RimWorldPath)
if (Get-Process $benchmarkProcessName -ErrorAction SilentlyContinue) {
    throw "Close the existing $benchmarkProcessName process before starting a controlled benchmark arm."
}
if (!$AllowConcurrentGameProcesses) {
    $gameDirectory = [System.IO.Path]::GetDirectoryName(
        [System.IO.Path]::GetFullPath($RimWorldPath))
    $otherGameProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ExecutablePath -and
                [System.IO.Path]::GetDirectoryName($_.ExecutablePath) -ieq $gameDirectory -and
                $_.Name -like 'RimWorld*.exe'
            })
    if ($otherGameProcesses.Count -gt 0) {
        throw "Close all RimWorld processes before a controlled performance arm, or pass -AllowConcurrentGameProcesses for a functional-only run."
    }
}
if ($LeaveRunning -and $Runs -ne 1) {
    throw "-LeaveRunning requires -Runs 1 so later runs cannot collide with the live process."
}
foreach ($requiredPath in @($BaseProfile, $measureScript, $sourceSavePath, $configPath, $legacySource, $conflictSource, $benchmarkAgentSource, $CandidateDll, $RimWorldPath)) {
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
        "gameSpeed=$GameSpeed"
        "probeMode=$ProbeMode"
        "runs=$Runs"
        "rimWorldSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $RimWorldPath).Hash)"
        "dataFolder=$activeDataFolder"
        "saveSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $activeDataFolder "Saves\$SaveName.rws")).Hash)"
        "legacyDllSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $legacyInstall "1.6\Assemblies\Construction Performance Optimizer.dll")).Hash)"
        "currentDllSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $candidateInstall "1.6\Assemblies\Construction Performance Optimizer.dll")).Hash)"
        "benchmarkAgentDllSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Get-ChildItem (Join-Path $benchmarkAgentInstall "1.6\Assemblies") -Filter '*.dll' | Select-Object -First 1).FullName).Hash)"
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
            "-GameSpeed", $GameSpeed,
            "-ProbeMode", $ProbeMode,
            "-Instance", $Instance,
            "-DataFolder", $activeDataFolder,
            "-RimWorldPath", $RimWorldPath,
            "-ResultPath", $reportPath
        )
        if ($Variant -like "current-*") {
            $measureArguments += "-RequireCpo"
        }
        if ($LeaveRunning) {
            $measureArguments += "-LeaveRunning"
        }
        & powershell @measureArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Construction probe run $run failed with exit code $LASTEXITCODE."
        }

        if (Test-Path -LiteralPath $playerLog) {
            Copy-Item -LiteralPath $playerLog -Destination (Join-Path $resultRoot ("run-{0:D2}-Player.log" -f $run))
        }
    }
}
finally {
    Copy-Item -LiteralPath $preRunConfig -Destination $configPath -Force
}

Write-Output "benchmark.results=$resultRoot"
