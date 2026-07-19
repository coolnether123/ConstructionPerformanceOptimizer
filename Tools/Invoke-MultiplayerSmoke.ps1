param(
    [ValidateSet("1.5")]
    [string]$Version = "1.5",
    [string]$ReplayName = "ZJC Conversion Baseline-preconvert",
    [string]$SaveName = "CPO Multiplayer Construction 1.5.4409",
    [int]$Port = 30512,
    [int]$RunSeconds = 20,
    [switch]$CreateSave,
    [switch]$TwoClient,
    [switch]$Singleplayer,
    [switch]$ExcludeMultiplayer,
    [switch]$ExcludeCpo,
    [switch]$NoProbe,
    [switch]$Probe
)

$ErrorActionPreference = "Stop"
if ($NoProbe -and $Probe) {
    throw "-NoProbe and -Probe cannot be used together."
}
if ($TwoClient -and $Singleplayer) {
    throw "-TwoClient and -Singleplayer cannot be used together."
}
if ($TwoClient -and $ExcludeMultiplayer) {
    throw "-TwoClient requires Multiplayer to be enabled."
}
if ($TwoClient -and $Probe) {
    throw "The runtime Harmony construction probe is not Multiplayer-safe. Use the synchronized construction fixture evidence instead."
}
$probeEnabled = $Probe -or (!$NoProbe -and !$TwoClient)
$version = $Version
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$rimWorld = "D:\Steam Library\steamapps\common\RimWorld\RimWorldWin64.exe"
$rimWorldDirectory = Split-Path -Parent $rimWorld
$clientExe = Join-Path $rimWorldDirectory "RimWorldClientWin64.exe"
$clientData = Join-Path $rimWorldDirectory "RimWorldClientWin64_Data"
$rimWorldData = Join-Path $rimWorldDirectory "RimWorldWin64_Data"
$cpoAssembly = Join-Path $projectRoot "$version\Assemblies\Construction Performance Optimizer.dll"
$multiplayerApiAssembly = Join-Path $projectRoot "$version\Assemblies\0MultiplayerAPI.dll"
$multiplayerAssembly = "D:\Steam Library\steamapps\workshop\content\294100\2606448745\$version\AssembliesCustom\Multiplayer.dll"
$aboutPath = Join-Path $projectRoot "About\About.xml"
$config = Join-Path $env:USERPROFILE "AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml"
$saveDataRoot = Split-Path -Parent (Split-Path -Parent $config)
$fullProfile = "$config.codex-before-cqo-optimized-20260713-132032"
$playerLog = Join-Path $env:USERPROFILE "AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log"
$sender = "A:\Dev\GitHub\Coolnether123\RimWorld-Agent\Tools\Send-RimWorldAgentCommand.ps1"
$procdump = Join-Path $env:TEMP "Procdump-Codex\procdump64.exe"
$backup = "$config.cpo-mp-smoke.bak"
$evidenceFile = Join-Path $env:TEMP "CPO-MultiplayerSmoke-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$process = $null
$clientProcess = $null
$clientArguments = $null
$testCompleted = $false
$hostSaveData = Join-Path $env:TEMP "RimWorldHost-CPO-$PID"
$hostLog = Join-Path $hostSaveData "Player-host.log"
$clientSaveData = Join-Path $env:TEMP "RimWorldClient-CPO-$PID"
$clientLog = Join-Path $clientSaveData "Player-client.log"
$createdClientExe = $false
$createdClientData = $false
$createdClientSaveData = $false
$createdHostSaveData = $false
$preexistingRimWorldIds = @(Get-Process RimWorldWin64 -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$evidence = [Collections.Generic.List[string]]::new()
$sourceSave = if ([string]::IsNullOrWhiteSpace($SaveName)) {
    $null
} else {
    Join-Path (Join-Path $saveDataRoot "Saves") ($SaveName + ".rws")
}
$sourceSaveExists = $sourceSave -and (Test-Path -LiteralPath $sourceSave)
$creatingSave = [bool]($CreateSave -and $sourceSave -and !$sourceSaveExists)
$fixtureReportCommand = if ($version -eq "1.5") {
    "construction-fixture report-material 100 Wall WoodLog"
} else {
    "construction-fixture report"
}

function Add-Evidence([string]$Text) {
    $value = $Text.TrimEnd()
    $evidence.Add($value)
    Write-Output $value
}

function Wait-Until([scriptblock]$Condition, [int]$TimeoutSeconds, [string]$FailureMessage) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    throw $FailureMessage
}

function Get-AgentPath([string]$Instance, [string]$Name) {
    Join-Path (Join-Path $env:TEMP "RimWorldAgent\$version\$Instance") $Name
}

function Invoke-Agent([string]$Instance, [string]$Command, [int]$TimeoutSeconds = 60) {
    $commandFile = Get-AgentPath $Instance "command.txt"
    $resultFile = Get-AgentPath $Instance "last-result.txt"
    if (Test-Path -LiteralPath $commandFile) {
        Remove-Item -LiteralPath $commandFile -Force
    }
    $sent = Get-Date
    & $sender -Version $version -Instance $Instance -Command $Command | Out-Null
    Wait-Until -TimeoutSeconds $TimeoutSeconds -FailureMessage "Agent command timed out: $Command" -Condition {
        if ((Test-Path $commandFile) -or !(Test-Path $resultFile)) { return $false }
        (Get-Item $resultFile).LastWriteTime -ge $sent
    }
    Get-Content -Raw -LiteralPath $resultFile
}

