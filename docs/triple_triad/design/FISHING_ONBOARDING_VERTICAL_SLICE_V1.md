# Triple Triad Fishing Onboarding Vertical Slice V1

## End-to-end loop

A fresh save now has a complete non-UI gameplay path:

1. Triple Triad collection starts empty and the card game is locked.
2. Fishing commits a normal catch through `FishingCatchRepository`.
3. `TripleTriadFishingSalvageBridge` observes the committed transaction.
4. On the first eligible catch at `ocean_2`, the bridge resolves the one-shot
   `salvaged_card_case` acquisition bundle.
5. Triple Triad grants the ten starter cards, persists ownership, records the
   acquisition source, and unlocks card-player encounters.
6. The authored Beach Trader already placed in `FishingTestScene_V2` becomes
   challengeable.
7. K opens the real deck setup -> match -> result/reward flow.
8. Triple Triad checkpoints persistent collection/progression/encounter state and
   restores the SceneTree pause state on close, returning to exploration.

## Ownership boundaries

Fishing owns:
- catch transactions,
- the current fishing spot,
- later physical salvage presentation.

The integration bridge owns:
- deciding whether a committed fishing event is eligible to discover the
  onboarding case.

Triple Triad owns:
- bundle contents,
- one-shot claim persistence,
- card ownership,
- acquisition history,
- the card-game unlock,
- opponent availability,
- matches/rewards/progression.

This avoids making fishing know card IDs or making Triple Triad depend on fish
species/physics.

## Temporary V1 discovery rule

The first committed catch at `ocean_2` discovers the Saltworn Card Case with
100% certainty if the card game is still locked.

This is intentionally an onboarding placeholder, not a final loot table. When a
real fishable salvage-object encounter exists, call:

`TripleTriadGame.claim_salvaged_card_case(source_context)`

and disable/remove the automatic first-catch rule. No acquisition/save migration
is required.

## Existing saves

The ecosystem acquisition migration remains authoritative:
- an existing non-empty card collection is treated as already discovered;
- the starter case is marked satisfied by migration;
- no duplicate five-card bundle is granted.

## QA

Backend QA now includes a discovery-gate test:
- Beach Trader is unavailable while `card_game_unlocked == false`;
- the same Rank-1 opponent becomes available once discovery is true.

Expected backend QA count after this pass: 26.
