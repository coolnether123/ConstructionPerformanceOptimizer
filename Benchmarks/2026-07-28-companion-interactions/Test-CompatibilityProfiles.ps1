[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$suiteRoot = $PSScriptRoot
$registryPath = Join-Path $suiteRoot 'CompanionMods.csv'
$profilesRoot = Join-Path $suiteRoot 'CompatibilityProfiles'
$registry = @(Import-Csv -LiteralPath $registryPath)
$knownPackageIds = @(
    $registry |
        ForEach-Object { $_.additional_mod_ids -split ';' } |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.ToLowerInvariant() } |
        Sort-Object -Unique)
$profiles = @(Get-ChildItem -LiteralPath $profilesRoot -Filter 'Set-*.ps1')

foreach ($companion in $registry) {
    if ($companion.profile_order -notmatch '^(append|(before|after):.+)$') {
        throw "Invalid profile_order for $($companion.slug): $($companion.profile_order)"
    }
    $minimumWarmup = 0
    if (![int]::TryParse(
            $companion.minimum_warmup_seconds,
            [ref]$minimumWarmup) -or
        $minimumWarmup -lt 0) {
        throw "Invalid minimum warmup for $($companion.slug)."
    }
    foreach ($constraint in @(
            $companion.required_order -split ';' |
                Where-Object { ![string]::IsNullOrWhiteSpace($_) })) {
        if (@($constraint -split '>').Count -ne 2) {
            throw "Invalid required-order constraint for $($companion.slug): $constraint"
        }
    }
}

if ($profiles.Count -eq 0) {
    throw 'No companion compatibility profiles were found.'
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'CPO-CompatibilityProfiles-{0}' -f [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null

    foreach ($profile in $profiles) {
        $packageId = $profile.BaseName.Substring('Set-'.Length).ToLowerInvariant()
        if ($knownPackageIds -notcontains $packageId) {
            throw "Compatibility profile has no registered companion: $($profile.Name)"
        }

        $configRoot = Join-Path $testRoot $packageId
        $outputs = @(& $profile.FullName -ConfigRoot $configRoot)
        if ($outputs.Count -eq 0) {
            throw "Compatibility profile returned no settings files: $($profile.Name)"
        }
        foreach ($output in $outputs) {
            $resolvedOutput = [IO.Path]::GetFullPath($output)
            $resolvedConfigRoot = [IO.Path]::GetFullPath($configRoot).TrimEnd('\') + '\'
            if (!$resolvedOutput.StartsWith(
                    $resolvedConfigRoot,
                    [StringComparison]::OrdinalIgnoreCase)) {
                throw "Compatibility profile output escaped its config root: $resolvedOutput"
            }
            if (!(Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
                throw "Compatibility profile did not write its declared output: $resolvedOutput"
            }
            [void]([xml](Get-Content -Raw -LiteralPath $resolvedOutput))
        }
    }

    $fishSettings = Join-Path $testRoot (
        'bs.performance\Mod_companion-bs.performance_PerformanceFishMod.xml')
    [xml]$fish = Get-Content -Raw -LiteralPath $fishSettings
    $fishBlock = $fish.SettingsBlock.ModSettings
    if ($fishBlock.Class -ne 'PerformanceFish.FishSettings' -or
        $fishBlock.Version -ne '0.6.2.0' -or
        $fishBlock.'System.ReflectionCaching.MonoCustomAttrs.GetCustomAttributes'.
            enabled -ne 'false') {
        throw 'Performance Fish compatibility settings did not match the pinned profile.'
    }
    $fishHash = (Get-FileHash -LiteralPath $fishSettings -Algorithm SHA256).Hash
    if ($fishHash -ne
        'A2F1D6951BD8A3FA51FC12B83581F95357EFA41668BEA124C6491776396F18BC') {
        throw "Performance Fish compatibility settings hash changed: $fishHash"
    }

    "PASS: validated $($profiles.Count) modular companion compatibility profile(s)."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (!$resolvedTestRoot.StartsWith(
                $resolvedTemp,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean a test path outside the temp root: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
