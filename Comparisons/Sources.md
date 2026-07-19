# Comparison sources

Acquired on 2026-07-13. External source was cloned or decompiled only for
interoperability and overlap analysis; no external implementation was copied into
Construction Performance Optimizer.

| Project | Evidence | Revision / artifact |
|---|---|---|
| Performance Optimizer | Official source: https://github.com/Taranchuk/PerformanceOptimizer | `cbea30c94a9076e0ceb8e2b2bebdf9f663e8bd57` (MIT) |
| Yet another Optimizer | Official source: https://github.com/szszss/YetAnotherOptimizer | `ab60621f071fbee3e4f1a92bb163c2760b8605bf` (MIT) |
| Performance Fish | Official upstream: https://github.com/bbradson/Performance-Fish | `a99972001e02d553a738611726cd9577ff41f86e` (MPL-2.0; upstream does not currently contain a live 1.6 implementation) |
| Performance Fish 1.6 port | Community 1.6 branch: https://github.com/localavaster/Performance-Fish/tree/rimworld-1.6 | `7d96ecdb1dd6904c210dab6c290583add7fda5b4` (MPL-2.0) |
| MissileGirl | Official source: https://github.com/ViralReaction/MissileGirl | `3170983d90e726f47f105dd2f426af8c3ce60e29` |
| Turret Performance Tweaks | Steam Workshop item `3621644930`; no source link was published | `TurretPerformanceTweaks.dll`, SHA-256 `6E5E604DF9F736EB7887642AD0BF07082C87F07C718CC6CF8B22E5E7054E86B2` |
| Hard RimWorld Optimization | Steam Workshop item `3668058976`; no source link was published | `MyRimWorldMod.dll`, SHA-256 `AC4109D756F313528BC8805671E386A82A2AE3B605A4C130586D46F2624F67FA` |

Local evidence:

- Source clones: `A:\Dev\GitHub\RimWorld-Optimization-Comparisons`
- Workshop packages: `A:\Dev\Downloads\RimWorld-Optimization-Workshop\steamapps\workshop\content\294100`
- Decompiled comparison output: `A:\Dev\Downloads\RimWorld-Optimization-Workshop\Decompiled`

The Workshop-only assemblies were decompiled with ILSpy 9.1.0.7988. Those
decompilations are evidence, not redistributable project source.
