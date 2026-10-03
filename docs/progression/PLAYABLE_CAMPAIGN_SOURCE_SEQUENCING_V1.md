# Playable Campaign Source Sequencing v1

## Purpose

Campaign milestone totals are now necessary but no longer sufficient on their own. The runtime campaign director also checks durable evidence that the player actually touched the intended systems before advancing the 0–12h campaign phase.

This keeps debug presets, seeded inventories, or unusually efficient play from skipping the learning sequence simply because the player already owns enough cards, rods, lures, or fish records.

## Runtime pacing evidence

### Learn Loop / ~1h

The player must satisfy the existing quantity targets and also:

- Defeat the Beach Trader at least once.
- Recover at least one card from `fishing_salvage:coast_shallows`.

This intentionally sends the player from fishing into the first duel and then back into fishing, proving that cards and fishing feed each other.

### Connected Systems / ~4h

The player must satisfy the existing quantity targets and use at least **one** of these routes:

- Make a card with the Card Maker.
- Turn in the Harbor Request.
- Open the Harbor Lockbox.

Only one route is required. The milestone is deliberately non-railroaded; the other two remain optional goals.

### Specialization / ~12h

The player must satisfy the existing quantity targets and also:

- Reach Duel Rank 2.
- Recover at least one card from `fishing_salvage:coast_deeper`.

This proves that the player has entered the deeper card/fishing loop rather than merely accumulating enough inventory through seeded or alternate sources.

## Why later authored opponents are not hard pacing gates yet

The canonical acquisition plan already contains Pier Apprentice, Gearwright, Dock Bruiser, and Marsh Keeper sources. Those pools remain valid design targets, but those opponents are not physically spawned in the current beach vertical slice.

Therefore they are **not** runtime activity requirements in this pass. Hard-gating the campaign director on them would make a legitimate current build impossible to complete. When World / Exploration Expansion introduces those opponents, this contract can be extended deliberately.

## Evidence source

The director remains read-only. It does not create new save files or mutate progression.

- Opponent evidence comes from existing encounter records.
- World-event evidence comes from the existing crash-safe reward ledger.
- Duel Rank comes from the existing player progression snapshot.
- Acquisition-source evidence is reconstructed from the existing card acquisition history and canonical world acquisition source card lists.
- QA presets / pre-history migration states may use current ownership as a compatibility fallback only when no acquisition history exists.

This means losing a previously acquired source card does not erase campaign evidence on a normal save.

## QA / Developer Guide

Shift+F10 now shows a **LIVE PACING EVIDENCE** section for the current target milestone. Each required activity and each alternative route is shown as complete/incomplete, so a playtester can see exactly why a milestone has or has not advanced.
