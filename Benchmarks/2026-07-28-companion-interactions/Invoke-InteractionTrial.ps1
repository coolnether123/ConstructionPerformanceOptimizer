[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('00', '10', '01', '11')]
    [string]$Arm,

    [Parameter(Mandatory = $true)]
    [string[]]$CompanionModIds,

    [string]$ProfileOrder = 'append',

    [string]$RequiredOrder = '',

    [string]$RuntimeChecks = '',

    [string]$ForbiddenLogRegex = '',

    [string]$CompanionHarmonyFilter = '',

    [string]$CompanionHarmonyOwnerToken = '',

    [Parameter(Mandatory = $true)]
    [string]$Instance,

    [Parameter(Mandatory = $true)]
    [string]$DataFolder,

    [Parameter(Mandatory = $true)]
    [string]$ResultRoot,

    [ValidateRange(10, 600)]
    [int]$DurationSeconds = 60,

    [ValidateRange(0, 60)]
    [int]$WarmupSeconds = 5,

    [ValidateSet('normal', 'fast', 'superfast', 'ultrafast')]
    [string]$GameSpeed = 'superfast',

    [switch]$DiagnosticDubs,

    [switch]$AllowConcurrentRimWorld,

    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'

$suiteRoot = $PSScriptRoot
$projectRoot = [IO.Path]::GetFullPath((Join-Path $suiteRoot '..\..'))
$gameRoot =
    'A:\Dev\BenchmarkGames\RimWorld-ConstructionPerformanceOptimizer-1.6'
$modsRoot = Join-Path $gameRoot 'Mods'
$dataRoot = Join-Path $gameRoot 'BenchmarkData'
$sourceFixtureRoot = Join-Path $dataRoot 'SourceFixtures'
$saveName = 'SGTLMathews Story Colony - SP 12000 Tilled Soil Stress 1.6.4871'
$sourceSavePath = Join-Path $sourceFixtureRoot "$saveName.rws"
$baseProfile = Join-Path $sourceFixtureRoot 'ModsConfig.base.xml'
$measureScript = Join-Path $suiteRoot 'Measure-ConstructionProbe-Isolated.ps1'
$compatibilityProfilesRoot = Join-Path $suiteRoot 'CompatibilityProfiles'
$legacyBenchmarkRoot =
    Join-Path $projectRoot 'Benchmarks\2026-07-15-adaptive-broad'
$benchmarkAgentSource =
    Join-Path $legacyBenchmarkRoot 'Runtime\RimWorld Agent - CPO Benchmark'
$benchmarkAgentInstall = Join-Path $modsRoot 'RimWorld Agent - CPO Benchmark'
$candidateInstall =
    Join-Path $modsRoot 'Construction Performance Optimizer - Current Benchmark'
$candidateDll =
    Join-Path $projectRoot '1.6\Assemblies\Construction Performance Optimizer.dll'
$expectedCpoState = if ($Arm -in @('10', '11')) { 'On' } else { 'Off' }
$companionEnabled = $Arm -in @('01', '11')
$expectedCompanionState = if ($companionEnabled) { 'On' } else { 'Off' }
$effectiveForbiddenLogRegex = if ($companionEnabled) {
    $ForbiddenLogRegex
}
else {
    ''
}
$CompanionModIds = @(
    $CompanionModIds -split '[,;]' |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) })

