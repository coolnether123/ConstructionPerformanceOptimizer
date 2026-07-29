[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigRoot
)

$ErrorActionPreference = 'Stop'

$resolvedConfigRoot = [IO.Path]::GetFullPath($ConfigRoot)
New-Item -ItemType Directory -Force -Path $resolvedConfigRoot | Out-Null
$settingsPath = Join-Path $resolvedConfigRoot (
    'Mod_companion-bs.performance_PerformanceFishMod.xml')

$writerSettings = [Xml.XmlWriterSettings]::new()
$writerSettings.Indent = $true
$writerSettings.Encoding = [Text.UTF8Encoding]::new($false)
$writer = [Xml.XmlWriter]::Create($settingsPath, $writerSettings)
try {
    $writer.WriteStartDocument()
    $writer.WriteStartElement('SettingsBlock')
    $writer.WriteStartElement('ModSettings')
    $writer.WriteAttributeString('Class', 'PerformanceFish.FishSettings')
    $writer.WriteElementString('Version', '0.6.2.0')
    $writer.WriteStartElement(
        'System.ReflectionCaching.MonoCustomAttrs.GetCustomAttributes')
    $writer.WriteElementString('enabled', 'false')
    $writer.WriteEndElement()
    $writer.WriteEndElement()
    $writer.WriteEndElement()
    $writer.WriteEndDocument()
}
finally {
    $writer.Dispose()
}

Write-Output $settingsPath
