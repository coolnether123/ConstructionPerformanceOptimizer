# RimWorld API compatibility matrix

The public package and `Dev` source support RimWorld 1.6. Historical API
adaptations are owned by matching `Support/<version>` branches. The cascade copies
their rebuilt DLL folders back to `Dev`, but never copies historical source into the
modern tree.

| RimWorld | Direct continuation | Adaptive cadence | Completion guard | Multiplayer | Evidence |
|---|---:|---:|---:|---:|---|
| Alpha 4 | Experimental | Not available in vanilla | Not needed | Not applicable | Original game assembly IL + target build/API audit |
| 0.13-0.17 | Experimental | Not available in vanilla | Not needed | Not tested | Original game assembly IL + target build/API audit |
| 0.18-0.19 | Experimental | Experimental | Experimental | Not tested | Original game assembly IL + target build/API audit |
| 1.0-1.4 | Experimental | Experimental | Experimental | Not tested | Reference assembly + target build/API audit |
| 1.5 | Experimental | Experimental | Experimental | Compile-ready, runtime unverified | RimWorld 1.5 reference assembly + MultiplayerAPI 0.5 + target build/API audit |
| 1.6 | Supported target | Supported target | Supported target | Supported | Installed assembly IL, compile/API audit, single-player smoke, and normal two-client construction tests |

## Important limits

- A successful reference build proves API compatibility, not runtime behavior.
  No runnable Alpha 4-1.5 game installations are present locally, so historical
  versions remain build/API verified until tested in their games.
- Every historical support branch is directly loadable: its root assembly matches
  its target-specific versioned DLL, its About metadata names that RimWorld version,
  and legacy branches remove unsupported modern load-folder metadata.
- Historical bootstrap and method-shape adaptations live only on their owning
  support branches. `Dev` receives rebuilt DLL folders, never historical source.
- The 1.5 branch references `Assembly-CSharp` 1.5 and MultiplayerAPI 0.5.0, matching
  the open-source Multiplayer `rw-1.5` branch. The API contract and build are verified,
  but no two-client 1.5 runtime claim is made without a runnable 1.5 installation.
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
