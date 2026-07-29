[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SaveName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('On', 'Off')]
    [string]$ExpectedCpoState,

    [Parameter(Mandatory = $true)]
    [ValidateSet('On', 'Off')]
    [string]$ExpectedCompanionState,

    [Parameter(Mandatory = $true)]
    [string[]]$ExpectedCompanionModIds,

    [string]$ForbiddenCompanionLogRegex = '',

    [string]$CompanionHarmonyFilter = '',

    [string]$CompanionHarmonyOwnerToken = '',

    [Parameter(Mandatory = $true)]
    [string]$Instance,

    [Parameter(Mandatory = $true)]
    [string]$ResultPath,

    [ValidateRange(10, 600)]
    [int]$DurationSeconds = 60,

    [ValidateRange(0, 60)]
    [int]$WarmupSeconds = 5,

    [ValidateSet('normal', 'fast', 'superfast', 'ultrafast')]
    [string]$GameSpeed = 'superfast',

    [switch]$AllowConcurrentRimWorld,

    [int]$ReadyTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

$gameRoot =
    'A:\Dev\BenchmarkGames\RimWorld-ConstructionPerformanceOptimizer-1.6'
$rimWorldPath = Join-Path $gameRoot 'RimWorldCPOIsolated.exe'
$canonicalPath = Join-Path $gameRoot 'RimWorldWin64.exe'
$dataRoot = Join-Path $gameRoot 'BenchmarkData'

$requiredCpoPatchPatterns = [ordered]@{
    'PlaceNoCostFrame continuation' =
        '(?ms)^RimWorld\.JobDriver_PlaceNoCostFrame\.MakeNewToils\r?\n' +
        '[^\r\n]*coolnether123\.constructionperformanceoptimizer::' +
        'ConstructionPerformanceOptimizer\.Patches\.' +
        'PlaceNoCostFrameContinuationPatch\.Postfix'
    'FinishFrame validation throttle' =
        '(?ms)^RimWorld\.JobDriver_ConstructFinishFrame\+<>' +
        'c__DisplayClass8_0\.<MakeNewToils>b__3\r?\n' +
        '[^\r\n]*coolnether123\.constructionperformanceoptimizer::' +
        'ConstructionPerformanceOptimizer\.Patches\.' +
        'FinishFrameValidationThrottlePatch\.Transpiler'
    'FinishFrame completion guard' =
        '(?ms)^RimWorld\.JobDriver_ConstructFinishFrame\+<>' +
        'c__DisplayClass8_0\.<MakeNewToils>b__1\r?\n' +
        '[^\r\n]*coolnether123\.constructionperformanceoptimizer::' +
        'ConstructionPerformanceOptimizer\.Patches\.' +
        'FinishFrameCompletionGuardPatch\.Transpiler'
}

function Assert-CpoHarmonyState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Report,

        [Parameter(Mandatory = $true)]
        [string]$Checkpoint
    )

    $hasAnyCpoOwner = $Report.IndexOf(
        'coolnether123.constructionperformanceoptimizer::',
        [StringComparison]::OrdinalIgnoreCase) -ge 0
    if ($ExpectedCpoState -eq 'Off' -and $hasAnyCpoOwner) {
        throw "A CPO Harmony owner was unexpectedly present at $Checkpoint.`n$Report"
    }

    foreach ($entry in $requiredCpoPatchPatterns.GetEnumerator()) {
        $present = $Report -match $entry.Value
        if ($ExpectedCpoState -eq 'On' -and !$present) {
            throw "CPO $($entry.Key) was absent at $Checkpoint.`n$Report"
        }
        if ($ExpectedCpoState -eq 'Off' -and $present) {
            throw "CPO $($entry.Key) was unexpectedly present at $Checkpoint.`n$Report"
        }
    }
}

# The trial runner writes the exact data path beside the result before invoking
# this script. Resolve it from the manifest instead of accepting an arbitrary
# savedata argument.
$trialManifest = Join-Path (Split-Path -Parent $ResultPath) 'manifest.txt'
if (!(Test-Path -LiteralPath $trialManifest)) {
    throw "Trial manifest not found: $trialManifest"
}
$dataLine = Get-Content -LiteralPath $trialManifest |
    Where-Object { $_ -like 'dataFolder=*' } |
    Select-Object -Last 1
