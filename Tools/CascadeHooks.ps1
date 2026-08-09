param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('after-merge', 'before-stage')]
    [string]$Phase,
    [Parameter(Mandatory = $true)][string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$payloadName = 'Construction Performance Optimizer.dll'

function Set-CpoBranchMetadata
{
    param([Parameter(Mandatory = $true)][string]$TargetVersion)

    $aboutPath = Join-Path $projectRoot 'About\About.xml'
    $loadFoldersPath = Join-Path $projectRoot 'LoadFolders.xml'
    $multiplayerText = if ($TargetVersion -eq '1.5')
    {
        'Includes the RimWorld 1.5 Multiplayer API 0.5 bridge. Every peer must use the same CPO build and mod list.'
    }
    else
    {
        'This build supports single-player. Multiplayer support begins with the separate RimWorld 1.5 build.'
    }
    $modVersionElement = if ($TargetVersion -eq '1.4' -or $TargetVersion -eq '1.5')
    {
        '  <modVersion>1.0.0</modVersion>'
    }
    else
    {
        ''
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<ModMetaData>
  <name>Construction Performance Optimizer</name>
  <author>Coolnether123</author>
  <packageId>coolnether123.constructionperformanceoptimizer</packageId>
$modVersionElement
  <supportedVersions>
    <li>$TargetVersion</li>
  </supportedVersions>
  <description><![CDATA[Helps construction-heavy colonies run more smoothly by reducing repeated construction work while preserving normal RimWorld behavior.

Version 1.0. The branch is compiled against RimWorld $TargetVersion. $multiplayerText

Requires Harmony. No settings or save data.]]></description>
  <modDependencies>
    <li>
      <packageId>brrainz.harmony</packageId>
      <displayName>Harmony</displayName>
      <steamWorkshopUrl>steam://url/CommunityFilePage/2009463077</steamWorkshopUrl>
      <downloadUrl>https://github.com/pardeike/HarmonyRimWorld/releases/latest</downloadUrl>
    </li>
  </modDependencies>
  <loadAfter>
    <li>brrainz.harmony</li>
    <li>ludeon.rimworld</li>
    <li>gt.sam.tilledsoil</li>
  </loadAfter>
  <incompatibleWith>
    <li>coolnether123.constructionqueueoptimizer</li>
  </incompatibleWith>
</ModMetaData>
"@
    [System.IO.File]::WriteAllText($aboutPath, $xml)

    $loadFolders = @"
<?xml version="1.0" encoding="utf-8"?>
<loadFolders>
  <v$TargetVersion>
    <li>/</li>
  </v$TargetVersion>
</loadFolders>
"@
    [System.IO.File]::WriteAllText($loadFoldersPath, $loadFolders)
}

function Sync-CpoBranchPayload
{
    param([Parameter(Mandatory = $true)][string]$TargetVersion)

    $versionedRoot = Join-Path $projectRoot "$TargetVersion\Assemblies"
    $versionedPayload = Join-Path $versionedRoot $payloadName
    if (-not (Test-Path -LiteralPath $versionedPayload -PathType Leaf))
    {
        throw "Built CPO payload is missing: $versionedPayload"
    }

    $rootAssemblies = Join-Path $projectRoot 'Assemblies'
    New-Item -ItemType Directory -Force -Path $rootAssemblies | Out-Null
    Copy-Item -LiteralPath $versionedPayload `
        -Destination (Join-Path $rootAssemblies $payloadName) `
        -Force

    $rootMultiplayerApi = Join-Path $rootAssemblies '0MultiplayerAPI.dll'
    $versionedMultiplayerApi = Join-Path $versionedRoot '0MultiplayerAPI.dll'
    if (Test-Path -LiteralPath $versionedMultiplayerApi -PathType Leaf)
    {
        Copy-Item -LiteralPath $versionedMultiplayerApi `
            -Destination $rootMultiplayerApi `
            -Force
    }
    elseif (Test-Path -LiteralPath $rootMultiplayerApi -PathType Leaf)
    {
        Remove-Item -LiteralPath $rootMultiplayerApi -Force
    }

    Set-CpoBranchMetadata -TargetVersion $TargetVersion
}

switch ($Phase)
{
    'after-merge' { Set-CpoBranchMetadata -TargetVersion $Version }
    'before-stage' { Sync-CpoBranchPayload -TargetVersion $Version }
}
