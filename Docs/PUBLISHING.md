# Publishing checklist

## Before publishing

The public package and `Dev` source target RimWorld 1.6 only. Older API source remains
on `Support/<version>` branches, while historical DLL folders in `Dev` are engineering
artifacts and must not be copied into the Workshop archive.

1. Close RimWorld or ensure the focused package is not being copied over while
   the game is loading assemblies.
2. Confirm the version matches in:
   - `About/About.xml`
   - `Source/ConstructionPipelineOptimizer.csproj`
   - `CHANGELOG.md`
3. Run `Tools/Release.ps1` from PowerShell.
4. Confirm the script reports successful tests, build, package validation, ZIP
   creation, and SHA-256 creation.
5. Confirm the generated DLL hash matches the artifact named by the current benchmark
   and Workshop performance text. Any transpiler or runtime source change requires a new
   in-game smoke and an explicit evidence update before publication.
6. Use the generated runtime-only folder at
   `Releases/ConstructionPipelineOptimizer-<version>/ConstructionPipelineOptimizer`.
   The ZIP contains this same `ConstructionPipelineOptimizer` root.
7. Test that extracted package in a fresh RimWorld 1.6 process with Harmony and
   Tilled Soil.
8. Test a save containing ordinary material-bearing construction and zero-cost
   terrain construction.
9. Run the normal-save two-client smoke and verify identical paused simulation
   clocks, construction progress, and `desynced=False` on both peers. Do not enable
   the runtime Harmony construction probe in this acceptance run.
10. Verify `About.xml` and the Workshop description describe RimWorld 1.6
    Multiplayer support and require matching CPO versions/mod lists.
11. Verify the startup diagnostic reports the expected adaptive state. Test once with
   a controlled foreign owner on the exact validation predicate and confirm both the
   cadence and completion guard remain off while continuation stays independent.

## Steam Workshop

1. Close RimWorld. Do not leave both development and release copies under the
   game's `Mods` folder because duplicate package IDs make only one copy usable.
2. Temporarily repoint the existing local Mods junction from the project root to
   the generated runtime-only folder. Never upload the development project root;
   it contains source, tests, tools, and research that are intentionally absent
   from the public package.
3. Start RimWorld, select Construction Pipeline Optimizer, and use the Workshop
   upload action.
4. Set Harmony as a required Workshop item. `About.xml` dependency metadata does
   not create Steam's Required Items relationship automatically.
5. Paste `Docs/WorkshopDescription.txt` into the Workshop description.
6. Select tags such as `Mod`, `1.6`, and `Performance` if available.
7. Publish as unlisted first, subscribe to the Workshop copy, remove or rename
   the local development junction, and test the downloaded artifact.
8. Copy the generated `About/PublishedFileId.txt` from the runtime-only folder
   back into the project's `About` folder. Future release archives will then
   update the same Workshop item.
9. Restore the development junction only after the Workshop copy is removed from
   the local Mods folder, avoiding duplicate package IDs.
10. Add the final Workshop or repository URL to `About/About.xml` in the next
   patch release; do not publish a fabricated placeholder URL.

## Release acceptance

- No red errors during startup or construction.
- No duplicate package-ID warning.
- The legacy Construction Queue Optimizer is not active.
- Ordinary material-bearing frames complete normally with the adaptive pair both on
  and intentionally disabled.
- Zero-cost terrain completes successfully.
- Restart and Play Again/save-load behavior is unaffected.
- `rwmt.multiplayer` is not declared incompatible, `0MultiplayerAPI.dll` is present
  in the 1.6 runtime folder, and public descriptions match the verified support scope.
- The published ZIP checksum matches its `.sha256` sidecar.
