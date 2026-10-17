# FishingGame — F5 desktop developer workflow (first acceptance pass)

**This is an implementation candidate, not visually accepted or Godot-runtime tested.**

## F5 startup

- Godot **F5** opens `res://actors/desktop/DesktopCompanion.tscn` rather than the bare fishing test scene.
- The project has a fixed, persistent developer save namespace: `FishingGame_DEV_F5`.
- The existing `Invoke-IsolatedDesktopAcceptance.ps1` and isolated QA tools continue to supply their own per-run save namespaces and launch scenes. They must restore the original `project.godot` on exit.
- The real/legacy story save is **not** copied or reset by this setup. The previous F5 namespace also is **not migrated** automatically.
- **Do not apply project.godot while an isolated launcher is running or when project.godot.qa.original.json exists.** Close the launcher and ensure it restored the project first.
- `project.godot` is a complete replacement from the supplied 2026-10-16 ZIP; preserve any later local project setting changes before replacing it. This is a development configuration, not approved export configuration.

## Test profiles

Press **Shift+F10** in F5, navigate with W/S, press K twice to confirm a *destructive* preset.

The original LIVE/Fresh Start/Card Discovery/Hour 1/Hour 4/Hour 12 presets remain unchanged for ordinary isolated runners. Only the named F5 developer namespace adds:

- **DEV / Cards Only**: 5 starting Triple Triad cards, starter fishing equipment.
- **DEV / All Fishing Tackle**: every authored rod/lure (including Master's Rod), a wallet and prepared bait, fresh card game.
- **DEV / Broad Unlock**: every authored rod/lure, full Triple Triad completion, 18 known QA fish species, wallet and prepared bait. This is NOT universal story/mastery completion; further world gates need developer mode.

These presets REPLACE current F5 progression/card state. **The default LIVE/current save row is read-only**; everyday catches/cards persist across F5 launches until an explicit preset is applied. For custom tweaks, use the existing F10 playtest menu: enable DEV and grant fishing/cards/wallet independently (in the isolated F5 save only). F10/Shift+F10 shortcuts otherwise behave as before.

## Scope/verification

- No camera behavior, shadow profiles, fishing rules, HUD graphics, pause logic or Triple Triad presentation were changed.
- The existing mobile test-namespace authorization policy is preserved, while dedicated F5 save becomes another authorized debug namespace.
- Source/config structure was reviewed. Actual Godot compilation, QA suites and interactive F5/save validation require Godot 4.7.2 on the user's Windows system; none are claimed passed here.
- **First manual acceptance:** F5 shows the Desktop Companion; Shift+F10 has the new developer entries; F10 grants fishing equipment in DEV mode; close and reopen F5 and confirm save persistence; the independent desktop launcher still gets a fresh sandbox.
- **Version control:** do not commit this change until it passes interactive acceptance. Existing `dev/qa-work` Git checkpoint stays available.
