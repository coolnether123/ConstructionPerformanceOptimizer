[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Companion,

    [ValidateRange(1, 20)]
    [int]$Blocks = 3,

    [ValidateRange(1, 20)]
    [int]$RunsPerArmPerBlock = 1,

    [ValidateRange(10, 600)]
    [int]$DurationSeconds = 60,

    [ValidateRange(0, 60)]
    [int]$WarmupSeconds = 5,

    [int]$Seed = 280726,

    [ValidateSet('normal', 'fast', 'superfast', 'ultrafast')]
    [string]$GameSpeed = 'superfast',

    [switch]$AllowConcurrentRimWorld,

    [string]$ResultRoot
)

$ErrorActionPreference = 'Stop'

$suiteRoot = $PSScriptRoot
$projectRoot = [IO.Path]::GetFullPath((Join-Path $suiteRoot '..\..'))
$trialRunner = Join-Path $suiteRoot 'Invoke-InteractionTrial.ps1'
$measureRunner = Join-Path $suiteRoot 'Measure-ConstructionProbe-Isolated.ps1'
$isolationGuard = Join-Path $projectRoot 'Tools\Test-CPOBenchmarkIsolation.ps1'
$registryPath = Join-Path $suiteRoot 'CompanionMods.csv'
$gameRoot =
    'A:\Dev\BenchmarkGames\RimWorld-ConstructionPerformanceOptimizer-1.6'
$rimWorldPath = Join-Path $gameRoot 'RimWorldCPOIsolated.exe'
$dataRoot = Join-Path $gameRoot 'BenchmarkData'
$sourceFixtureRoot = Join-Path $dataRoot 'SourceFixtures'
$saveName = 'SGTLMathews Story Colony - SP 12000 Tilled Soil Stress 1.6.4871'
$sourceSavePath = Join-Path $sourceFixtureRoot "$saveName.rws"
$baseProfile = Join-Path $sourceFixtureRoot 'ModsConfig.base.xml'
$candidateDll =
    Join-Path $projectRoot '1.6\Assemblies\Construction Performance Optimizer.dll'
$benchmarkAgentDll = Join-Path $projectRoot (
    'Benchmarks\2026-07-15-adaptive-broad\Runtime\' +
    'RimWorld Agent - CPO Benchmark\1.6\Assemblies\' +
    'RimWorldAgentCpoBenchmark.dll')
$benchmarkAgentSource = [IO.Path]::GetDirectoryName(
    [IO.Path]::GetDirectoryName(
        [IO.Path]::GetDirectoryName($benchmarkAgentDll)))
$compatibilityProfilesRoot = Join-Path $suiteRoot 'CompatibilityProfiles'

