# 2.5D Grounding & Shadow Standard v1

The physical ground-contact root is authoritative. All migrated beach roots are Y=0; intended X/Z, body/Area world transforms, shape resources and collision layers/masks are preserved. Legacy visual root Y values were moved out of roots. Child collision/Area translations compensate root normalization, preserving their previous world placement; these are physics-preservation offsets, not visual tuning.

`ActorRoot -> WorldGroundPresentation.tscn -> VisualAnchor -> Sprite`

`WorldGroundPresentation -> ShadowAnchor -> WorldBlobShadow`

The component inherits root translation immediately and removes actor rotation/scale from the presentation basis. Sheet pixel padding registers the feet using Sprite3D.offset, with a shared 0.012 world lift. Shadow orientation is world identity, root-centered at a 0.006 ground lift. No per-facing/world shadow shifts, shadow billboarding, no_depth_test, or terrain-overdraw trick is used; character sprite billboarding is preserved. All actor scenes instantiate one shared presentation scene; future actors choose a profile and place their physical root on the ground.

## Complete beach sprite inventory and legacy offsets

Authored before values come from the untouched initial scene snapshot. Final collider bottoms come from the unchanged physics footprint (bounds of the runtime Shape3D debug mesh, transformed into world space). Multiple values mean multiple physical shapes. Ambient crabs have only sensors. See `grounding_before_inventory.json` for all 344 sheet-frame alpha bounds and original shape transforms; `grounding_after_inventory.json` includes applied runtime sprite alignment and every collider bottom, including interaction/terrain shapes. Collision bottoms were deliberately preserved, even when their existing volume extends below the nominal contact plane.

| Actor / item | Old root Y | Old sprite Y | Old frame offset Y (px) | Old scale XYZ | Physical shape bottom Y | Final frame offset Y (px) |
|---|---:|---:|---:|---|---|---:|
| World/BeachMerchantNPC | 0 | 0.07 | 11 | 1/1/1 | 0 | 22 |
| World/TripleTriadOpponentNPC | 0.074429 | 0 | 11 | 1/1/1 | -0.055571 | 21 |
| World/BeachCrafterNPC | 0.07 | -0.08 | 11 | 1/1/1 | -0.188853 | 22 |
| World/FishingCardMakerNPC | -0.12454 | 0.3 | -2 | 1/1/1 | -0.12454 | 29.5 |
| World/BeachGatheringCircuit/Driftwood01 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/Shell01 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/Seaweed01 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/Driftwood02 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/IronScrap01 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/SeaGlass01 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/IronScrap02 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/Shell02 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/Driftwood03 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/Seaweed02 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/CoastalHerb01 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/BeachGatheringCircuit/CoastalHerb02 | 0.006279 | -0.004 | 0 | 1/1/1 | No hard body | 0 |
| World/FishingMasterStillWaterNPC | 0 | 0.099701 | 11 | 1/1/1 | 0 | 23 |
| World/FishingMasterCurrentReaderNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterDepthReaderNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterStructureHunterNPC | 0.07 | 0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterLineFighterNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterDeepwaterVeteranNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterSurfaceAnglerNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterLandingGuideNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterWeatherWatcherNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterTideReaderNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterSignReaderNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterNatureGuideNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterDriftAnglerNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/FishingMasterGyosilNPC | 0.07 | -0.08 | 11 | 1/1/1 | 0.07 | 21 |
| World/BeachCritter | -0.055645 | 0 | 0 | 1/1/1 | No hard body | 5 |
| World/BeachCritter2 | -0.055645 | 0 | 0 | 1/1/1 | No hard body | 5 |
| Player/CharacterBody3D | 0 | -0.081947 | 11 | 1/1/1 | -0.002072 | 10 |

