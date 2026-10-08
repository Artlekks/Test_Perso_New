# NPC directional presentation audit and fix

The yaw projection itself was correct (+Z South, clockwise eight-sector convention). The root bug was nearest-view tie-breaking: four diagonal views selected SE for South but NW for West, crossing front/back after a 90-degree camera turn. Exact E/W ties now prefer the front diagonal. Explicit authored views take precedence over aliases in one shared animation-map builder. Player input/directional code is unchanged.

Other causes: five-view sheets omitted west mirrors; 19 imported assets had only unlabelled pose mappings, although 17 contain usable additional views. Each sheet was visually reviewed using its actual extracted cells, rather than inferring directions from filenames or index order. Poses retain their original names, rectangles and 1-FPS timing; no walk cycles were invented. The two single-view imported strips remain single-view.

The Captain atlas also contained unused N/E/S standing rows. These are now exposed as six-frame idle animations at the existing 6 FPS. Existing diagonal idle/walk frames and rates are unchanged; smoke stays disabled. The side-view W uses the authored E row mirrored.

Rendered review also corrected Rod Angler pose_001's automatic stance metadata: the lowest alpha belonged to the lure rather than the body. Its reusable profile now anchors at body-feet x=19.5, bottom padding=3. A visible guide-edge bleed on that view remains a separate source/rendering cleanup item; clipping attempts were reverted when rendered evidence showed they did not fix it. Source PNGs and that frame's atlas rectangle are unchanged.

| Catalogue ID | Authored idle directions | Mirrored idle directions | Source / mapped cells |
|---|---|---|---|
| crab_small_01 | S, SE, E, NE, N, NW, W, SW | None | assets/animations/beach_fishing_crab_frames.tres |
| creature_green_01 | S, SE, E, NE, N | W, NW, SW | assets/animations/beach_fishing_critter_frames.tres |
| creature_red_01 | S, SE, E, NE, N | W, NW, SW | assets/animations/beach_fishing_critter_frames.tres |
| fisher_captain_01 | N, NE, E, SE, S, SW, NW | W | assets/animations/fishing_captain_frames.tres |
| merchant_heavy_01 | SE | None | assets/animations/beach_merchant_frames.tres |
| placeholder_14bf342a | NE, SE | NW, SW | NE=pose_000, SE=pose_001 |
| placeholder_21f7b2b2 | SE | None | SE=pose_000 |
| placeholder_3cb9da3b | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_43fb177f | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_4b58ab5e | SE, NE | NW, SW | SE=pose_000, NE=pose_001 |
| placeholder_68024840 | NE, SE | NW, SW | NE=pose_000, SE=pose_001 |
| placeholder_6d89ee8e | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_78f1768c | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_7d53dc6e | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_7f1b19bc | NE, SE | NW, SW | NE=pose_000, SE=pose_001 |
| placeholder_837b6a03 | NE, SE | NW, SW | NE=pose_000, SE=pose_006 |
| placeholder_8483df78 | NE, SE | NW, SW | NE=pose_000, SE=pose_031 |
| placeholder_85f413fb | NE, SE | NW, SW | NE=pose_000, SE=pose_014 |
| placeholder_8c3ae570 | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_9d2e2d78 | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_c3997e38 | E, SE, N, S, NE | W, NW, SW | E=pose_000, SE=pose_001, N=pose_002, S=pose_003, NE=pose_004 |
| placeholder_cac2bbc2 | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_d1282736 | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_d7c2eeb9 | NE, SE | NW, SW | NE=pose_000, SE=pose_001 |
| placeholder_e1466c4f | SE, NE | NW, SW | SE=pose_000, NE=pose_001 |
| placeholder_e5085f21 | NE | None | NE=pose_000 |
| placeholder_e8e1ac56 | S, SE, E, NE, N | W, NW, SW | S=pose_000, SE=pose_001, E=pose_002, NE=pose_003, N=pose_004 |
| placeholder_ea87e795 | E, NE, S, N | W, NW | E=pose_000, NE=pose_001, S=pose_002, N=pose_003 |
| placeholder_f3876069 | SE, NE | NW, SW | SE=pose_000, NE=pose_001 |
| placeholder_f8644d09 | N, S, E, SE, NE | W, NW, SW | N=pose_000, S=pose_001, E=pose_002, SE=pose_003, NE=pose_004 |
| placeholder_faacbedb | NE, SE | NW, SW | NE=pose_000, SE=pose_020 |
| placeholder_ff1c0303 | N, NE, E, SE, S | W, NW, SW | N=idle_n, NE=idle_ne, E=idle_e, SE=idle_se, S=idle_s |
| placeholder_ff6dba97_blue | NE, SE | NW, SW | NE=pose_000, SE=pose_004 |
| placeholder_ff6dba97_orange | NE, SE | NW, SW | NE=pose_008, SE=pose_012 |
| seated_crafter_01 | SE | None | assets/animations/beach_crafter_frames.tres |
| smoking_traveler_01 | SE | None | assets/animations/fishing_master_still_water_frames.tres |

One-view: merchant_heavy_01, placeholder_21f7b2b2, placeholder_e5085f21, seated_crafter_01, smoking_traveler_01. Their existing action animations are preserved. A one-view fallback never relabels its front artwork as a back view.

Walk/fly coverage: the ten five-standing-view imports retain their two authored NE/SE walk/fly strips, with explicit NW/SW mirrors. Captain walk uses four authored diagonal strips. Crab idle has eight authored directions and walk uses authored NW/SW with existing NE/SE mirrors. Mixed-action pose sheets retain static view selection without newly inferred action timing. Green/red small creatures use five authored idle views plus W/NW/SW mirrors.

Reviewed source sidecars and original catalogue manifest carry mappings for future ingestion. Regenerating actors is not required to apply the fix; the current profiles and Captain SpriteFrames were updated directly. `scan_source_batch.py --refresh-generated` is a destructive re-review operation for batch-generated manifests, so its explicit refresh option should not be used to overwrite these reviewed mappings.

Visual evidence: `build/direction-audit/*.png` contains source-cell contact sheets; `build/direction-shadow-captures/*.png` contains rendered catalogue actors. Focused QA rotates every catalogue actor and every placed world presentation through 360 degrees at 45-degree steps. Physical iPhone visual acceptance remains pending.
