# Publishing checklist

## Before publishing

The public package targets RimWorld 1.6 only. Older API assemblies are compile/static
engineering fixtures and must not be copied into the Workshop archive.

1. Close RimWorld or ensure the focused package is not being copied over while
   the game is loading assemblies.
2. Confirm the version matches in:
   - `About/About.xml`
   - `Source/ConstructionPipelineOptimizer.csproj`
   - `CHANGELOG.md`
3. Run `Tools/Release.ps1` from PowerShell.
4. Confirm the script reports successful tests, build, package validation, ZIP
   creation, and SHA-256 creation.
5. Use the generated runtime-only folder at
   `Releases/ConstructionPipelineOptimizer-<version>/ConstructionPipelineOptimizer`.
   The ZIP contains this same `ConstructionPipelineOptimizer` root.
6. Test that extracted package in a fresh RimWorld 1.6 process with Harmony and
   Tilled Soil.
7. Test a save containing ordinary material-bearing construction and zero-cost
   terrain construction.
8. Run a two-client Multiplayer desync test with identical DLLs and load order.
9. Verify the startup diagnostic reports the expected adaptive state. Test once with
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
- Multiplayer remains synchronized in a real two-client run.
- If the two-client test has not been completed, every public description explicitly
  labels Multiplayer compatibility as expected but unverified.
- The published ZIP checksum matches its `.sha256` sidecar.