All final sprite-local positions are zero, scales are one, and root Y is zero. Shared visual lift is profile data, not per-instance transform. Merchant BagSearch (40x44) has zero bottom padding; Stand_Interest (40x56) has seven pixels. Card Maker (48x69) has five pixels; Still Water (44x54) has four. Crab (32x24) feet padding varies 6ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ8 pixels; fixed seven keeps stance stable. Ryu (192x160) uses fixed 70 pixels: standing 69ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ71, walking 67ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ73. Detached broken-rod artwork is deliberately not mistaken for the player's feet. Those small authored animation variations remain; the shadow never follows them. Smoke stays disabled.

## Migrated actors and reuse

- Player/Ryu; Beach Merchant; Beach Crafter; Card Maker; Triple Triad opponent.
- Fishing Masters: Still Water, Current Reader, Depth Reader, Structure Hunter, Line Fighter, Deepwater Veteran, Surface Angler, Landing Guide, Weather Watcher, Tide Reader, Sign Reader, Nature Guide, Drift Angler, Gyosil/reward NPC.
- Both crabs inherit BeachFishingCritter; their ambient sensor/no-hard-body policy is unchanged.
- All twelve circuit items: Driftwood01/02/03, Shell01/02, Seaweed01/02, IronScrap01/02, SeaGlass01, CoastalHerb01/02. Six inherited gathering scenes select sheet-size/yaw/shadow profiles; sprites remain flat and non-blocking.
- Native mesh grounded props: HarborLockbox, HarborRequestBoard, RegionalChampionshipRegistrar. Original mesh placement stays intact, shared component supplies contact shadows. Old roots were Y=0.07; root normalization preserves lockbox blocking body and all interaction Areas in world space.
- Regional ManilloTrader and ContextualItemShop inherit merchant presentation. DevelopmentFishingOutpost's Manillo root was Y=0.063; now Y=0 with body/Area world placement preserved. Ocean, Lake, River and Chiqua inherit the regional base. Removed its obsolete player-shadow override; retained the HUD's unrelated Shadow.png use.
- Excluded: bait/fish/waterborne visuals, airborne splash/thrash/smoke/effects, UI and particles. None is migrated to a contact shadow. The explicit excluded profile disables shadow if selected for a future presentation.

## Profile tuning

All dimensions are world units. Values omitted in resources use the exported Resource defaults below.

| Profile | Feet padding (px) | Pixel size | Width x depth | Opacity | Ground lift |
|---|---:|---:|---|---:|---:|
| card_maker | 5.0 | 0.01 | 0.36 x 0.36 | 0.65 | 0.006 |
| coastalherb | 0 | 0.0090 | 0.13 x 0.13 | 0.35 | 0.004 |
| crab | 7.0 | 0.012 | 0.14 x 0.14 | 0.60 | 0.006 |
| driftwood | 0 | 0.0100 | 0.13 x 0.13 | 0.35 | 0.004 |
| excluded | 0 | 0.01 | 0.30 x 0.30 | 0.65 | 0.006 |
| ground_item | 0 | 0.01 | 0.10 x 0.10 | 0.35 | 0.004 |
| harborlockbox | 0 | 0.01 | 0.24 x 0.24 | 0.40 | 0.006 |
| harborrequestboard | 0 | 0.01 | 0.14 x 0.14 | 0.40 | 0.006 |
| ironscrap | 0 | 0.0085 | 0.13 x 0.13 | 0.35 | 0.004 |
| merchant | 0.0 | 0.01 | 0.38 x 0.38 | 0.65 | 0.006 |
| player | 70.0 | 0.01 | 0.24 x 0.24 | 0.65 | 0.006 |
| regionalchampionshipregistrar | 0 | 0.01 | 0.28 x 0.28 | 0.40 | 0.006 |
| seaglass | 0 | 0.0095 | 0.08 x 0.08 | 0.35 | 0.004 |
| seaweed | 0 | 0.0090 | 0.13 x 0.13 | 0.35 | 0.004 |
| shell | 0 | 0.0050 | 0.08 x 0.08 | 0.35 | 0.004 |
| still_water | 4.0 | 0.01 | 0.32 x 0.32 | 0.65 | 0.006 |