$resolvedDataFolder = [IO.Path]::GetFullPath($DataFolder)
$resolvedResultRoot = [IO.Path]::GetFullPath($ResultRoot)
if (!$resolvedDataFolder.StartsWith(
        $dataRoot.TrimEnd('\') + '\',
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Trial data escaped the isolated data root: $resolvedDataFolder"
}
if (Test-Path -LiteralPath $resolvedDataFolder) {
    throw "Fresh trial data folder already exists: $resolvedDataFolder"
}

New-Item -ItemType Directory -Path (
    Join-Path $resolvedDataFolder 'Config'),
    (Join-Path $resolvedDataFolder 'Saves'),
    $resolvedResultRoot |
    Out-Null
Copy-Item `
    -LiteralPath $sourceSavePath `
    -Destination (Join-Path $resolvedDataFolder "Saves\$saveName.rws")
Copy-Item `
    -LiteralPath $baseProfile `
    -Destination (Join-Path $resolvedDataFolder 'Config\ModsConfig.xml')

$companionCompatibilitySettings = @()
if ($companionEnabled) {
    foreach ($companionModId in $CompanionModIds) {
        $safeModId = $companionModId -replace '[^A-Za-z0-9._-]', '_'
        $compatibilityProfile = Join-Path $compatibilityProfilesRoot (
            "Set-$safeModId.ps1")
        if (Test-Path -LiteralPath $compatibilityProfile) {
            $companionCompatibilitySettings += @(
                & $compatibilityProfile `
                    -ConfigRoot (Join-Path $resolvedDataFolder 'Config'))
        }
    }
}
(Get-Item -LiteralPath (
    Join-Path $resolvedDataFolder 'Config\ModsConfig.xml')).IsReadOnly = $false

# These helpers each have one caller. They are retained as explicit mutation
# boundaries for profile construction and runtime projection; extract them into a
# shared tested module if a second benchmark suite needs either operation.
function Set-InteractionProfile {
    $profilePath = Join-Path $resolvedDataFolder 'Config\ModsConfig.xml'
    [xml]$profile = Get-Content -Raw -LiteralPath $profilePath
    $activeMods = $profile.ModsConfigData.activeMods
    $registry = Import-Csv -LiteralPath (Join-Path $suiteRoot 'CompanionMods.csv')
    $allTreatmentIds = @(
        $registry.additional_mod_ids -split ';' |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) })
    $removeIds = @(
        'coolnether123.betterworktab',
        'coolnether123.constructionqueueoptimizer',
        'coolnether123.constructionperformanceoptimizer',
        'coolnether123.constructionperformanceoptimizer.benchmarkcurrent',
        'coolnether123.constructionperformanceoptimizer.benchmarklegacy',
        'benchmark.cpo.foreignvalidationowner',
        'dubwise.dubsperformanceanalyzer.steam',
        'coolnether123.rimworldagent',
        'coolnether123.rimworldagent.cpobenchmark'
    ) + $allTreatmentIds
    @($activeMods.SelectNodes('li')) |
        Where-Object {
            $removeIds -contains $_.InnerText.ToLowerInvariant()
        } |
        ForEach-Object { [void]$activeMods.RemoveChild($_) }

    if ($companionEnabled) {
        $anchor = $null
        $placement = $ProfileOrder
        if ($ProfileOrder -match '^(before|after):(.+)$') {
            $placement = $Matches[1].ToLowerInvariant()
            $anchorId = $Matches[2]
            $anchor = @($activeMods.SelectNodes('li')) |
                Where-Object { $_.InnerText -ieq $anchorId } |
                Select-Object -First 1
            if (!$anchor) {
                throw "Companion profile anchor is absent: $anchorId"
            }
        }
        elseif ($ProfileOrder -ne 'append') {
            throw "Unknown companion profile order: $ProfileOrder"
        }

        foreach ($id in $CompanionModIds) {
            $node = $profile.CreateElement('li')
            $node.InnerText = $id
            if ($placement -eq 'before') {
                [void]$activeMods.InsertBefore($node, $anchor)
            }
            elseif ($placement -eq 'after') {
                [void]$activeMods.InsertAfter($node, $anchor)
                $anchor = $node
            }
            else {
                [void]$activeMods.AppendChild($node)
            }
        }
    }

    if ($expectedCpoState -eq 'On') {
        $node = $profile.CreateElement('li')
        $node.InnerText = 'coolnether123.constructionperformanceoptimizer'
        [void]$activeMods.AppendChild($node)
    }
    if ($DiagnosticDubs) {
        $node = $profile.CreateElement('li')
        $node.InnerText = 'dubwise.dubsperformanceanalyzer.steam'
        [void]$activeMods.AppendChild($node)
    }
    $agentNode = $profile.CreateElement('li')
    $agentNode.InnerText = 'coolnether123.rimworldagent.cpobenchmark'
    [void]$activeMods.AppendChild($agentNode)

    $ids = @($activeMods.SelectNodes('li') | ForEach-Object {
        $_.InnerText.ToLowerInvariant()
    })
    $duplicates = @(
        $ids |
            Group-Object |
            Where-Object Count -gt 1 |
            ForEach-Object Name)
    if ($duplicates.Count -gt 0) {
        throw "Generated profile contains duplicate IDs: $($duplicates -join ', ')"
    }
    if ($companionEnabled) {
        foreach ($constraint in @(
                $RequiredOrder -split ';' |
                    Where-Object { ![string]::IsNullOrWhiteSpace($_) })) {
            $parts = @($constraint -split '>')
            if ($parts.Count -ne 2) {
                throw "Invalid required-order constraint: $constraint"
            }
            $beforeIndex = [Array]::IndexOf(
                $ids,
                $parts[0].Trim().ToLowerInvariant())
            $afterIndex = [Array]::IndexOf(
                $ids,
                $parts[1].Trim().ToLowerInvariant())
            if ($beforeIndex -lt 0 -or
                $afterIndex -lt 0 -or
                $beforeIndex -ge $afterIndex) {
                throw "Companion load-order constraint failed: $constraint"
            }
        }
    }

    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $writer = [Xml.XmlWriter]::Create($profilePath, $settings)
    try {
        $profile.Save($writer)
    }
    finally {
        $writer.Dispose()
    }
}

function Stage-CpoBenchmarkRuntime {
    New-Item -ItemType Directory -Force -Path $benchmarkAgentInstall | Out-Null
    Copy-Item `
        -Path (Join-Path $benchmarkAgentSource '*') `
        -Destination $benchmarkAgentInstall `
        -Recurse `
        -Force

    New-Item -ItemType Directory -Force -Path (
        Join-Path $candidateInstall 'About'),
        (Join-Path $candidateInstall '1.6\Assemblies') |
        Out-Null
    [xml]$about = Get-Content -Raw -LiteralPath (
        Join-Path $projectRoot 'About\About.xml')
    $about.ModMetaData.name =
        'Construction Performance Optimizer - Current Benchmark'
    $about.ModMetaData.packageId =
        'coolnether123.constructionperformanceoptimizer'
    $about.Save((Join-Path $candidateInstall 'About\About.xml'))
    Copy-Item `
        -LiteralPath (Join-Path $projectRoot 'LoadFolders.xml') `
        -Destination (Join-Path $candidateInstall 'LoadFolders.xml') `
        -Force
    Copy-Item `
        -LiteralPath $candidateDll `
        -Destination (
            Join-Path $candidateInstall (
                '1.6\Assemblies\Construction Performance Optimizer.dll')) `
        -Force
    Copy-Item `
        -LiteralPath (
            Join-Path $projectRoot '1.6\Assemblies\0MultiplayerAPI.dll') `
        -Destination (
            Join-Path $candidateInstall '1.6\Assemblies\0MultiplayerAPI.dll') `
        -Force
}

Stage-CpoBenchmarkRuntime
Set-InteractionProfile

$profilePath = Join-Path $resolvedDataFolder 'Config\ModsConfig.xml'
$installedPackages = @{}
foreach ($modDirectory in Get-ChildItem -LiteralPath $modsRoot -Directory) {
    $aboutPath = Join-Path $modDirectory.FullName 'About\About.xml'
    if (!(Test-Path -LiteralPath $aboutPath)) {
        continue
    }
    try {
        [xml]$metadata = Get-Content -Raw -LiteralPath $aboutPath
        $packageId = ([string]$metadata.ModMetaData.packageId).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }
        if (!$installedPackages.ContainsKey($packageId)) {
            $installedPackages[$packageId] = @()
        }
        $installedPackages[$packageId] += $modDirectory.FullName
    }
    catch {
        throw "Invalid staged About.xml: $aboutPath`n$_"
    }
}

$runtimeCheckEvidence = @()
foreach ($runtimeCheck in @(
        $RuntimeChecks -split ';' |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) })) {
    $parts = @($runtimeCheck -split '\|')
    if ($parts.Count -ne 4) {
        throw "Invalid runtime check: $runtimeCheck"
    }
    $runtimePackageId = $parts[0].Trim().ToLowerInvariant()
    $runtimeRoots = @($installedPackages[$runtimePackageId])
    if ($runtimeRoots.Count -ne 1) {
        throw "Runtime check package $runtimePackageId resolves to $($runtimeRoots.Count) roots."
    }
    $runtimeRoot = $runtimeRoots[0]
    $runtimePath = [IO.Path]::GetFullPath(
        (Join-Path $runtimeRoot $parts[1].Trim()))
    $runtimeRootPrefix = [IO.Path]::GetFullPath($runtimeRoot).TrimEnd('\') + '\'
    if (!$runtimePath.StartsWith(
            $runtimeRootPrefix,
            [StringComparison]::OrdinalIgnoreCase) -or
        !(Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
        throw "Pinned runtime file is absent or escaped its mod root: $runtimePath"
    }
    $assemblyIdentity =
        [Reflection.AssemblyName]::GetAssemblyName($runtimePath).FullName
    $runtimeSha =
        (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash
    if ($assemblyIdentity -ne $parts[2].Trim()) {
        throw "Runtime assembly identity mismatch for $runtimePath`: $assemblyIdentity"
    }
    if ($runtimeSha -ne $parts[3].Trim()) {
        throw "Runtime hash mismatch for $runtimePath`: $runtimeSha"
    }
    $runtimeCheckEvidence +=
        "$runtimePackageId|$($parts[1].Trim())|$assemblyIdentity|$runtimeSha"
}

[xml]$activeProfile = Get-Content -Raw -LiteralPath $profilePath
$activeIds = @(
    $activeProfile.ModsConfigData.activeMods.li |
        ForEach-Object { $_.ToString().ToLowerInvariant() })
$runtimeRows = @()
foreach ($activeId in $activeIds) {
    if ($activeId.StartsWith('ludeon.rimworld')) {
        $runtimeRows += [pscustomobject]@{
            PackageId = $activeId
            Root = '<isolated game Data>'
            AboutSha256 = ''
            AssemblyHashes = ''
        }
        continue
    }
    $roots = @($installedPackages[$activeId])
    if ($roots.Count -ne 1) {
        throw "Active package $activeId resolves to $($roots.Count) staged roots."
    }
    $root = $roots[0]
    $assemblyHashes = @(
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.dll' |
            Sort-Object FullName |
            ForEach-Object {
                '{0}={1}' -f
                $_.FullName.Substring($root.Length + 1),
                (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            })
    $runtimeRows += [pscustomobject]@{
        PackageId = $activeId
        Root = $root
        AboutSha256 = (
            Get-FileHash -LiteralPath (
                Join-Path $root 'About\About.xml') -Algorithm SHA256).Hash
        AssemblyHashes = $assemblyHashes -join ';'
    }
}
$runtimeRows | Export-Csv -LiteralPath (
    Join-Path $resolvedResultRoot 'runtime-packages.csv') `
    -NoTypeInformation `
    -Encoding UTF8

$stagedCandidate = Join-Path $candidateInstall (
    '1.6\Assemblies\Construction Performance Optimizer.dll')
$manifest = @(
    "arm=$Arm"
    "expectedCpoState=$expectedCpoState"
    "companionEnabled=$companionEnabled"
    "companionModIds=$($CompanionModIds -join ';')"
    "profileOrder=$ProfileOrder"
    "requiredOrder=$RequiredOrder"
    "runtimeChecks=$($runtimeCheckEvidence -join ';')"
    "forbiddenLogRegex=$effectiveForbiddenLogRegex"
    "companionHarmonyFilter=$CompanionHarmonyFilter"
    "companionHarmonyOwnerToken=$CompanionHarmonyOwnerToken"
    "diagnosticDubs=$([bool]$DiagnosticDubs)"
    "allowConcurrentRimWorld=$([bool]$AllowConcurrentRimWorld)"
    "dataFolder=$resolvedDataFolder"
    "saveSha256=$((Get-FileHash -LiteralPath (
        Join-Path $resolvedDataFolder "Saves\$saveName.rws") -Algorithm SHA256).Hash)"
    "modsConfigSha256=$((Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash)"
    "candidateDllSha256=$((Get-FileHash -LiteralPath $stagedCandidate -Algorithm SHA256).Hash)"
    "benchmarkAgentDllSha256=$((Get-FileHash -LiteralPath (
        Join-Path $benchmarkAgentInstall (
            '1.6\Assemblies\RimWorldAgentCpoBenchmark.dll')) -Algorithm SHA256).Hash)"
    "companionCompatibilitySettings=$($companionCompatibilitySettings -join ';')"
    "companionCompatibilitySettingsSha256=$(
        @($companionCompatibilitySettings | ForEach-Object {
            (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
        }) -join ';')"
)
$manifest | Set-Content -LiteralPath (
    Join-Path $resolvedResultRoot 'manifest.txt') -Encoding UTF8
