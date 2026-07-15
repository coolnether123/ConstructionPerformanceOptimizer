# RimWorld API compatibility matrix

The build supports the construction APIs available locally from Alpha 4 through
RimWorld 1.6. Support is intentionally capability-based rather than pretending
that every release has the same vanilla hooks.

| RimWorld | Direct zero-cost continuation | Validation cadence | Final completion guard | Evidence |
|---|---:|---:|---:|---|
| Alpha 4 | Yes | Not available in vanilla | Not needed | Original game assembly IL + compile |
| 0.13–0.17 | Yes | Not available in vanilla | Not needed | Original game assembly IL + compile |
| 0.18–0.19 | Yes | Yes | Yes | Original game assembly IL + compile |
| 1.0–1.5 | Yes | Yes | Yes | Version reference compile; runtime IL is not installed locally |
| 1.6 | Yes | Yes | Yes | Installed game assembly IL + compile |

## Important limits

- A successful reference build proves API compatibility, not runtime behavior.
  Actual RimWorld 1.0–1.5 binaries are not installed on this machine, so those
  six versions remain compile-surface verified until tested in their games.
- Alpha 4 uses a small XML `Def` bootstrap because that release predates the
  modern static-constructor startup attribute.
- RimWorld 0.13–0.16 use a two-argument `CanConstruct`; 0.17–0.18 use three;
  0.19+ use four. The validation feature begins only in 0.18 because earlier
  `FinishFrame` drivers do not contain the repeated validation predicate.
- The cascade fails closed when a required compiler-generated method has zero
  or multiple matching call sites.