Character profiles use shared 0.012 visual ground lift and unit scale. Ground items use 0.010 visual lift and profile-authored original yaw/pixel sizes. Merchant profile is reused by Crafter, Triple Triad, Gyosil, the other master families and regional traders. Default character footprint 0.30 x 0.30 / opacity 0.65; default critter profile 0.14 x 0.14 / 0.60; small item range 0.08ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ0.13 / 0.35; native prop range 0.14ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ0.28 / 0.40. Excluded profile disables the blob.

Shadow uses a horizontal PlaneMesh and simple radial alpha ShaderMaterial (smoothstep falloff, no lighting, normal depth testing). Compact circular footprint is projected naturally by perspective. Render priority -120 lies below ground item sprites (-110) and actors. No new art was generated. Old manually overridden world shadow materials and nodes were removed; existing shared Shadow.png remains for unrelated HUD/other art consumers.

## C input diagnosis and fix

Desktop used raw physical C routing. Mobile emitted a nested synthetic raw C and relied on the shell's unhandled-input callback to forward it, while its originating ScreenTouch was marked handled. This indirect/reentrant path was fragile. Physical Safari failure has been reported by the user; the exact Safari event-loss point was not captured, so this is the proven architectural defect, not a claim of device-level trace evidence.

`world_card_challenge` now binds desktop C and mobile C. Mobile touch emits a named InputEventAction, deferred until the original ScreenTouch dispatch finishes, updates Input's action held state, then pushes it directly into the gameplay SubViewport. WorldInteractionRouter and the Triple Triad NPC consume the same named action using the existing eligibility/modal/gameplay route. No direct match-opening bypass exists. First finger presses once; last releases once; focus loss clears it; queued rapid taps stay ordered. Other keys/touch mappings/layout are unchanged.

Native QA exercises independent stick/A/B/C fingers, two C fingers, rapid presses and focus cleanup. Actual browser QA dispatches DOM TouchEvent through canvas/Emscripten/Godot/MobileTouchControls, then opens the real challenge and match. This verifies browser integration, not physical iPhone Safari/isTrusted input. Physical phone action delivery was subsequently verified; see the physical iPhone evidence section below.

## Reproduction / QA commands

Use installed Godot 4.7.2, `--headless --path . --script res://scripts/qa/<name>.gd`; log files are in the Codex artifact directory.

| Command suffix | Result |
|---|---|
| world_grounding_standard_qa.gd | 847/847 after inherited location checks |
| beach_collision_qa.gd | 65 checks, 0 failures |
| world_actor_collision_qa.gd | 96/96; max passive displacement 0.0, epsilon 0.00001 |
| world_interaction_qa.gd | 93/93 |
| mobile_portrait_harness_qa.gd | 163/163 |
| fishing_fight_camera_tracking_qa.gd -- --regressions | Camera 120/120; full fishing 22950/22950 |
| Actual game startup during the above | Card Maker 10/10; Triple Triad 101/101; Fishing Presentation 10/10; System Stability 27/27; Fresh Save 55/55 |
| Rendered --rendering-method forward_plus/gl_compatibility --script world_grounding_standard_qa.gd -- --rendered --capture-dir=... | 851/851 each, including inherited-location assertions; four captures each |
| Linux-built MobileWebParityQA.tscn, disposable loopback origin | 24/24 with opt-in rendered Web orbits (20/20 core touch/routes); full authored Beach/Ocean/Lake/River/Chiqua travel |

Known provisional economy guardrails remain 22/24. No balances, guardrails or save schema changed. No new temporary production telemetry was added.

## Manual acceptance

Refresh Safari after Build complete; near the Triple Triad NPC, face him and tap C, then A to confirm. Repeat C while another finger holds movement and confirm release/focus loss leaves no stuck action. Physical touch delivery is verified by the user; opening a match after actual starter acquisition remains a manual check.

