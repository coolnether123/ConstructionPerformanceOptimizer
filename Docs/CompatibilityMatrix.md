# RimWorld API compatibility matrix

The public package and `main` source support RimWorld 1.6. Historical API
adaptations are owned by matching `Support/<version>` branches. The cascade copies
their rebuilt DLL folders back to `main`, but never copies historical source into the
modern tree.

| RimWorld | Direct continuation | Adaptive cadence | Completion guard | Multiplayer | Evidence |
|---|---:|---:|---:|---:|---|
| 1.0 | Verified | Disabled for old Mono compatibility | Not used | Not supported | Installed 1.0.2559 runtime + clean quickstart with 50 colonists and 300 wall blueprints |
| 1.1-1.4 | Experimental | Experimental | Experimental | Not supported | Reference assembly + target build/API audit |
| 1.5 | Experimental | Experimental | Experimental | Verified on `Support/1.5` | Installed RimWorld 1.5 + MultiplayerAPI 0.5 + build/API audit + single-player and normal two-client construction tests |
| 1.6 | Supported target | Supported target | Supported target | Supported | Installed assembly IL, compile/API audit, single-player smoke, and normal two-client construction tests |

## Important limits

- A successful reference build proves API compatibility, not runtime behavior.
  No runnable 1.1-1.4 game installations are present locally, so those versions
  remain build/API verified until tested in their games.
- Every historical support branch is directly loadable: its root assembly matches
  its target-specific versioned DLL, its About metadata names that RimWorld version,
  and legacy branches remove unsupported modern load-folder metadata.
- Historical bootstrap and method-shape adaptations live only on their owning
  support branches. `main` receives rebuilt DLL folders, never historical source.
- The 1.0 branch targets the installed .NET 3.5 game runtime. Its modern fluent
  validation pair is excluded because RimWorld 1.0's Mono cannot load those types;
  the independent construction continuation remains enabled and runtime-verified.
- Multiplayer is supported only on RimWorld 1.5 and 1.6.
- The 1.5 branch references `Assembly-CSharp` 1.5 and MultiplayerAPI 0.5.0, matching
  the open-source Multiplayer `rw-1.5` branch. Its isolated 100-blueprint save passed
  single-player construction and normal two-client Multiplayer tests. The final
  CPO-enabled run advanced from tick 23 to 14,379, completed 37 constructions, and
  kept both peers synchronized with no desync. The CPO-free control also passed.
- The cascade fails closed when a required compiler-generated method has zero or
  multiple matching call sites.
- The valid Multiplayer acceptance path is normal save hosting. The older replay
  path desynchronized even without CPO and is not used as compatibility evidence.
- The 1.6 control without CPO passed approximately 7,000 ticks. Three CPO-enabled
  runs completed 2,686, 2,731, and 1,801 synchronized simulation ticks across three
  maps, reduced the construction fixture by 57, 62, and 23 blueprints, returned both
  peers to identical map clocks, and reported no desync. The final run used the exact
  1.0 release DLL with SHA-256
  `9D4FDA8F3F6EF33AE3D6F181BFDAB0E15D6B1A228C89F48A332E239471AC0EEA`.
- Runtime Harmony instrumentation is deliberately disabled in two-client acceptance
  runs. Dynamically repatching the construction methods while the harness is active
  can itself change the system under test and caused a diagnostic-only desync;
  synchronized fixture counts are used instead.
- The 1.6 API audit asserts the exact five-argument `CanConstruct` runtime shape so
  an optional-argument source call cannot hide a method mismatch.