function Get-OutputValue([string]$Output, [string]$Name) {
    $line = $Output -split "`r?`n" |
        Where-Object { $_.StartsWith($Name + "=", [StringComparison]::Ordinal) } |
        Select-Object -Last 1
    if (!$line) { return $null }
    $line.Substring($Name.Length + 1)
}

function Get-MultiplayerClockState([string]$Status) {
    $worldTicks = 0L
    $worldSpeed = Get-OutputValue $Status "multiplayer.worldDesiredSpeed"
    $mapSpeeds = Get-OutputValue $Status "multiplayer.mapDesiredSpeeds"
    $mapTicks = Get-OutputValue $Status "multiplayer.mapTicks"
    $normalizedMapSpeeds = if ([string]::IsNullOrWhiteSpace($mapSpeeds)) {
        ""
    } else {
        (($mapSpeeds -split ",") | Sort-Object) -join ","
    }
    $normalizedMapTicks = if ([string]::IsNullOrWhiteSpace($mapTicks)) {
        ""
    } else {
        (($mapTicks -split ",") | Sort-Object) -join ","
    }
    $allMapsPaused =
        ![string]::IsNullOrWhiteSpace($normalizedMapSpeeds) -and
        !(($normalizedMapSpeeds -split ",") | Where-Object {
            -not $_.EndsWith(":Paused", [StringComparison]::Ordinal)
        })

    [pscustomobject]@{
        Valid = [long]::TryParse(
            (Get-OutputValue $Status "multiplayer.worldTicks"),
            [ref]$worldTicks) -and
            ![string]::IsNullOrWhiteSpace($normalizedMapTicks)
        Paused = $worldSpeed -eq "Paused" -and $allMapsPaused
        WorldTicks = $worldTicks
        MapTicks = $normalizedMapTicks
        MapSpeeds = $normalizedMapSpeeds
    }
}

function Set-IsolatedPrefs([string]$ConfigDirectory) {
    $prefsPath = Join-Path $ConfigDirectory "Prefs.xml"
    if (!(Test-Path -LiteralPath $prefsPath)) {
        throw "Isolated RimWorld preferences are missing: $prefsPath"
    }

    [xml]$prefs = Get-Content -Raw -LiteralPath $prefsPath
    $prefs.PrefsData.fullscreen = "False"
    $prefs.PrefsData.runInBackground = "True"
    if ($version -eq "1.5") {
        foreach ($name in @("rememberDrawStyles", "zoomSwitchWorldLayer", "gravshipCutscenes")) {
            $node = $prefs.PrefsData.SelectSingleNode($name)
            if ($node) {
                [void]$prefs.PrefsData.RemoveChild($node)
            }
        }
    }
    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $writer = [Xml.XmlWriter]::Create($prefsPath, $settings)
    try { $prefs.Save($writer) } finally { $writer.Dispose() }
}

function Set-ProcessForeground([Diagnostics.Process]$TargetProcess) {
    $shell = New-Object -ComObject WScript.Shell
    try {
        $deadline = (Get-Date).AddSeconds(30)
        do {
            $TargetProcess.Refresh()
            if ($TargetProcess.HasExited) {
                throw "RimWorld process $($TargetProcess.Id) exited before its window could be activated."
            }

            if ($TargetProcess.MainWindowHandle -ne [IntPtr]::Zero -and $shell.AppActivate($TargetProcess.Id)) {
                return
            }

            Start-Sleep -Milliseconds 200
        } while ((Get-Date) -lt $deadline)
    } finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }

    throw "Could not activate RimWorld process $($TargetProcess.Id)."
}

function Wait-ForDurableHeartbeat(
    [string]$Instance,
    [string]$HeartbeatPath,
    [Diagnostics.Process]$TargetProcess,
    [int]$TimeoutSeconds,
    [string]$FailureMessage,
    [bool]$CaptureHangDump = $true
) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $dumpCaptured = $false
    $staleObservedAt = Get-Date
    $freshObservedAt = $null
    $lastFreshWrite = $null
    $freshUpdates = 0
    do {
        if (Test-Path -LiteralPath $HeartbeatPath) {
            $heartbeatItem = Get-Item -LiteralPath $HeartbeatPath -ErrorAction SilentlyContinue
            if (!$heartbeatItem) {
                Start-Sleep -Milliseconds 200
                continue
            }
            $heartbeatWrite = $heartbeatItem.LastWriteTime
            $ageSeconds = ((Get-Date) - $heartbeatWrite).TotalSeconds
            if ($ageSeconds -lt 3) {
                if ($lastFreshWrite -ne $heartbeatWrite) {
                    $lastFreshWrite = $heartbeatWrite
                    $freshUpdates++
                    if ($null -eq $freshObservedAt) {
                        $freshObservedAt = Get-Date
                    }
                }

                if ($freshUpdates -ge 3 -and ((Get-Date) - $freshObservedAt).TotalSeconds -ge 5) {
                    return
                }
            } else {
                $freshObservedAt = $null
                $lastFreshWrite = $null
                $freshUpdates = 0
            }

            if ($CaptureHangDump -and
                !$dumpCaptured -and
                $ageSeconds -ge 30 -and
                ((Get-Date) - $staleObservedAt).TotalSeconds -ge 60 -and
                (Test-Path -LiteralPath $procdump)) {
                $dumpPath = "$evidenceFile.$Instance-hang.dmp"
                $TargetProcess.Refresh()
                if (!$TargetProcess.HasExited) {
                    & $procdump -accepteula -ma $TargetProcess.Id $dumpPath | Out-Null
                    if (Test-Path -LiteralPath $dumpPath) {
                        Add-Evidence "hang.dump.$Instance=$dumpPath"
                    } else {
                        Add-Evidence "hang.dump.$Instance=failed exitCode=$LASTEXITCODE"
                    }
                }
                $dumpCaptured = $true
            }
        }

        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    throw $FailureMessage
}