function Get-LinesDigest {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Entries
    )

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString(
            $algorithm.ComputeHash(
                [Text.Encoding]::UTF8.GetBytes(
                    ($Entries -join [Environment]::NewLine)))).
            Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-CompatibilityProfilesDigest {
    $entries = @(
        Get-ChildItem -LiteralPath $compatibilityProfilesRoot -File |
            Sort-Object Name |
            ForEach-Object {
                '{0}={1}' -f
                $_.Name,
                (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            })
    Get-LinesDigest -Entries $entries
}

function Get-CpoStagingInputsDigest {
    $agentRoot = [IO.Path]::GetFullPath($benchmarkAgentSource).TrimEnd('\')
    $entries = @(
        Get-ChildItem -LiteralPath $agentRoot -File -Recurse |
            Sort-Object FullName |
            ForEach-Object {
                $relativePath = $_.FullName.Substring(
                    $agentRoot.Length + 1).Replace('\', '/')
                'agent/{0}={1}' -f
                    $relativePath,
                    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        foreach ($relativePath in @(
                'About\About.xml',
                'LoadFolders.xml',
                '1.6\Assemblies\Construction Performance Optimizer.dll',
                '1.6\Assemblies\0MultiplayerAPI.dll')) {
            $inputPath = Join-Path $projectRoot $relativePath
            'candidate/{0}={1}' -f
                $relativePath.Replace('\', '/'),
                (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash
        }
    )
    Get-LinesDigest -Entries $entries
}

$companionRow = @(
    Import-Csv -LiteralPath $registryPath |
        Where-Object { $_.slug -ieq $Companion -or $_.name -ieq $Companion })
if ($companionRow.Count -ne 1) {
    throw "Companion must match exactly one registry row: $Companion"
}
$companionRow = $companionRow[0]
if ($companionRow.status -ne 'available') {
    throw "$($companionRow.name) is not benchmarkable: $($companionRow.special_case)"
}
$companionIds = @(
    $companionRow.additional_mod_ids -split ';' |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) })
$minimumWarmupSeconds = [int]$companionRow.minimum_warmup_seconds
$effectiveWarmupSeconds = [Math]::Max($minimumWarmupSeconds, $WarmupSeconds)

$isolationArguments = @{
    RimWorldPath = $rimWorldPath
    DataRoot = $dataRoot
}
if (!$AllowConcurrentRimWorld) {
    $isolationArguments.PerformanceRun = $true
}
& $isolationGuard @isolationArguments | Out-Null

if ([string]::IsNullOrWhiteSpace($ResultRoot)) {
    $ResultRoot = Join-Path $suiteRoot (
        'Results\{0}-{1}' -f
        (Get-Date -Format 'yyyyMMdd-HHmmss'),
        $companionRow.slug)
}
$ResultRoot = [IO.Path]::GetFullPath($ResultRoot)
$schedulePath = Join-Path $ResultRoot 'schedule.csv'
$progressPath = Join-Path $ResultRoot 'progress.csv'
$manifestPath = Join-Path $ResultRoot 'manifest.txt'
$resultRootHashAlgorithm = [Security.Cryptography.SHA256]::Create()
try {
    $resultRootHash = [BitConverter]::ToString(
        $resultRootHashAlgorithm.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($ResultRoot))).
        Replace('-', '').
        Substring(0, 12)
}
finally {
    $resultRootHashAlgorithm.Dispose()
}
$trialDataRoot = Join-Path $dataRoot ("Trials\CPO-$resultRootHash")

New-Item -ItemType Directory -Force -Path $ResultRoot, $trialDataRoot | Out-Null

$arms = [ordered]@{
    '00' = @{ Variant = 'baseline'; Companion = $false }
    '10' = @{ Variant = 'current-adaptive'; Companion = $false }
    '01' = @{ Variant = 'baseline'; Companion = $true }
    '11' = @{ Variant = 'current-adaptive'; Companion = $true }
}

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
            $schedule += [pscustomobject]@{
                Trial = $trial
                Block = $block
                Sequence = $sequence + 1
                Arm = $order[$sequence]
            }
        }
    }
    $schedule | Export-Csv -LiteralPath $schedulePath -NoTypeInformation -Encoding UTF8
    $schedule |
        Select-Object *, @{Name = 'Status'; Expression = { 'pending' }},
        @{Name = 'ResultPath'; Expression = { '' }} |
        Export-Csv -LiteralPath $progressPath -NoTypeInformation -Encoding UTF8
    @(
        "createdUtc=$([DateTime]::UtcNow.ToString('o'))"
        "companion=$($companionRow.name)"
        "companionSlug=$($companionRow.slug)"
        "companionSourceRevision=$($companionRow.source_revision)"
        "companionRuntimeIdentity=$($companionRow.runtime_identity)"
        "additionalModIds=$($companionIds -join ';')"
        "profileOrder=$($companionRow.profile_order)"
        "requiredOrder=$($companionRow.required_order)"
        "minimumWarmupSeconds=$minimumWarmupSeconds"
        "runtimeChecks=$($companionRow.runtime_checks)"
        "forbiddenLogRegex=$($companionRow.forbidden_log_regex)"
        "companionHarmonyFilter=$($companionRow.harmony_filter)"
        "companionHarmonyOwnerToken=$($companionRow.harmony_owner_token)"
        "blocks=$Blocks"
        "runsPerArmPerBlock=$RunsPerArmPerBlock"
        "durationSeconds=$DurationSeconds"
        "warmupSeconds=$effectiveWarmupSeconds"
        "seed=$Seed"
        "gameSpeed=$GameSpeed"
        "allowConcurrentRimWorld=$([bool]$AllowConcurrentRimWorld)"
        "trialDataRoot=$trialDataRoot"
        "rimWorldPath=$rimWorldPath"
        "rimWorldSha256=$((Get-FileHash -LiteralPath $rimWorldPath -Algorithm SHA256).Hash)"
        "sourceSavePath=$sourceSavePath"
        "sourceSaveSha256=$((Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash)"
        "baseProfile=$baseProfile"
        "baseProfileSha256=$((Get-FileHash -LiteralPath $baseProfile -Algorithm SHA256).Hash)"
        "candidateDll=$candidateDll"
        "candidateDllSha256=$((Get-FileHash -LiteralPath $candidateDll -Algorithm SHA256).Hash)"
        "scheduleSha256=$((Get-FileHash -LiteralPath $schedulePath -Algorithm SHA256).Hash)"
        "registrySha256=$((Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash)"
        "interactionRunnerSha256=$((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash)"
        "trialRunnerSha256=$((Get-FileHash -LiteralPath $trialRunner -Algorithm SHA256).Hash)"
        "measureRunnerSha256=$((Get-FileHash -LiteralPath $measureRunner -Algorithm SHA256).Hash)"
        "benchmarkAgentDllSha256=$((Get-FileHash -LiteralPath $benchmarkAgentDll -Algorithm SHA256).Hash)"
        "compatibilityProfilesSha256=$(Get-CompatibilityProfilesDigest)"
        "cpoStagingInputsSha256=$(Get-CpoStagingInputsDigest)"
    ) | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

$resumeManifest = @{}
foreach ($line in Get-Content -LiteralPath $manifestPath) {
    $separator = $line.IndexOf('=')
    if ($separator -gt 0) {
        $resumeManifest[$line.Substring(0, $separator)] =
            $line.Substring($separator + 1)
    }
}
function Assert-ResumeManifest {
    $resumeExpectations = [ordered]@{
        companionSlug = $companionRow.slug
        blocks = "$Blocks"
        runsPerArmPerBlock = "$RunsPerArmPerBlock"
        durationSeconds = "$DurationSeconds"
        warmupSeconds = "$effectiveWarmupSeconds"
        seed = "$Seed"
        gameSpeed = $GameSpeed
        allowConcurrentRimWorld = "$([bool]$AllowConcurrentRimWorld)"
        rimWorldSha256 =
            (Get-FileHash -LiteralPath $rimWorldPath -Algorithm SHA256).Hash
        sourceSaveSha256 =
            (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
        baseProfileSha256 =
            (Get-FileHash -LiteralPath $baseProfile -Algorithm SHA256).Hash
        candidateDllSha256 =
            (Get-FileHash -LiteralPath $candidateDll -Algorithm SHA256).Hash
        scheduleSha256 =
            (Get-FileHash -LiteralPath $schedulePath -Algorithm SHA256).Hash
        registrySha256 =
            (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash
        interactionRunnerSha256 =
            (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        trialRunnerSha256 =
            (Get-FileHash -LiteralPath $trialRunner -Algorithm SHA256).Hash
        measureRunnerSha256 =
            (Get-FileHash -LiteralPath $measureRunner -Algorithm SHA256).Hash
        benchmarkAgentDllSha256 =
            (Get-FileHash -LiteralPath $benchmarkAgentDll -Algorithm SHA256).Hash
        compatibilityProfilesSha256 = Get-CompatibilityProfilesDigest
        cpoStagingInputsSha256 = Get-CpoStagingInputsDigest
    }
    foreach ($expectation in $resumeExpectations.GetEnumerator()) {
        if (!$resumeManifest.ContainsKey($expectation.Key) -or
            $resumeManifest[$expectation.Key] -ne $expectation.Value) {
            throw "Resume manifest mismatch for $($expectation.Key). Start a new result root."
        }
    }
}
Assert-ResumeManifest

$progress = @(Import-Csv -LiteralPath $progressPath)
$schedule = @(Import-Csv -LiteralPath $schedulePath)
if ($progress.Count -ne $schedule.Count) {
    throw 'Progress row count does not match the locked schedule.'
}
for ($index = 0; $index -lt $schedule.Count; $index++) {
    foreach ($field in @('Trial', 'Block', 'Sequence', 'Arm')) {
        if ($progress[$index].$field -ne $schedule[$index].$field) {
            throw "Progress diverged from the locked schedule at row $($index + 1), field $field."
        }
    }
    $status = $progress[$index].Status
    if ($status -notin @('pending', 'complete')) {
        throw "Invalid progress status at row $($index + 1): $status"
    }
    $expectedResultPath = [IO.Path]::GetFullPath(
        (Join-Path $ResultRoot (
            'trial-{0:D3}-arm-{1}' -f
            [int]$schedule[$index].Trial,
            $schedule[$index].Arm)))
    if ($status -eq 'pending') {
        if (![string]::IsNullOrWhiteSpace($progress[$index].ResultPath)) {
            throw "Pending progress row $($index + 1) has a result path."
        }
        continue
    }
    $actualResultPath = [IO.Path]::GetFullPath($progress[$index].ResultPath)
    if (!$actualResultPath.Equals(
            $expectedResultPath,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Completed progress row $($index + 1) points to the wrong trial result."
    }
    $trialManifestPath = Join-Path $actualResultPath 'manifest.txt'
    if (!(Test-Path -LiteralPath $trialManifestPath)) {
        throw "Completed progress row $($index + 1) has no trial manifest."
    }
    $manifestArm = @(
        Get-Content -LiteralPath $trialManifestPath |
            Where-Object { $_ -like 'arm=*' }) |
        Select-Object -First 1
    if ($manifestArm -ne "arm=$($schedule[$index].Arm)") {
        throw "Completed progress row $($index + 1) has a mismatched trial arm."
    }
}
foreach ($entry in $progress |
    Where-Object Status -ne 'complete' |
    Sort-Object { [int]$_.Trial }) {
    Assert-ResumeManifest
    & $isolationGuard @isolationArguments | Out-Null

    $arm = $arms[$entry.Arm]
    if (!$arm) {
        throw "Unknown interaction arm: $($entry.Arm)"
    }
    $trialName = 'trial-{0:D3}-arm-{1}' -f [int]$entry.Trial, $entry.Arm
    $trialData = Join-Path $trialDataRoot $trialName
    $trialResult = Join-Path $ResultRoot $trialName
    $trialArguments = @{
        Arm = $entry.Arm
        CompanionModIds = $companionIds
        ProfileOrder = $companionRow.profile_order
        RequiredOrder = $companionRow.required_order
        RuntimeChecks = $companionRow.runtime_checks
        ForbiddenLogRegex = $companionRow.forbidden_log_regex
        CompanionHarmonyFilter = $companionRow.harmony_filter
        CompanionHarmonyOwnerToken = $companionRow.harmony_owner_token
        Instance = "$($companionRow.slug)-$trialName"
        DataFolder = $trialData
        ResultRoot = $trialResult
        DurationSeconds = $DurationSeconds
        WarmupSeconds = $effectiveWarmupSeconds
        GameSpeed = $GameSpeed
        AllowConcurrentRimWorld = $AllowConcurrentRimWorld
    }

    Write-Host (
        'Trial {0}/{1}: {2} arm {3}' -f
        $entry.Trial,
        $progress.Count,
        $companionRow.name,
        $entry.Arm)
    $output = & $trialRunner @trialArguments
    $resultLine = @(
        $output |
            Where-Object { $_ -like 'benchmark.results=*' }) |
        Select-Object -Last 1
    if (!$resultLine) {
        throw "Trial $($entry.Trial) did not report a result path."
    }

    $entry.ResultPath = $resultLine.Substring('benchmark.results='.Length)
    $entry.Status = 'complete'
    $progress | Export-Csv -LiteralPath $progressPath -NoTypeInformation -Encoding UTF8
}

Write-Output "interaction.results=$ResultRoot"