if (!$dataLine) {
    throw 'Trial manifest does not declare dataFolder.'
}
$dataFolder = [IO.Path]::GetFullPath($dataLine.Substring('dataFolder='.Length))
$dataPrefix = $dataRoot.TrimEnd('\') + '\'
if (!$dataFolder.StartsWith(
        $dataPrefix,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Trial data folder escapes the isolated data root: $dataFolder"
}
$playerLog = Join-Path $dataFolder 'Player.log'

$safeInstance = ($Instance -replace '[\\/:*?"<>|]', '_').Trim()
if ([string]::IsNullOrWhiteSpace($safeInstance)) {
    throw 'A non-empty benchmark instance ID is required.'
}
$bridge = Join-Path $env:TEMP "RimWorldAgent\1.6\$safeInstance"
$commandPath = Join-Path $bridge 'command.txt'
$agentResultPath = Join-Path $bridge 'last-result.txt'
$readyPath = Join-Path $bridge 'ready.txt'
$sender =
    'A:\Dev\GitHub\Coolnether123\RimWorld-Agent\Tools\Send-RimWorldAgentCommand.ps1'
$authorizedHash =
    (Get-FileHash -LiteralPath $rimWorldPath -Algorithm SHA256).Hash
if ((Get-FileHash -LiteralPath $canonicalPath -Algorithm SHA256).Hash -cne
    $authorizedHash) {
    throw 'The isolated canonical restart executable hash changed.'
}

function Wait-ForCondition {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Condition,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) {
            return
        }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    throw $FailureMessage
}

function Invoke-AgentCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPrefix,

        [int]$TimeoutSeconds = 20
    )

    $sentAt = Get-Date
    & powershell `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $sender `
        -Version 1.6 `
        -Instance $safeInstance `
        -Command $Command |
        Out-Null
    Wait-ForCondition `
        -TimeoutSeconds $TimeoutSeconds `
        -FailureMessage "Agent command timed out: $Command" `
        -Condition {
            if ((Test-Path $commandPath) -or !(Test-Path $agentResultPath)) {
                return $false
            }
            $result = Get-Item $agentResultPath
            if ($result.LastWriteTime -lt $sentAt) {
                return $false
            }
            return (Get-Content -Raw $agentResultPath).StartsWith(
                $ExpectedPrefix,
                [StringComparison]::Ordinal)
        }
    Get-Content -Raw $agentResultPath
}

function Wait-ForMapReadyAfter {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$RequestedUtc
    )

    Wait-ForCondition `
        -TimeoutSeconds 180 `
        -FailureMessage 'Loaded save did not reach a map-ready state.' `
        -Condition {
            if (!(Test-Path -LiteralPath (
                    Join-Path $bridge 'lifecycle-journal.log'))) {
                return $false
            }
            $mapReadyLines = @(
                Get-Content -LiteralPath (
                    Join-Path $bridge 'lifecycle-journal.log') |
                    Where-Object { $_ -match ' lifecycle=MapReady ' })
            if ($mapReadyLines.Count -lt 1) {
                return $false
            }
            $timestampText = $mapReadyLines[-1].Split(' ')[0]
            $mapReadyUtc = [datetime]::Parse(
                $timestampText,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind)
            $mapReadyUtc -gt $RequestedUtc
        }
}

function Get-ForeignRimWorldProcesses {
    $allGameProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'RimWorld*.exe' })
    @(
        $allGameProcesses |
            Where-Object {
                !$_.ExecutablePath -or
                ![IO.Path]::GetDirectoryName($_.ExecutablePath).Equals(
                    $gameRoot,
                    [StringComparison]::OrdinalIgnoreCase)
            })
}

$foreignObservations =
    [System.Collections.Generic.List[pscustomobject]]::new()

