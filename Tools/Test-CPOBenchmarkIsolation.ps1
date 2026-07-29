[CmdletBinding()]
param(
    [string]$RimWorldPath =
        'A:\Dev\BenchmarkGames\RimWorld-ConstructionPerformanceOptimizer-1.6\RimWorldCPOIsolated.exe',

    [string]$DataRoot =
        'A:\Dev\BenchmarkGames\RimWorld-ConstructionPerformanceOptimizer-1.6\BenchmarkData',

    [switch]$PerformanceRun
)

$ErrorActionPreference = 'Stop'

$expectedRoot = [IO.Path]::GetFullPath(
    'A:\Dev\BenchmarkGames\RimWorld-ConstructionPerformanceOptimizer-1.6')
$expectedExecutable = Join-Path $expectedRoot 'RimWorldCPOIsolated.exe'
$expectedDataRoot = Join-Path $expectedRoot 'BenchmarkData'
$expectedCanonicalExecutable = Join-Path $expectedRoot 'RimWorldWin64.exe'
$resolvedExecutable = [IO.Path]::GetFullPath($RimWorldPath)
$resolvedDataRoot = [IO.Path]::GetFullPath($DataRoot)

if (!$resolvedExecutable.Equals(
        $expectedExecutable,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Only the isolated CPO executable is authorized: $expectedExecutable"
}
if (!$resolvedDataRoot.Equals(
        $expectedDataRoot,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Only the isolated CPO data root is authorized: $expectedDataRoot"
}

$modsRoot = Join-Path $expectedRoot 'Mods'
$dataLink = Join-Path $expectedRoot 'RimWorldCPOIsolated_Data'
foreach ($requiredPath in @(
        $expectedExecutable,
        $expectedCanonicalExecutable,
        $expectedDataRoot,
        $modsRoot,
        $dataLink)) {
    if (!(Test-Path -LiteralPath $requiredPath)) {
        throw "Required isolated benchmark path not found: $requiredPath"
    }
}

foreach ($realDirectory in @($expectedDataRoot, $modsRoot)) {
    $item = Get-Item -LiteralPath $realDirectory -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Writable benchmark path must not be a link or junction: $realDirectory"
    }
}

$dataLinkItem = Get-Item -LiteralPath $dataLink -Force
$targets = @($dataLinkItem.Target)
if ($targets.Count -ne 1) {
    throw "The isolated executable's _Data link must have exactly one target."
}
$resolvedTarget = [IO.Path]::GetFullPath($targets[0])
$rootPrefix = $expectedRoot.TrimEnd('\') + '\'
if (!$resolvedTarget.StartsWith(
        $rootPrefix,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "The isolated executable's _Data link escapes its game copy."
}

$executableHash =
    (Get-FileHash -LiteralPath $expectedExecutable -Algorithm SHA256).Hash
$canonicalHash =
    (Get-FileHash -LiteralPath $expectedCanonicalExecutable -Algorithm SHA256).Hash
if ($canonicalHash -cne $executableHash) {
    throw "Prepatcher's canonical restart player does not match the isolated player."
}

if ($PerformanceRun) {
    $runningGames = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -like 'RimWorld*.exe' -or
                ($_.ExecutablePath -and
                    [IO.Path]::GetFileName($_.ExecutablePath) -like 'RimWorld*.exe')
            })
    if ($runningGames.Count -gt 0) {
        $details = $runningGames |
            ForEach-Object { "$($_.ProcessId):$($_.Name):$($_.ExecutablePath)" }
        throw "Close every RimWorld process before a measured trial: $($details -join '; ')"
    }
}

[pscustomobject]@{
    Status = 'isolated'
    Root = $expectedRoot
    Executable = $expectedExecutable
    ExecutableSha256 = $executableHash
    CanonicalRestartExecutable = $expectedCanonicalExecutable
    CanonicalRestartSha256 = $canonicalHash
    DataRoot = $expectedDataRoot
    ModsRoot = $modsRoot
    DataLinkTarget = $resolvedTarget
    PerformanceProcessCheck = [bool]$PerformanceRun
}
