# RimWorld API compatibility matrix

The public package and `Dev` source support RimWorld 1.6. Historical API
adaptations are owned by matching `Support/<version>` branches. The cascade may
copy their rebuilt DLL folders back to `Dev`, but it does not copy historical
source into the modern tree.

| RimWorld | Direct continuation | Adaptive cadence | Completion guard | Multiplayer | Evidence |
|---|---:|---:|---:|---:|---|
| Alpha 4 | Experimental | Not available in vanilla | Not needed | Not applicable | Original game assembly IL + compile only |
| 0.13–0.17 | Experimental | Not available in vanilla | Not needed | Not tested | Original game assembly IL + compile only |
| 0.18–0.19 | Experimental | Experimental | Experimental | Not tested | Original game assembly IL + compile only |
| 1.0–1.5 | Experimental | Experimental | Experimental | Not tested | Compile surface only; runtime games are not installed locally |
| 1.6 | Supported target | Supported target | Supported target | Supported | Installed assembly IL, compile/API audit, single-player smoke, and normal two-client construction tests |

## Important limits

- A successful reference build proves API compatibility, not runtime behavior.
  Actual RimWorld 1.0–1.5 binaries are not installed on this machine, so those
  versions remain compile-surface verified until tested in their games.
- Alpha 4–0.19 are separate legacy engineering artifacts and are not advertised
  as equally supported public releases.
- Historical bootstrap and method-shape adaptations live only on their owning
  support branches.
- The cascade fails closed when a required compiler-generated method has zero or
  multiple matching call sites.
- The valid Multiplayer acceptance path is normal save hosting. The older replay
  path desynchronized even without CPO and is not used as compatibility evidence.
- The 1.6 control without CPO passed approximately 7,000 ticks. Two CPO-enabled
  release-candidate runs then completed 2,686 and 2,731 synchronized simulation
  ticks across three maps, reduced the construction fixture by 57 and 62
  blueprints, returned both peers to identical map clocks, and reported no desync.
- Runtime Harmony instrumentation is deliberately disabled in two-client
  acceptance runs. Dynamically repatching the construction methods while the
  harness is active can itself change the system under test and caused a
  diagnostic-only desync; synchronized fixture counts are used instead.
- The 1.6 API audit asserts the exact five-argument `CanConstruct` runtime shape
  so an optional-argument source call cannot hide a method mismatch.
