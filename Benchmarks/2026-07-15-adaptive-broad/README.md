# Adaptive broad-validation benchmark

This benchmark compares three construction-only states against the same paused
three-map colony fixture:

- `baseline`: no construction optimizer;
- `legacy-broad`: the preserved pre-redesign DLL with all-frame validation cadence;
- `current-adaptive`: the current `Dev` build. It installs the broad cadence and
  targeted completion guard when the exact validation predicate has no foreign
  Harmony owner; otherwise the pair stays off. Downstream patched methods remain
  composed and are reported.

Better Work Tab and the older all-in-one Construction Queue Optimizer are removed
from every benchmark profile. Dubs Performance Analyzer and RimWorld Agent remain
enabled for measurement only.

The historic frozen fixture contains 1,344 construction blueprints: 1,122 are
Tilled Soil. It does **not** contain 12,000 queued tiles. Any 12,000-tile stress
fixture must therefore be generated and saved under a new name; the frozen source
must never be overwritten.

The completed comparison used the derived fixture
`SGTLMathews Story Colony - SP 12000 Tilled Soil Stress 1.6.4871` with exactly
12,000 Tilled Soil blueprints. See `REPORT.md` for its hash, protocol, exclusions,
statistics, raw-result locations, and compatibility evidence.

Run one arm from PowerShell after closing RimWorld:

```powershell
$save = 'SGTLMathews Story Colony - SP 12000 Tilled Soil Stress 1.6.4871'
& .\Invoke-Variant.ps1 -Variant baseline -Runs 3 -DurationSeconds 30 -SaveName $save
& .\Invoke-Variant.ps1 -Variant legacy-broad -Runs 3 -DurationSeconds 30 -SaveName $save
& .\Invoke-Variant.ps1 -Variant current-adaptive -Runs 3 -DurationSeconds 30 -SaveName $save
```

The script restores the user's pre-run `ModsConfig.xml` in `finally`, even when a
launch or agent command fails. Raw reports, copied player logs, mod profiles, and
hash manifests are written to a timestamped folder under `Results`.