function Assert-NoDesync {
    foreach ($log in @($hostLog, $clientLog)) {
        if ((Test-Path -LiteralPath $log) -and
            (Select-String -LiteralPath $log -Pattern "Desynced after last valid tick" -Quiet)) {
            throw "Multiplayer desync detected in $log"
        }
    }
}

foreach ($required in @(
    $rimWorld,
    $cpoAssembly,
    $multiplayerApiAssembly,
    $multiplayerAssembly,
    $aboutPath,
    $config,
    $fullProfile,
    $sender
)) {
    if (!(Test-Path -LiteralPath $required)) { throw "Required path missing: $required" }
}
if ($sourceSave -and !$sourceSaveExists -and !$creatingSave) {
    throw "Required save missing: $sourceSave"
}

Copy-Item -LiteralPath $config -Destination $backup -Force
$originalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $config).Hash
$cpoHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $cpoAssembly).Hash
$multiplayerApiHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $multiplayerApiAssembly).Hash
$multiplayerVersion = [Reflection.AssemblyName]::GetAssemblyName($multiplayerAssembly).Version.ToString(3)
$multiplayerApiAssemblyVersion = [Reflection.AssemblyName]::GetAssemblyName($multiplayerApiAssembly).Version
$multiplayerApiVersion = "$($multiplayerApiAssemblyVersion.Major).$($multiplayerApiAssemblyVersion.Minor)"
[xml]$about = Get-Content -Raw -LiteralPath $aboutPath
$releaseVersion = [string]$about.ModMetaData.modVersion
$releaseArchive = "ConstructionPerformanceOptimizer-$releaseVersion-rw$version.zip"
$gameVersion = "<unknown>"
if ($sourceSaveExists) {
    $gameVersionMatch = Select-String -LiteralPath $sourceSave -Pattern "<gameVersion>([^<]+)" |
        Select-Object -First 1
    if ($gameVersionMatch) {
        $gameVersion = $gameVersionMatch.Matches[0].Groups[1].Value
    }
}