Visually review all eight Ryu directions, Card Maker walking/stopping/turning/dialogue, crab roaming, and small item contact. Desktop/Compatibility orbit captures show the stationary merchant's soft contact shadow centered and fixed across four camera headings; the transform assertions also show exact equality. Pixel art animation feet may vary by a few authored pixels; no per-frame shadow compensation was added. Browser shader rendering and scene reuse have been exercised, but final artistic approval on the actual phone belongs to the user.

## Rendered Web evidence and export

Four actual Web Compatibility camera headings reported the identical merchant shadow transform: identity basis, origin `(-1.949, 0.006, 0.609)`. Browser QA completed 24/24; no script errors or vanished migrated nodes appeared in the final run. The test fixture's opt-in `?shadow_orbits=1` runs these views; it is never selected as the shipping main scene. Desktop and Compatibility saved PNGs are under the Codex artifact directory `final-ground-forward_plus` and `final-ground-gl_compatibility`.

Final default command executed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

Result: Build complete. Linux Godot 4.7.2 generated PCK 31,266,244 bytes, project.binary 9,944 bytes with valid ECFG and checksums. Normal MobilePortraitHarness remains the mobile main scene. Existing HTTPS listener remains PID 2964 on 0.0.0.0:8060, unchanged. Only the disposable loopback QA server was stopped.

The final run still includes existing dedicated balance warnings (22/24) and text-path UID fallback warnings for fishing-current resources. These were not changed in this presentation/input pass; they are distinct from script errors or missing migrated presentation nodes. No claim that all historic warnings have been eliminated.

`git diff --check`: PASS after final whitespace cleanup.

## Physical iPhone input evidence and actual cause

The user supplied phone telemetry: C hits 2, named requests 1, forwarded 1, cards unlocked false, Area monitoring false, in range false. This proves physical Safari touch reached the named-action forwarding path. The actual reported no-response state is authored campaign gating in the phone's save, not loss of C input: card duels are locked, so `PlayableCampaignPresentationController._set_interaction_enabled()` disables the NPC's InteractionArea; the NPC consequently cannot report the player in range. The PC and mobile harness do not share the same save/progression state.

The browser/native unlocked tests acquire the real starter bundle before challenging the NPC. Fresh-save QA now explicitly proves C remains locked before that acquisition (163/163). No starter cards/unlocks were granted in production, no saves were copied, and no progression rule changed. Existing authored unlock: after 3â€“5 eligible Ocean Spot 2 catches, cast close to the water glint (0.95 world-unit trigger radius), then complete the catch to recover the Saltworn Card Case. Its acquisition unlocks the card NPC through the existing refresh path.

The original raw-key forwarding architecture was fragile; it was replaced by the shared named action, but it is not claimed as the proven cause of the phone's no-response state. Physical phone action delivery is now verified. A physical-phone match-opening test after the real case acquisition remains a manual acceptance check; native/browser unlocked challenge and match tests already pass.

Temporary phone diagnostic script, generated UID, and both harness hooks were removed after receiving this evidence. No debug overlay remains in the clean rebuild.

## Exact changed/new files

