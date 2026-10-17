FISHINGGAME — STABILIZATION GATE 02 (CANDIDATE / NOT ACCEPTED)
Input baseline: FishingGame_QA_Work_STABILIZATION_20261016_154704.zip
Apply only to: C:\Users\Alucard7th\Documents\FishingGame\FishingGame_QA_Work
Keep the October 16 snapshot ZIP untouched. Do not apply to original or frozen audit.

PURPOSE:
- Floating window vertically expands actual gameplay world while fishing.
- The free-lure solver projects onto a constant 960x480 camera reference lens in DesktopCompanion, independent of displayed viewport height/FOV.
- Stop using the camera/HUD's live resize-dependent screen-region callback as a physics boundary.
- Late HUD water-safe helper no longer mutates the physical bait.
- If free-reel D's entire steering candidate set fails near shore, fall back to one bounded, shore-clamped INWARD step instead of freezing the lure. Preserve A/D preferred arcs whenever legal.
- Docked views and native/mobile projection defaults remain unchanged by the new reference remapping.

CONTENTS / ORIGINAL FILENAMES:
 scripts/ui/seaside_shell_layout.gd
 scripts/bait_V2.gd
 scripts/fishing_screen_water_bounds.gd
 scripts/qa/desktop_fishing_resize_contract_qa.gd       (replaces Gate 01 QA: its locked-height rule was wrong)
 scripts/qa/fishing_physics_projection_gate_02_qa.gd     (new)

NOT IN SCOPE: Adjusting HUD positions, new camera yaw policy, changing rod stats, fish combat, splash art, or RPG systems.
KNOWN RISK: A normal screen-safe region may not contain the physical shore landing point. The fallback prioritizes physical progress; a subsequent camera/presentation gate must ensure the bait never visually intersects a HUD panel. Do not accept this as final if that is visible in F5.

HOW TO TEST:
1. Close running F5. Extract this ZIP into the active QA_Work folder, preserving paths.
2. Run these TWO Godot headless QAs using your installed 4.7.2 binary:
   --headless --path <QA_Work> --script res://scripts/qa/desktop_fishing_resize_contract_qa.gd
   --headless --path <QA_Work> --script res://scripts/qa/fishing_physics_projection_gate_02_qa.gd
3. If both pass, F5 long Master Rod cast while FLOATING, hold D all the way inward,
   resize from normal to tall and back, then repeat A, D and K; check bait,
   camera, water splashes, HUD overlap, and debugger.
4. If any red error or HUD overlap occurs: FAIL Gate 02, STOP and report it.

ROLLBACK: Restore these three production scripts from the preserved source
snapshot ZIP, then re-apply Gate 01 layout ONLY if returning to the Gate 01
experimental state. (No Git commits are made by this ZIP.)

VERIFICATION: Offline independent perspective math was checked at 3 widths x
5 heights x 3 screen points. Godot binary unavailable in this environment;
compile/runtime/visual behavior UNVERIFIED until user runs the test.
