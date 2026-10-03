# Playable Campaign Loop V1 — Foundation

## Purpose

This is the first pass of the whole-game progression block. It does not add another gameplay subsystem. It establishes one canonical fresh-save contract so fishing, economy, crafting, Triple Triad and world rewards can now be developed against the same player journey.

## Canonical checkpoints

### Fresh save

- 100z
- 0 cards
- Wooden Rod + Straight lure
- card game locked

### ~15 minutes — First fishing trip

- player has actually fished before cards are introduced;
- first eligible coastal catch discovers the Saltworn Card Case;
- exactly five starter cards are granted;
- card duels become available.

### ~1 hour — Learn loop

- 7–10 cards;
- 4–6 fish species discovered;
- early fishing, selling, gathering, coastal card salvage and Beach Trader can all be understood without requiring every connected system yet.

### ~4 hours — Connected systems

- 15–22 cards;
- 9–12 fish species discovered;
- first rod upgrade and a useful lure set are affordable;
- prepared bait, Card Maker, harbor request, lockbox and gear progression have reasons to interact with the fishing economy.

### ~12 hours — Specialization

- 30–40 cards;
- 15–25 fish species discovered;
- deeper salvage and Rank-2 card play are active;
- enough tackle/economy choice exists for fishing-first, card-first and crafting-first play styles to diverge.

The checkpoint times are targets for pacing analysis, not timers that force unlocks.

## Simulator change

`EconomyProgressionSimulator` is now version 0.3 and starts from the actual new-save state rather than silently assuming the five starter cards already exist. The first 15-minute simulation step models the current temporary fishing discovery rule and records:

- `card_game_unlocked`
- `starter_case_discovered`
- five starter cards

The original H1/H4/H12 economy envelopes remain intact.

## Cross-system QA

`PlayableCampaignLoopQA` validates the authored progression plan against:

- the live 100z economy baseline;
- the real Wooden Rod / Straight starter loadout contract;
- the five-card Saltworn Card Case;
- the existing Triple Triad early-acquisition plan;
- the world acquisition source map;
- the physical Card Maker / Harbor Lockbox / Harbor Request Board / Regional Championship scenes;
- the deterministic balanced-player simulation.

It runs automatically in debug builds through `FishingSessionServices`.

## Next pass

The next campaign pass should turn this static contract into a runtime **Campaign Progression Director** that can answer one simple question at any point in a save: **what is the most useful next thing for the player to discover or do?** That state can then feed the later Campaign QA / Developer Guide and, eventually, unobtrusive player-facing guidance.
