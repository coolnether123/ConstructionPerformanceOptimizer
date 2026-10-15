# Construction Performance Optimizer Agent Guide

Own only this repository. It owns CPO source, tests, benchmarks, compatibility
evidence, version cascade, and release payloads. Preserve benchmark inputs and
owner work; never overwrite a baseline save or capture.

`About\About.xml`, `LoadFolders.xml`, Git branches, and
`Tools\CascadeManifest.json` together define supported versions. Do not invent
support branches or restore archived payloads.

Read `README.md`, `Docs\Architecture.md`, and the affected benchmark protocol.
Use `Tools\Build.ps1` for a focused build and
`Tools\Build-AllVersions.ps1` with the reviewed cascade manifest for matrix
work. Treat `Tests`, `Tools\Test-*.ps1`, and
`Tools\Validate-Package.ps1` as the current
verification inventory.

Use the runtime workflow in `H:\Dev\RimWorld\AGENTS.md`. Transpiler safety,
foreign Harmony ownership, performance, and multiplayer claims require their
specific runtime or paired-evidence checks; compilation alone is insufficient.