try {
    [xml]$profile = Get-Content -Raw -LiteralPath $fullProfile
    if ($version -eq "1.5") {
        $profile.ModsConfigData.version = "1.5.4409 rev1120"
    }
    $active = $profile.ModsConfigData.activeMods
    $forbiddenIds = @(
        "coolnether123.betterworktab",
        "coolnether123.constructionqueueoptimizer",
        "coolnether123.constructionperformanceoptimizer.benchmarklegacy",
        "benchmark.cpo.foreignvalidationowner"
    )
    $versionExcludedIds = @()
    if ($version -eq "1.5") {
        $versionExcludedIds = @(
            "ludeon.rimworld.odyssey",
            "defi.stabilizebleeding",
            "adamas.hospitalitycasino"
        )
        $forbiddenIds += $versionExcludedIds
    }
    if ($ExcludeMultiplayer) {
        $forbiddenIds += @("rwmt.multiplayer", "rwmt.multiplayercompatibility")
    }
    foreach ($id in @($forbiddenIds + "coolnether123.constructionperformanceoptimizer")) {
        @($active.SelectNodes("li")) |
            Where-Object { $_.InnerText.Equals($id, [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { [void]$active.RemoveChild($_) }
    }

    if (!$ExcludeCpo) {
        $cpo = $profile.CreateElement("li")
        $cpo.InnerText = "coolnether123.constructionperformanceoptimizer"
        $agent = @($active.SelectNodes("li")) |
            Where-Object { $_.InnerText.Equals("coolnether123.rimworldagent", [StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
        if ($agent) { [void]$active.InsertBefore($cpo, $agent) } else { [void]$active.AppendChild($cpo) }
    }

    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $writer = [Xml.XmlWriter]::Create($config, $settings)
    try { $profile.Save($writer) } finally { $writer.Dispose() }

    $ids = @($active.SelectNodes("li") | ForEach-Object { $_.InnerText.ToLowerInvariant() })
    $forbidden = @($ids | Where-Object { $forbiddenIds -contains $_ })
    if ($forbidden.Count -ne 0) { throw "Forbidden test mods active: $($forbidden -join ', ')" }
    $cpoActive = $ids -contains "coolnether123.constructionperformanceoptimizer"
    if ($cpoActive -eq [bool]$ExcludeCpo) { throw "CPO profile state did not match ExcludeCpo=$([bool]$ExcludeCpo)." }
    Add-Evidence "test.version=$version"
    Add-Evidence "game.version=$gameVersion"
    Add-Evidence "multiplayer.version=$multiplayerVersion"
    Add-Evidence "multiplayerApi.version=$multiplayerApiVersion"
    Add-Evidence "artifact.cpoSha256=$cpoHash"
    Add-Evidence "artifact.multiplayerApiSha256=$multiplayerApiHash"
    Add-Evidence "artifact.releaseArchive=$releaseArchive"
    Add-Evidence "test.source=$(if ($creatingSave) { 'quickstart-created-save' } elseif ($sourceSaveExists) { 'save' } else { 'replay' })"
    Add-Evidence "test.save=$SaveName"
    Add-Evidence "test.createSave=$creatingSave"
    Add-Evidence "test.replay=$ReplayName"
    Add-Evidence "test.activeMods=$($ids.Count)"
    Add-Evidence "test.versionExcluded=$($versionExcludedIds -join ',')"
    Add-Evidence "test.cpo=$cpoActive"
    Add-Evidence "test.betterWorkTab=false"
    Add-Evidence "test.legacyOptimizer=false"
    Add-Evidence "test.multiplayer=$($ids -contains 'rwmt.multiplayer')"
    Add-Evidence "test.multiplayerCompatibility=$($ids -contains 'rwmt.multiplayercompatibility')"
    Add-Evidence "test.excludeMultiplayer=$([bool]$ExcludeMultiplayer)"
    Add-Evidence "test.tilledSoil=$($ids -contains 'gt.sam.tilledsoil')"
    Add-Evidence "test.twoClient=$([bool]$TwoClient)"
    Add-Evidence "test.singleplayer=$([bool]$Singleplayer)"
    Add-Evidence "test.probe=$probeEnabled"
    if ($TwoClient) {
        Add-Evidence "test.probePolicy=synchronized fixture only; runtime Harmony probe disabled"
    }
    Add-Evidence "process.preexisting=$($preexistingRimWorldIds.Count)"

    foreach ($instance in @("host", "client")) {
        foreach ($name in @("command.txt", "ready.txt", "heartbeat.txt")) {
            $stale = Get-AgentPath $instance $name
            if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force }
        }
    }
    New-Item -ItemType Directory -Path $hostSaveData | Out-Null
    $createdHostSaveData = $true
    Copy-Item -LiteralPath (Join-Path $saveDataRoot "Config") -Destination (Join-Path $hostSaveData "Config") -Recurse
    Set-IsolatedPrefs (Join-Path $hostSaveData "Config")
    if (Test-Path -LiteralPath (Join-Path $saveDataRoot "HugsLib")) {
        Copy-Item -LiteralPath (Join-Path $saveDataRoot "HugsLib") -Destination (Join-Path $hostSaveData "HugsLib") -Recurse
    }
    if ($sourceSaveExists) {
        New-Item -ItemType Directory -Path (Join-Path $hostSaveData "Saves") | Out-Null
        Copy-Item -LiteralPath $sourceSave -Destination (Join-Path $hostSaveData "Saves")
    }
    New-Item -ItemType Directory -Path (Join-Path $hostSaveData "MpReplays") | Out-Null
    Copy-Item -LiteralPath (Join-Path (Join-Path $saveDataRoot "MpReplays") ($ReplayName + ".zip")) -Destination (Join-Path $hostSaveData "MpReplays")
    $hostArguments = @(
        "-rw-agent", "-rw-agent-id", "host", "-savedatafolder=$hostSaveData", "-logfile", $hostLog,
        "-screen-fullscreen", "0", "-screen-width", "1920", "-screen-height", "1080"
    )
    if (!$TwoClient -and !$Singleplayer) { $hostArguments = @("-batchmode") + $hostArguments }
    $process = Start-Process -FilePath $rimWorld -ArgumentList $hostArguments -PassThru
    $started = $process.StartTime
    Add-Evidence "process.hostId=$($process.Id)"
    Set-ProcessForeground $process

    if ($TwoClient) {
        if ((Test-Path -LiteralPath $clientExe) -or (Test-Path -LiteralPath $clientData)) {
            $staleExeMatches =
                (Test-Path -LiteralPath $clientExe) -and
                ((Get-FileHash -Algorithm SHA256 -LiteralPath $clientExe).Hash -eq
                    (Get-FileHash -Algorithm SHA256 -LiteralPath $rimWorld).Hash)
            $staleDataItem = Get-Item -LiteralPath $clientData -Force -ErrorAction SilentlyContinue
            $staleDataTarget = if ($staleDataItem -and $staleDataItem.Target) {
                [IO.Path]::GetFullPath([string]$staleDataItem.Target[0])
            } else {
                $null
            }
            $staleDataMatches =
                $staleDataItem -and
                $staleDataItem.LinkType -eq "Junction" -and
                $staleDataTarget -eq [IO.Path]::GetFullPath($rimWorldData)
            if (!$staleExeMatches -or !$staleDataMatches) {
                throw "Existing client paths are not recognized harness artifacts: $clientExe / $clientData"
            }

            [IO.Directory]::Delete($clientData, $false)
            Remove-Item -LiteralPath $clientExe -Force
            Add-Evidence "cleanup.staleClientArtifacts=true"
        }
        Copy-Item -LiteralPath $rimWorld -Destination $clientExe
        $createdClientExe = $true
        New-Item -ItemType Junction -Path $clientData -Target $rimWorldData | Out-Null
        $createdClientData = $true
        New-Item -ItemType Directory -Path $clientSaveData | Out-Null
        $createdClientSaveData = $true
        Copy-Item -LiteralPath (Join-Path $saveDataRoot "Config") -Destination (Join-Path $clientSaveData "Config") -Recurse
        Set-IsolatedPrefs (Join-Path $clientSaveData "Config")
        if (Test-Path -LiteralPath (Join-Path $saveDataRoot "HugsLib")) {
            Copy-Item -LiteralPath (Join-Path $saveDataRoot "HugsLib") -Destination (Join-Path $clientSaveData "HugsLib") -Recurse
        }
        $clientArguments = @(
            "-force-d3d11", "-force-driver-type-warp",
            "-rw-agent", "-rw-agent-id", "client", "-savedatafolder=$clientSaveData", "-logfile", $clientLog,
            "-screen-fullscreen", "0", "-screen-width", "1280", "-screen-height", "720"
        )
    }

    $readyFile = Get-AgentPath "host" "ready.txt"
    $heartbeatFile = Get-AgentPath "host" "heartbeat.txt"
    Wait-Until -TimeoutSeconds 300 -FailureMessage "Agent did not become ready." -Condition {
        (Test-Path $readyFile) -and (Get-Item $readyFile).LastWriteTime -gt $started
    }
    $initializationMarker = if ($ExcludeCpo) { "[RimWorld Agent] Enabled." } else { "[Construction Performance Optimizer] features:" }
    Wait-Until -TimeoutSeconds 600 -FailureMessage "Full mod initialization did not complete." -Condition {
        if (!(Test-Path $hostLog)) { return $false }
        $log = Get-Content -Raw -LiteralPath $hostLog
        ($ExcludeMultiplayer -or $log.Contains("Multiplayer version ")) -and $log.Contains($initializationMarker)
    }
    Wait-ForDurableHeartbeat "host" $heartbeatFile $process 600 "Agent heartbeat was not durable after mod initialization." $false
    Add-Evidence "agent.durableReady=true"

    if ($TwoClient) {
        # Loading two large mod lists concurrently can stall one Unity main loop
        # during startup. Initialize the host first, then start the second process.
        $clientProcess = Start-Process -FilePath $clientExe -ArgumentList $clientArguments -PassThru
        Add-Evidence "process.clientId=$($clientProcess.Id)"
        Set-ProcessForeground $clientProcess
        $clientReadyFile = Get-AgentPath "client" "ready.txt"
        $clientHeartbeatFile = Get-AgentPath "client" "heartbeat.txt"
        $clientStarted = $clientProcess.StartTime
        Wait-Until -TimeoutSeconds 360 -FailureMessage "Client agent did not become ready." -Condition {
            (Test-Path $clientReadyFile) -and (Get-Item $clientReadyFile).LastWriteTime -gt $clientStarted
        }
        Wait-Until -TimeoutSeconds 600 -FailureMessage "Client full mod initialization did not complete." -Condition {
            if (!(Test-Path $clientLog)) { return $false }
            $log = Get-Content -Raw -LiteralPath $clientLog
            $log.Contains("Multiplayer version ") -and $log.Contains($initializationMarker)
        }
        Set-ProcessForeground $clientProcess
        Wait-ForDurableHeartbeat "client" $clientHeartbeatFile $clientProcess 120 "Client heartbeat was not durable."
        $rendererLine = Select-String -LiteralPath $clientLog -Pattern "^\s*Renderer:" |
            Select-Object -First 1 -ExpandProperty Line
        Add-Evidence ("client.renderer=" + $(if ($rendererLine) { $rendererLine.Trim() } else { "<unknown>" }))
    }

    # Instrument before either process enters a Multiplayer session. Installing
    # Harmony probes after joining can change JIT/patch timing at different local
    # frames even while the host is requesting a pause.
    if ($probeEnabled) {
        $hostProbeStart = Invoke-Agent "host" "dev-run construction-probe start"
        Add-Evidence $hostProbeStart
        if (!$hostProbeStart.StartsWith("constructionProbe.running=true", [StringComparison]::Ordinal)) {
            throw "Host construction probe did not start: $hostProbeStart"
        }
        if ($TwoClient) {
            $clientProbeStart = Invoke-Agent "client" "dev-run construction-probe start"
            Add-Evidence $clientProbeStart
            if (!$clientProbeStart.StartsWith("constructionProbe.running=true", [StringComparison]::Ordinal)) {
                throw "Client construction probe did not start: $clientProbeStart"
            }
        }
    }

    if ($sourceSaveExists) {
        $loadQueued = Invoke-Agent -Instance "host" -Command "dev-run load-save `"$SaveName`" --pause-after-load" -TimeoutSeconds 300
        Add-Evidence $loadQueued
        if (!$loadQueued.StartsWith("load queued:", [StringComparison]::Ordinal)) {
            throw "Singleplayer save did not queue for loading."
        }

        $loadDeadline = (Get-Date).AddMinutes(8)
        do {
            Start-Sleep -Seconds 3
            [void](Invoke-Agent -Instance "host" -Command "status")
            $loadStatus = Get-Content -Raw -LiteralPath (Get-AgentPath "host" "status.txt")
            Add-Evidence ("load.poll=" + ($loadStatus.TrimEnd() -replace "`r?`n", "; "))
            $loadReady =
                (Get-OutputValue $loadStatus "programState") -eq "Playing" -and
                (Get-OutputValue $loadStatus "mapReady") -eq "True"
        } while (!$loadReady -and (Get-Date) -lt $loadDeadline)
        if (!$loadReady) {
            throw "Singleplayer save did not finish loading before Multiplayer host startup."
        }

        if (!$Singleplayer) {
            $queued = Invoke-Agent -Instance "host" -Command "dev-run mp-host $Port CPOReleaseTest" -TimeoutSeconds 300
            Add-Evidence $queued
            if (!$queued.StartsWith("Multiplayer host requested", [StringComparison]::Ordinal)) {
                throw "Loaded save did not start a Multiplayer host."
            }
        } else {
            Add-Evidence "test.session=singleplayer"
        }
    } elseif ($creatingSave) {
        Add-Evidence (Invoke-Agent -Instance "host" -Command "quickstart" -TimeoutSeconds 300)
        $quickstartDeadline = (Get-Date).AddMinutes(8)
        do {
            Start-Sleep -Seconds 3
            [void](Invoke-Agent -Instance "host" -Command "status")
            $quickstartStatus = Get-Content -Raw -LiteralPath (Get-AgentPath "host" "status.txt")
            Add-Evidence ("quickstart.poll=" + ($quickstartStatus.TrimEnd() -replace "`r?`n", "; "))
            $quickstartReady =
                (Get-OutputValue $quickstartStatus "programState") -eq "Playing" -and
                (Get-OutputValue $quickstartStatus "mapReady") -eq "True"
        } while (!$quickstartReady -and (Get-Date) -lt $quickstartDeadline)
        if (!$quickstartReady) {
            throw "RimWorld 1.5 quickstart did not create a playable map."
        }

        Add-Evidence (Invoke-Agent "host" "dev-run set-speed paused")
        $fixtureBuild = Invoke-Agent "host" "dev-run construction-fixture build-material 100 Wall WoodLog"
        Add-Evidence ("construction.created:`n" + $fixtureBuild)
        $createdTotal = 0
        if (![int]::TryParse((Get-OutputValue $fixtureBuild "constructionFixture.total"), [ref]$createdTotal) -or
            $createdTotal -le 0) {
            throw "The RimWorld 1.5 construction fixture was not created."
        }

        $isolatedSave = Join-Path (Join-Path $hostSaveData "Saves") ($SaveName + ".rws")
        $saveQueuedAt = Get-Date
        $saveResult = Invoke-Agent "host" "dev-run save-game `"$SaveName`"" -TimeoutSeconds 300
        Add-Evidence $saveResult
        if (!$saveResult.StartsWith("save queued:", [StringComparison]::Ordinal)) {
            throw "The RimWorld 1.5 fixture save did not queue."
        }
        Wait-Until -TimeoutSeconds 300 -FailureMessage "The RimWorld 1.5 fixture save did not finish." -Condition {
            try {
                (Test-Path -LiteralPath $isolatedSave) -and
                    (Get-Item -LiteralPath $isolatedSave).LastWriteTime -ge $saveQueuedAt -and
                    (Select-String -LiteralPath $isolatedSave -Pattern "<gameVersion>1.5." -SimpleMatch -Quiet)
            } catch {
                $false
            }
        }
        Copy-Item -LiteralPath $isolatedSave -Destination $sourceSave -Force
        $sourceSaveExists = $true
        Add-Evidence "test.createdSavePath=$sourceSave"
        Add-Evidence "test.createdSaveSha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $sourceSave).Hash)"

        if (!$Singleplayer) {
            $queued = Invoke-Agent -Instance "host" -Command "dev-run mp-host $Port CPOReleaseTest" -TimeoutSeconds 300
            Add-Evidence $queued
            if (!$queued.StartsWith("Multiplayer host requested", [StringComparison]::Ordinal)) {
                throw "Created save did not start a Multiplayer host."
            }
        } else {
            Add-Evidence "test.session=singleplayer"
        }
    } else {
        if ($Singleplayer) {
            throw "Singleplayer mode requires -SaveName."
        }
        $queued = Invoke-Agent -Instance "host" -Command "dev-run mp-host-replay `"$ReplayName`" $Port CPOReleaseTest" -TimeoutSeconds 300
        Add-Evidence $queued
        if (!$queued.StartsWith("Multiplayer replay host queued", [StringComparison]::Ordinal)) {
            throw "Replay host did not queue."
        }
    }

    if (!$Singleplayer) {
        $status = ""
        $deadline = (Get-Date).AddMinutes(8)
        do {
            Start-Sleep -Seconds 3
            $status = Invoke-Agent -Instance "host" -Command "dev-run mp-status"
            Add-Evidence ("host.poll=" + ($status.TrimEnd() -replace "`r?`n", "; "))
            if ($status -match "localServer\.fullyStarted=True" -and $status -match "client=True") { break }
        } while ((Get-Date) -lt $deadline)
        if (!($status -match "localServer\.fullyStarted=True" -and $status -match "client=True")) {
            throw "Multiplayer host did not become ready."
        }
    }

    if ($TwoClient) {
        Add-Evidence (Invoke-Agent -Instance "client" -Command "dev-run mp-connect 127.0.0.1 $Port CodexClient")
        $clientStatus = ""
        $clientDeadline = (Get-Date).AddMinutes(10)
        do {
            Start-Sleep -Seconds 3
            $clientStatus = Invoke-Agent -Instance "client" -Command "dev-run mp-status"
            Add-Evidence ("client.poll=" + ($clientStatus.TrimEnd() -replace "`r?`n", "; "))
            $clientLoadedMapCount = 0
            $clientWorldReady =
                $clientStatus -match "client.state=ClientPlaying" -and
                $clientStatus -match "(?m)^username=CodexClient\r?$" -and
                [int]::TryParse(
                    (Get-OutputValue $clientStatus "game.mapCount"),
                    [ref]$clientLoadedMapCount) -and
                $clientLoadedMapCount -gt 0
            if ($clientWorldReady) { break }
        } while ((Get-Date) -lt $clientDeadline)
        if (!$clientWorldReady) {
            throw "Second Multiplayer client did not finish loading the hosted world."
        }
        Add-Evidence (Invoke-Agent "host" "dev-run mp-set-speed paused")
        $syncDeadline = (Get-Date).AddMinutes(10)
        do {
            Start-Sleep -Seconds 3
            Assert-NoDesync
            $hostSyncStatus = Invoke-Agent "host" "dev-run mp-status"
            $clientSyncStatus = Invoke-Agent "client" "dev-run mp-status"
            $hostMapCount = 0
            $clientMapCount = 0
            $hostClock = Get-MultiplayerClockState $hostSyncStatus
            $clientClock = Get-MultiplayerClockState $clientSyncStatus
            $syncReady = $hostClock.Valid -and $clientClock.Valid -and
                [int]::TryParse((Get-OutputValue $hostSyncStatus "game.mapCount"), [ref]$hostMapCount) -and
                [int]::TryParse((Get-OutputValue $clientSyncStatus "game.mapCount"), [ref]$clientMapCount) -and
                $hostMapCount -gt 0 -and $clientMapCount -eq $hostMapCount -and
                $hostClock.Paused -and $clientClock.Paused -and
                (Get-OutputValue $hostSyncStatus "multiplayer.desynced") -eq "False" -and
                (Get-OutputValue $clientSyncStatus "multiplayer.desynced") -eq "False" -and
                $hostClock.WorldTicks -eq $clientClock.WorldTicks -and
                $hostClock.MapTicks -eq $clientClock.MapTicks
        } while (!$syncReady -and (Get-Date) -lt $syncDeadline)
        if (!$syncReady) {
            Add-Evidence ("sync.timeout.host=" + ($hostSyncStatus.TrimEnd() -replace "`r?`n", "; "))
            Add-Evidence ("sync.timeout.client=" + ($clientSyncStatus.TrimEnd() -replace "`r?`n", "; "))
            throw "Multiplayer clients did not reach the same initial paused simulation clock."
        }
        Add-Evidence "sync.initial.worldTicks=$($hostClock.WorldTicks)"
        Add-Evidence "sync.initial.mapTicks=$($hostClock.MapTicks)"
        Add-Evidence "sync.initial.mapSpeeds=$($hostClock.MapSpeeds)"
        Add-Evidence "sync.initial.mapCount=$hostMapCount"
        $initialWorldTicks = $hostClock.WorldTicks
    }

    $constructionBefore = Invoke-Agent "host" "dev-run $fixtureReportCommand"
    Add-Evidence ("construction.before:`n" + $constructionBefore)
    $speedTool = if ($Singleplayer) { "set-speed" } else { "mp-set-speed" }
    Add-Evidence (Invoke-Agent "host" "dev-run $speedTool ultrafast")
    Start-Sleep -Seconds $RunSeconds
    Add-Evidence (Invoke-Agent "host" "dev-run $speedTool paused")
    if ($TwoClient) {
        $syncDeadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 3
            Assert-NoDesync
            $hostSyncStatus = Invoke-Agent "host" "dev-run mp-status"
            $clientSyncStatus = Invoke-Agent "client" "dev-run mp-status"
            $hostClock = Get-MultiplayerClockState $hostSyncStatus
            $clientClock = Get-MultiplayerClockState $clientSyncStatus
            $syncReady = $hostClock.Valid -and $clientClock.Valid -and
                $hostClock.Paused -and $clientClock.Paused -and
                (Get-OutputValue $hostSyncStatus "multiplayer.desynced") -eq "False" -and
                (Get-OutputValue $clientSyncStatus "multiplayer.desynced") -eq "False" -and
                $hostClock.WorldTicks -eq $clientClock.WorldTicks -and
                $hostClock.MapTicks -eq $clientClock.MapTicks -and
                $hostClock.WorldTicks -gt $initialWorldTicks
        } while (!$syncReady -and (Get-Date) -lt $syncDeadline)
        if (!$syncReady) { throw "Multiplayer client did not catch up to the paused simulation clock." }
        Add-Evidence "sync.final.worldTicks=$($hostClock.WorldTicks)"
        Add-Evidence "sync.final.mapTicks=$($hostClock.MapTicks)"
        Add-Evidence "sync.final.mapSpeeds=$($hostClock.MapSpeeds)"
    }
    Start-Sleep -Seconds 2
    if ($probeEnabled) {
        $hostProbe = Invoke-Agent "host" "dev-run construction-probe stop"
        Add-Evidence ("host.probe:`n" + $hostProbe)
        if ($TwoClient) {
            $clientProbe = Invoke-Agent "client" "dev-run construction-probe stop"
            Add-Evidence ("client.probe:`n" + $clientProbe)
        }
    }
    if ($TwoClient) {
        Add-Evidence ("client.final:`n" + (Invoke-Agent "client" "dev-run mp-status"))
    }
    $constructionAfter = Invoke-Agent "host" "dev-run $fixtureReportCommand"
    Add-Evidence ("construction.after:`n" + $constructionAfter)
    $beforeTotal = 0
    $afterTotal = 0
    if (![int]::TryParse((Get-OutputValue $constructionBefore "constructionFixture.total"), [ref]$beforeTotal) -or
        ![int]::TryParse((Get-OutputValue $constructionAfter "constructionFixture.total"), [ref]$afterTotal)) {
        throw "Construction fixture totals were not reported."
    }
    if ($afterTotal -ge $beforeTotal) {
        throw "Construction did not progress: before=$beforeTotal after=$afterTotal."
    }
    Add-Evidence "construction.completed=$($beforeTotal - $afterTotal)"
    $finalStatusCommand = if ($Singleplayer) { "status" } else { "dev-run mp-status" }
    Add-Evidence ("host.final:`n" + (Invoke-Agent "host" $finalStatusCommand))
    Assert-NoDesync
    Add-Evidence "test.completed=true"
    $testCompleted = $true
}
catch {
    Add-Evidence "test.completed=false"
    Add-Evidence "test.error=$($_.Exception.Message)"
    throw
}
finally {
    $desyncLogDetected = @($hostLog, $clientLog) | Where-Object {
        (Test-Path -LiteralPath $_) -and
            (Select-String -LiteralPath $_ -Pattern "Desynced after last valid tick" -Quiet)
    }
    if ($desyncLogDetected.Count -gt 0) {
        $desyncDirectory = Join-Path $clientSaveData "MpDesyncs"
        $desyncDeadline = (Get-Date).AddSeconds(10)
        while (!(Get-ChildItem -LiteralPath $desyncDirectory -Filter "*.zip" -File -ErrorAction SilentlyContinue) -and
            (Get-Date) -lt $desyncDeadline) {
            Start-Sleep -Milliseconds 200
        }
    }
    if ($clientProcess) {
        $clientProcess.Refresh()
        if (!$clientProcess.HasExited) {
            Stop-Process -Id $clientProcess.Id -Force
            [void]$clientProcess.WaitForExit(10000)
        }
    }
    if ($process) {
        $process.Refresh()
        if (!$process.HasExited) {
            [void]$process.CloseMainWindow()
            if (!$process.WaitForExit(20000)) {
                Stop-Process -Id $process.Id -Force
                [void]$process.WaitForExit(10000)
            }
        }
    }
    Copy-Item -LiteralPath $backup -Destination $config -Force
    $restoredHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $config).Hash
    Add-Evidence "profile.originalHash=$originalHash"
    Add-Evidence "profile.restoredHash=$restoredHash"
    Add-Evidence "profile.restored=$($restoredHash -eq $originalHash)"
    $testProcessRemaining = $false
    if ($process) {
        $process.Refresh()
        $testProcessRemaining = !$process.HasExited
    }
    Add-Evidence "process.testRemaining=$testProcessRemaining"
    Add-Evidence "process.clientRemaining=$([bool]($clientProcess -and !$clientProcess.HasExited))"
    Add-Evidence "process.otherRimWorld=$(@(Get-Process RimWorldWin64 -ErrorAction SilentlyContinue | Where-Object { !$process -or $_.Id -ne $process.Id }).Count)"
    foreach ($instanceLog in @(
        [pscustomobject]@{ Name = "host"; Path = $hostLog },
        [pscustomobject]@{ Name = "client"; Path = $clientLog }
    )) {
        if (Test-Path -LiteralPath $instanceLog.Path) {
            $matches = Select-String -LiteralPath $instanceLog.Path -Pattern "Construction Performance Optimizer|desync|Exception|Error" -CaseSensitive:$false |
                Select-Object -Last 160 | ForEach-Object { $_.Line }
            Add-Evidence ("$($instanceLog.Name)Log.matches:`n" + ($matches -join [Environment]::NewLine))
        }
    }
    $desyncFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $clientSaveData "MpDesyncs") -Filter "*.zip" -File -ErrorAction SilentlyContinue
    )
    Add-Evidence "desync.detected=$($desyncLogDetected.Count -gt 0 -or $desyncFiles.Count -gt 0)"
    if (!$testCompleted -or $desyncFiles.Count -gt 0) {
        $artifactDirectory = $evidenceFile + ".artifacts"
        New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
        @($hostLog, $clientLog) |
            Where-Object { Test-Path -LiteralPath $_ } |
            Copy-Item -Destination $artifactDirectory -Force
        $desyncFiles | Copy-Item -Destination $artifactDirectory -Force
        foreach ($instance in @("host", "client")) {
            $agentDirectory = Split-Path -Parent (Get-AgentPath $instance "status.txt")
            foreach ($agentFile in @("heartbeat.txt", "watchdog.txt", "status.txt", "lifecycle-journal.log")) {
                $source = Join-Path $agentDirectory $agentFile
                if (Test-Path -LiteralPath $source) {
                    Copy-Item -LiteralPath $source -Destination (Join-Path $artifactDirectory "$instance-$agentFile") -Force
                }
            }
        }
        Add-Evidence "test.artifacts=$artifactDirectory"
    }
    if ($createdClientData -and (Test-Path -LiteralPath $clientData)) {
        try { [IO.Directory]::Delete($clientData, $false) } catch { Add-Evidence "cleanup.clientData=$($_.Exception.Message)" }
    }
    if ($createdClientExe -and (Test-Path -LiteralPath $clientExe)) {
        try { Remove-Item -LiteralPath $clientExe -Force } catch { Add-Evidence "cleanup.clientExe=$($_.Exception.Message)" }
    }
    if ($createdClientSaveData -and (Test-Path -LiteralPath $clientSaveData)) {
        try {
            $resolvedClientSave = [IO.Path]::GetFullPath($clientSaveData)
            $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            if (!$resolvedClientSave.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove client save data outside TEMP: $resolvedClientSave"
            }
            Remove-Item -LiteralPath $resolvedClientSave -Recurse -Force
        } catch { Add-Evidence "cleanup.clientSaveData=$($_.Exception.Message)" }
    }
    if ($createdHostSaveData -and (Test-Path -LiteralPath $hostSaveData)) {
        try {
            $resolvedHostSave = [IO.Path]::GetFullPath($hostSaveData)
            $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            if (!$resolvedHostSave.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove host save data outside TEMP: $resolvedHostSave"
            }
            Remove-Item -LiteralPath $resolvedHostSave -Recurse -Force
        } catch { Add-Evidence "cleanup.hostSaveData=$($_.Exception.Message)" }
    }
    $evidence | Set-Content -LiteralPath $evidenceFile -Encoding UTF8
    if ($restoredHash -eq $originalHash -and (Test-Path -LiteralPath $backup)) {
        Remove-Item -LiteralPath $backup -Force
    }
    Write-Output "evidence.path=$evidenceFile"
}