function Add-ForeignObservations {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Processes,

        [Parameter(Mandatory = $true)]
        [string]$Checkpoint
    )

    foreach ($foreignProcess in $Processes) {
        $foreignObservations.Add([pscustomobject]@{
                TimestampUtc = [datetime]::UtcNow.ToString('o')
                Checkpoint = $Checkpoint
                ProcessId = $foreignProcess.ProcessId
                Name = $foreignProcess.Name
                ExecutablePath = $foreignProcess.ExecutablePath
            })
    }
    if ($Processes.Count -gt 0 -and !$AllowConcurrentRimWorld) {
        $details = $Processes |
            ForEach-Object {
                "$($_.ProcessId):$($_.Name):$($_.ExecutablePath)"
            }
        throw "Another RimWorld process contaminated the trial: $($details -join '; ')"
    }
}

function Observe-ForeignRimWorldProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Checkpoint
    )

    $foreignProcesses = @(
        Get-Process -Name 'RimWorld*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                $executablePath = $_.Path
                if (!$executablePath -or
                    ![IO.Path]::GetDirectoryName($executablePath).Equals(
                        $gameRoot,
                        [StringComparison]::OrdinalIgnoreCase)) {
                    [pscustomobject]@{
                        ProcessId = $_.Id
                        Name = $_.Name + '.exe'
                        ExecutablePath = $executablePath
                    }
                }
            })
    Add-ForeignObservations `
        -Processes $foreignProcesses `
        -Checkpoint $Checkpoint
}

function Assert-IsolatedProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Checkpoint
    )

    $foreignProcesses = @(Get-ForeignRimWorldProcesses)
    Add-ForeignObservations `
        -Processes $foreignProcesses `
        -Checkpoint $Checkpoint
    $allGameProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'RimWorld*.exe' })
    $processes = @(
        $allGameProcesses |
            Where-Object {
                $_.ExecutablePath -and
                [IO.Path]::GetDirectoryName($_.ExecutablePath).Equals(
                    $gameRoot,
                    [StringComparison]::OrdinalIgnoreCase) -and
                $_.Name -like 'RimWorld*.exe'
            })
    if ($processes.Count -lt 1) {
        throw 'No isolated RimWorld process is running.'
    }
    foreach ($gameProcess in $processes) {
        $path = [IO.Path]::GetFullPath($gameProcess.ExecutablePath)
        if (!$path.Equals($rimWorldPath, [StringComparison]::OrdinalIgnoreCase) -and
            !$path.Equals($canonicalPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unexpected player inside isolated game root: $path"
        }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne
            $authorizedHash) {
            throw "Running player hash changed for PID $($gameProcess.ProcessId)."
        }
        $commandLine = [string]$gameProcess.CommandLine
        $dataPattern =
            '(?i)(?:^|\s)-savedatafolder(?:=|\s+)"?' +
            [regex]::Escape($dataFolder) +
            '"?(?:\s|$)'
        $instancePattern =
            '(?i)(?:^|\s)-rw-agent-id(?:=|\s+)"?' +
            [regex]::Escape($safeInstance) +
            '"?(?:\s|$)'
        if ($commandLine -notmatch $dataPattern -or
            $commandLine -notmatch '(?i)(?:^|\s)-rw-agent(?:\s|$)' -or
            $commandLine -notmatch $instancePattern) {
            throw "PID $($gameProcess.ProcessId) lost its isolation or agent arguments."
        }
    }
}