- `actors/BeachCrafterNPC.tscn`
- `actors/BeachFishingCritter.tscn`
- `actors/BeachGatheringCircuit.tscn`
- `actors/BeachGatheringNode3D.tscn`
- `actors/BeachMerchantNPC.tscn`
- `actors/ExplorationPlayer_V2.tscn`
- `actors/FishingCardMakerNPC.tscn`
- `actors/FishingMasterCurrentReaderNPC.tscn`
- `actors/FishingMasterDeepwaterVeteranNPC.tscn`
- `actors/FishingMasterDepthReaderNPC.tscn`
- `actors/FishingMasterDriftAnglerNPC.tscn`
- `actors/FishingMasterGyosilNPC.tscn`
- `actors/FishingMasterLandingGuideNPC.tscn`
- `actors/FishingMasterLineFighterNPC.tscn`
- `actors/FishingMasterNatureGuideNPC.tscn`
- `actors/FishingMasterSignReaderNPC.tscn`
- `actors/FishingMasterStillWaterNPC.tscn`
- `actors/FishingMasterStructureHunterNPC.tscn`
- `actors/FishingMasterSurfaceAnglerNPC.tscn`
- `actors/FishingMasterTideReaderNPC.tscn`
- `actors/FishingMasterWeatherWatcherNPC.tscn`
- `actors/FishingTestScene_V2.tscn`
- `actors/HarborLockbox.tscn`
- `actors/HarborRequestBoard.tscn`
- `actors/RegionalChampionshipRegistrar.tscn`
- `actors/TripleTriadOpponentNPC.tscn`
- `actors/WorldBlobShadow.tscn`
- `actors/WorldGroundPresentation.tscn`
- `actors/gathering/CoastalHerbGatherNode.tscn`
- `actors/gathering/DriftwoodGatherNode.tscn`
- `actors/gathering/IronScrapGatherNode.tscn`
- `actors/gathering/SeaGlassGatherNode.tscn`
- `actors/gathering/SeaweedGatherNode.tscn`
- `actors/gathering/ShellGatherNode.tscn`
- `actors/locations/DevelopmentFishingOutpost.tscn`
- `assets/shaders/world_contact_shadow.gdshader`
- `assets/shaders/world_contact_shadow.gdshader.uid`
- `data/presentation/card_maker.tres`
- `data/presentation/coastalherb.tres`
- `data/presentation/crab.tres`
- `data/presentation/driftwood.tres`
- `data/presentation/excluded.tres`
- `data/presentation/ground_item.tres`
- `data/presentation/harborlockbox.tres`
- `data/presentation/harborrequestboard.tres`
- `data/presentation/ironscrap.tres`
- `data/presentation/merchant.tres`
- `data/presentation/player.tres`
- `data/presentation/qa_physics_baseline.json`
- `data/presentation/regionalchampionshipregistrar.tres`
- `data/presentation/seaglass.tres`
- `data/presentation/seaweed.tres`
- `data/presentation/shell.tres`
- `data/presentation/still_water.tres`
- `docs/mobile/grounding_after_inventory.json`
- `docs/mobile/grounding_before_inventory.json`
- `docs/mobile/grounding_standard_v1.md`
- `export/index.html`
- `export/index.pck`
- `project.godot`
- `scripts/beach_crafter_npc.gd`
- `scripts/beach_gathering_node_3d.gd`
- `scripts/beach_merchant_npc.gd`
- `scripts/economy/fishing_card_maker_npc.gd`
- `scripts/mastery/fishing_master_lesson_npc_base.gd`
- `scripts/mastery/fishing_master_still_water_npc.gd`
- `scripts/mobile/mobile_portrait_harness.gd`
- `scripts/mobile/mobile_touch_controls.gd`
- `scripts/progression/fishing_reward_claim_npc_base.gd`
- `scripts/qa/beach_collision_qa.gd`
- `scripts/qa/mobile_portrait_harness_qa.gd`
- `scripts/qa/mobile_web_parity_qa.gd`
- `scripts/qa/world_character_shadow_qa.gd`
- `scripts/qa/world_grounding_inventory.gd`
- `scripts/qa/world_grounding_inventory.gd.uid`
- `scripts/qa/world_grounding_standard_qa.gd`
- `scripts/qa/world_grounding_standard_qa.gd.uid`
- `scripts/qa/world_interaction_qa.gd`
- `scripts/triple_triad/triple_triad_opponent_npc.gd`
- `scripts/world/beach_fishing_critter.gd`
- `scripts/world/ground_presentation.gd`
- `scripts/world/ground_presentation.gd.uid`
- `scripts/world/world_actor_presentation_profile.gd`
- `scripts/world/world_actor_presentation_profile.gd.uid`
- `scripts/world/world_blob_shadow.gd`
- `scripts/world_actor_presentation.gd`
- `scripts/world_interaction_router.gd`
