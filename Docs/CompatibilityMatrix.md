# RimWorld API compatibility matrix

The public package supports RimWorld 1.6. The repository also compiles engineering
fixtures against older APIs; those results are intentionally separated from public
runtime support.

| RimWorld | Direct zero-cost continuation | Adaptive broad cadence | Final completion guard | Evidence |
|---|---:|---:|---:|---|
| Alpha 4 | Experimental | Not available in vanilla | Not needed | Original game assembly IL + compile only |
| 0.13–0.17 | Experimental | Not available in vanilla | Not needed | Original game assembly IL + compile only |
| 0.18–0.19 | Experimental | Experimental | Experimental | Original game assembly IL + compile only |
| 1.0–1.5 | Experimental | Experimental | Experimental | Compile surface only; runtime assemblies are not installed locally |
| 1.6 | Supported target | Supported target | Supported target | Installed game assembly IL + compile + in-game validation |

## Important limits

- A successful reference build proves API compatibility, not runtime behavior.
  Actual RimWorld 1.0–1.5 binaries are not installed on this machine, so those
  six versions remain compile-surface verified until tested in their games.
- Alpha 4-0.19 are separate legacy engineering artifacts and are not advertised as
  equally supported public releases.
- Alpha 4 uses a small XML `Def` bootstrap because that release predates the
  modern static-constructor startup attribute.
- RimWorld 0.13–0.16 use a two-argument `CanConstruct`; 0.17–0.18 use three;
  0.19-1.4 use four, and 1.5-1.6 use five. The validation feature begins only
  in 0.18 because earlier
  `FinishFrame` drivers do not contain the repeated validation predicate.
- The cascade fails closed when a required compiler-generated method has zero
  or multiple matching call sites.
- The 1.6 benchmark is not a two-client Multiplayer synchronization test. Multiplayer
  remains runtime-unverified for this adaptive revision.
- RimWorld 1.5 and 1.6 use the five-argument `CanConstruct` overload in the generated
  fail predicate. The API audit asserts this exact shape so an optional-argument
  source call cannot be mistaken for a four-argument runtime method.