$process = $null
try {
    $launchArguments = @(
        '-disableSteam',
        '-rw-agent',
        '-rw-agent-id', $safeInstance,
        '-screen-fullscreen', '0',
        '-screen-width', '1920',
        '-screen-height', '1080',
        '-logFile', (Join-Path $dataFolder 'Player.log'),
        "-savedatafolder=$dataFolder")
    $process = Start-Process `
        -FilePath $rimWorldPath `
        -WorkingDirectory $gameRoot `
        -ArgumentList $launchArguments `
        -PassThru

    $processStart = $process.StartTime
    Wait-ForCondition `
        -TimeoutSeconds $ReadyTimeoutSeconds `
        -FailureMessage 'RimWorld Agent did not become ready.' `
        -Condition {
            (Test-Path $readyPath) -and
            (Get-Item $readyPath).LastWriteTime -gt $processStart
        }
    Assert-IsolatedProcesses -Checkpoint 'agent-ready'

    $loadRequestedUtc = [datetime]::UtcNow
    Invoke-AgentCommand `
        -Command "dev-run load-save $SaveName --pause-after-load" `
        -ExpectedPrefix 'load complete:' `
        -TimeoutSeconds 150 |
        Out-Null
    Wait-ForMapReadyAfter -RequestedUtc $loadRequestedUtc

    if ($WarmupSeconds -gt 0) {
        Invoke-AgentCommand `
            -Command "dev-run set-speed $GameSpeed" `
            -ExpectedPrefix (
                'timeSpeed={0}{1}' -f
                [char]::ToUpperInvariant($GameSpeed[0]),
                $GameSpeed.Substring(1).ToLowerInvariant()) |
            Out-Null
        Start-Sleep -Seconds $WarmupSeconds
        Invoke-AgentCommand `
            -Command 'dev-run set-speed paused' `
            -ExpectedPrefix 'timeSpeed=Paused' |
            Out-Null
        $reloadRequestedUtc = [datetime]::UtcNow
        Invoke-AgentCommand `
            -Command "dev-run load-save $SaveName --pause-after-load" `
            -ExpectedPrefix 'load complete:' `
            -TimeoutSeconds 150 |
            Out-Null
        Wait-ForMapReadyAfter -RequestedUtc $reloadRequestedUtc
    }

    $fixtureBefore = Invoke-AgentCommand `
        -Command 'dev-run construction-fixture report 11004 GT_SoilTilled' `
        -ExpectedPrefix 'constructionFixture.terrain=GT_SoilTilled'
    if ($fixtureBefore -notmatch '(?m)^constructionFixture.total=11004\r?$') {
        throw "The frozen fixture does not load with exactly 11,004 target blueprints.`n$fixtureBefore"
    }

    $logText = Get-Content -Raw -LiteralPath $playerLog
    if (![string]::IsNullOrWhiteSpace($ForbiddenCompanionLogRegex)) {
        $forbiddenMatch = [regex]::Match(
            $logText,
            $ForbiddenCompanionLogRegex,
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($forbiddenMatch.Success) {
            throw "Companion runtime log rejection matched before timing: $($forbiddenMatch.Value)"
        }
    }
    $modListMatches = [regex]::Matches(
        $logText,
        '(?ms)^Loading game from file .*? with mods:\r?\n' +
            '(?<mods>(?:  - [^\r\n]+\r?\n)+)')
    if ($modListMatches.Count -eq 0) {
        throw 'Player.log did not contain the active mod list used to load the fixture.'
    }
    $activeModIds = @(
        $modListMatches[$modListMatches.Count - 1].Groups['mods'].Value -split
            '\r?\n' |
            Where-Object { $_ -match '^  - (.+)$' } |
            ForEach-Object { $Matches[1].Trim().ToLowerInvariant() })
    foreach ($expectedCompanionId in $ExpectedCompanionModIds) {
        $present = $activeModIds -contains $expectedCompanionId.ToLowerInvariant()
        if ($ExpectedCompanionState -eq 'On' -and !$present) {
            throw "Companion package was expected on but not loaded: $expectedCompanionId"
        }
        if ($ExpectedCompanionState -eq 'Off' -and $present) {
            throw "Companion package was expected off but loaded: $expectedCompanionId"
        }
    }
    $cpoPackageId = 'coolnether123.constructionperformanceoptimizer'
    $cpoPackagePresent = $activeModIds -contains $cpoPackageId
    if ($ExpectedCpoState -eq 'On' -and !$cpoPackagePresent) {
        throw "CPO package was expected on but not loaded: $cpoPackageId"
    }
    if ($ExpectedCpoState -eq 'Off' -and $cpoPackagePresent) {
        throw "CPO package was expected off but loaded: $cpoPackageId"
    }

    $companionHarmonyBefore = ''
    if (![string]::IsNullOrWhiteSpace($CompanionHarmonyFilter) -or
        ![string]::IsNullOrWhiteSpace($CompanionHarmonyOwnerToken)) {
        if ($CompanionHarmonyFilter -notmatch '^[A-Za-z0-9._-]+$' -or
            [string]::IsNullOrWhiteSpace($CompanionHarmonyOwnerToken)) {
            throw 'Companion Harmony verification metadata is incomplete or invalid.'
        }
        $companionHarmonyBefore = Invoke-AgentCommand `
            -Command (
                "harmony-patches filter=$CompanionHarmonyFilter limit=100") `
            -ExpectedPrefix 'patched methods shown='
        $hasCompanionOwner = $companionHarmonyBefore.IndexOf(
            $CompanionHarmonyOwnerToken,
            [StringComparison]::OrdinalIgnoreCase) -ge 0
        if ($ExpectedCompanionState -eq 'On' -and !$hasCompanionOwner) {
            throw "Companion Harmony owner was absent before timing.`n$companionHarmonyBefore"
        }
        if ($ExpectedCompanionState -eq 'Off' -and $hasCompanionOwner) {
            throw "Companion Harmony owner was present in an off arm.`n$companionHarmonyBefore"
        }
    }

    $cpoHarmonyBefore = Invoke-AgentCommand `
        -Command 'harmony-patches filter=constructionperformanceoptimizer limit=20' `
        -ExpectedPrefix 'patched methods shown='
    Assert-CpoHarmonyState -Report $cpoHarmonyBefore -Checkpoint 'before measurement'

    Invoke-AgentCommand `
        -Command "dev-run set-speed $GameSpeed" `
        -ExpectedPrefix (
            'timeSpeed={0}{1}' -f
            [char]::ToUpperInvariant($GameSpeed[0]),
            $GameSpeed.Substring(1).ToLowerInvariant()) |
        Out-Null
    Invoke-AgentCommand `
        -Command 'dev-run performance-probe start' `
        -ExpectedPrefix 'performanceProbe.running=true' |
        Out-Null

    Assert-IsolatedProcesses -Checkpoint 'measurement-start'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $measurementSecond = 1
    while ($timer.Elapsed.TotalSeconds -lt $DurationSeconds) {
        Start-Sleep -Milliseconds 100
        if ($timer.Elapsed.TotalSeconds -ge $measurementSecond) {
            Observe-ForeignRimWorldProcesses -Checkpoint (
                "measurement-second-$measurementSecond")
            $measurementSecond++
        }
    }
    Assert-IsolatedProcesses -Checkpoint 'measurement-end'
    $report = Invoke-AgentCommand `
        -Command 'dev-run performance-probe report' `
        -ExpectedPrefix 'performanceProbe.running=True'
    $timer.Stop()

    foreach ($requiredMetric in @(
            'performanceProbe.tps=',
            'performanceProbe.fps=',
            'performanceProbe.frameMilliseconds=',
            'performanceProbe.wallMillisecondsPerTick=',
            'performanceProbe.processCpuMillisecondsPerTick=')) {
        if ($report.IndexOf(
                $requiredMetric,
                [StringComparison]::Ordinal) -lt 0) {
            throw "Performance probe is missing $requiredMetric"
        }
    }

    Invoke-AgentCommand `
        -Command 'dev-run set-speed paused' `
        -ExpectedPrefix 'timeSpeed=Paused' |
        Out-Null
    Invoke-AgentCommand `
        -Command 'dev-run performance-probe stop' `
        -ExpectedPrefix 'performanceProbe.running=false' |
        Out-Null
    $fixtureAfter = Invoke-AgentCommand `
        -Command 'dev-run construction-fixture report 11004 GT_SoilTilled' `
        -ExpectedPrefix 'constructionFixture.terrain=GT_SoilTilled'
    $cpoHarmonyAfter = Invoke-AgentCommand `
        -Command 'harmony-patches filter=constructionperformanceoptimizer limit=20' `
        -ExpectedPrefix 'patched methods shown='
    Assert-CpoHarmonyState -Report $cpoHarmonyAfter -Checkpoint 'after measurement'
    $companionHarmonyAfter = ''
    if (![string]::IsNullOrWhiteSpace($CompanionHarmonyFilter)) {
        $companionHarmonyAfter = Invoke-AgentCommand `
            -Command (
                "harmony-patches filter=$CompanionHarmonyFilter limit=100") `
            -ExpectedPrefix 'patched methods shown='
        $hasCompanionOwnerAfter = $companionHarmonyAfter.IndexOf(
            $CompanionHarmonyOwnerToken,
            [StringComparison]::OrdinalIgnoreCase) -ge 0
        if ($ExpectedCompanionState -eq 'On' -and !$hasCompanionOwnerAfter) {
            throw "Companion Harmony owner was absent after timing.`n$companionHarmonyAfter"
        }
        if ($ExpectedCompanionState -eq 'Off' -and $hasCompanionOwnerAfter) {
            throw "Companion Harmony owner was present after an off-arm measurement.`n$companionHarmonyAfter"
        }
    }

    $foreignSummary = @(
        "concurrency.allowed=$([bool]$AllowConcurrentRimWorld)"
        "concurrency.foreignObservationCount=$($foreignObservations.Count)"
    )
    if ($foreignObservations.Count -gt 0) {
        $foreignSummary += 'concurrency.foreignObservations'
        $foreignSummary += @(
            $foreignObservations |
                ForEach-Object {
                    '{0}|{1}|{2}|{3}|{4}' -f
                    $_.TimestampUtc,
                    $_.Checkpoint,
                    $_.ProcessId,
                    $_.Name,
                    $_.ExecutablePath
                })
    }
    $output = @(
        "probe.activeWallSeconds=$($timer.Elapsed.TotalSeconds.ToString(
            'F3',
            [Globalization.CultureInfo]::InvariantCulture))"
        "expectedCpoState=$ExpectedCpoState"
        "expectedCompanionState=$ExpectedCompanionState"
        "expectedCompanionModIds=$($ExpectedCompanionModIds -join ';')"
        "runtime.activeModIds=$($activeModIds -join ';')"
        $foreignSummary
        'fixture.before'
        $fixtureBefore.TrimEnd()
        'cpo.harmony.before'
        $cpoHarmonyBefore.TrimEnd()
        'companion.harmony.before'
        $companionHarmonyBefore.TrimEnd()
        $report.TrimEnd()
        'fixture.after'
        $fixtureAfter.TrimEnd()
        'cpo.harmony.after'
        $cpoHarmonyAfter.TrimEnd()
        'companion.harmony.after'
        $companionHarmonyAfter.TrimEnd()
    ) -join [Environment]::NewLine
    $parent = Split-Path -Parent $ResultPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $ResultPath -Value $output -Encoding UTF8
    $output
}
finally {
    $deadline = (Get-Date).AddSeconds(20)
    do {
        $isolatedProcesses = @(
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ExecutablePath -and
                    [IO.Path]::GetDirectoryName($_.ExecutablePath).Equals(
                        $gameRoot,
                        [StringComparison]::OrdinalIgnoreCase) -and
                    $_.Name -like 'RimWorld*.exe'
                })
        foreach ($isolatedProcess in $isolatedProcesses) {
            $ownedProcess =
                Get-Process -Id $isolatedProcess.ProcessId -ErrorAction SilentlyContinue
            if (!$ownedProcess) {
                continue
            }
            $ownedProcess.CloseMainWindow() | Out-Null
            if (!$ownedProcess.WaitForExit(3000)) {
                Stop-Process -Id $ownedProcess.Id -Force
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline -and
        @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ExecutablePath -and
                [IO.Path]::GetDirectoryName($_.ExecutablePath).Equals(
                    $gameRoot,
                    [StringComparison]::OrdinalIgnoreCase) -and
                $_.Name -like 'RimWorld*.exe'
            }).Count -gt 0)
}
