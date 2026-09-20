# Clean Checkpoint Playtest

Run the clean candidate in Godot and verify this sequence before making it the new baseline.

1. Project opens with no missing-resource errors.
2. F5 starts `FishingTestScene_V2` and debugger remains clean.
3. Exploration movement and quarter-turn camera still work.
4. Enter fishing at the zone; prep/aim camera transition works.
5. A/D aim works before and during power selection.
6. Cancel from power selection returns cleanly to aim.
7. Cast preview arc matches the actual cast landing point.
8. Bait lands, depth meter works, free reeling works.
9. Bite opportunity: Reel_Front + ripple; miss returns to normal fishing.
10. Direct/confirmed hit: Reel_Bite_Strong once, then fight state.
11. Fight controls: K, release K, A/D, W/S all feel as before.
12. Tension: safe zone remains green; release moves left; thrash can push right.
13. Hook Off and Line Break result flows still work.
14. Catch flow: Catch feedback, catch animation, frame slide, K dismiss.
15. Fish portrait/name/size/points display correctly.
16. Catch several Ocean 2 species, especially Sea Bass and Whale.
17. Whale/Spearfish now require their authored resistance rounds; confirm the longer endurance feels intentional.
18. No new warnings/errors appear after multiple fishing cycles.

If something feels different, note the exact step rather than tuning immediately. The cleanup intentionally fixed several hidden duplicate/unused code paths, so we want to distinguish a real regression from a previously masked bug.