Copy-Item -LiteralPath $profilePath -Destination (
    Join-Path $resolvedResultRoot 'ModsConfig.benchmark.xml')

if ($PrepareOnly) {
    Write-Output "benchmark.prepared=$resolvedResultRoot"
    return
}

$probePath = Join-Path $resolvedResultRoot 'run-01-probe.txt'
& $measureScript `
    -SaveName $saveName `
    -ExpectedCpoState $expectedCpoState `
    -ExpectedCompanionState $expectedCompanionState `
    -ExpectedCompanionModIds $CompanionModIds `
    -ForbiddenCompanionLogRegex $effectiveForbiddenLogRegex `
    -CompanionHarmonyFilter $CompanionHarmonyFilter `
    -CompanionHarmonyOwnerToken $CompanionHarmonyOwnerToken `
    -Instance $Instance `
    -ResultPath $probePath `
    -DurationSeconds $DurationSeconds `
    -WarmupSeconds $WarmupSeconds `
    -GameSpeed $GameSpeed `
    -AllowConcurrentRimWorld:$AllowConcurrentRimWorld |
    Out-Null

$playerLog = Join-Path $resolvedDataFolder 'Player.log'
if (!(Test-Path -LiteralPath $playerLog)) {
    throw 'Measured trial did not produce Player.log.'
}
$logText = Get-Content -Raw -LiteralPath $playerLog
$forbiddenCompanionLogMatch = if (
    [string]::IsNullOrWhiteSpace($effectiveForbiddenLogRegex)) {
    $null
}
else {
    [regex]::Match(
        $logText,
        $effectiveForbiddenLogRegex,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
if ($forbiddenCompanionLogMatch -and $forbiddenCompanionLogMatch.Success) {
    throw "Companion runtime log rejection matched: $($forbiddenCompanionLogMatch.Value)"
}
$successDiagnostic =
    '[Construction Performance Optimizer] features: continuation=on, ' +
    'broad validation throttle=on, completion guard=on,'
if ($expectedCpoState -eq 'On' -and
    $logText.IndexOf(
        $successDiagnostic,
        [StringComparison]::Ordinal) -lt 0) {
    throw 'CPO did not report all three expected features enabled.'
}
if ($expectedCpoState -eq 'Off' -and
    $logText.IndexOf(
        '[Construction Performance Optimizer] features:',
        [StringComparison]::Ordinal) -ge 0) {
    throw 'CPO startup diagnostic appeared in an off arm.'
}
Copy-Item -LiteralPath $playerLog -Destination (
    Join-Path $resolvedResultRoot 'run-01-Player.log')
Copy-Item -LiteralPath (Join-Path $resolvedDataFolder 'Config') -Destination (
    Join-Path $resolvedResultRoot 'Config.after') -Recurse

Write-Output "benchmark.results=$resolvedResultRoot"
