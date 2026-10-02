# FishingGame Architecture — Pass 2: Single Source of Truth

**Date:** 2026-09-27  
**Baseline:** Pass 1 clean candidate

## Goal

Remove fish/manual content ownership from `FishingMenu.gd`.

After Pass 2:

`FishData -> FishingJournalService -> FishingMenu`

The menu renders data. It no longer defines the fish database.

## FishData now owns

Every one of the 30 FishData resources now has:

- `species_id`
- `journal_name`
- `guide_effect`
- `guide_description`
- `journal_spot_ids`

`species_id` is the stable persistence identity. Current IDs deliberately match
the old resource filenames, so existing save keys remain compatible.

FishData also exposes:

- `get_stable_species_id()`
- `get_journal_name()`
- `accepts_lure_type()`
- `get_unavailable_lure_types()`

Lure compatibility therefore comes from the same `preferred_lure_types` /
`accepts_all_lures` data used by gameplay.

## FishingProgress

Persistence identity now prefers `FishData.species_id`.

The fallback-by-filename dependency has been removed from the normal path.

## FishingJournalService

The service now exposes to the Data menu:

- canonical display name
- portrait
- guide effect
- guide description
- average/king/points data
- unavailable lure types
- canonical source locations
- derived habitat types

Canonical BOF4 journal locations come from `FishData.journal_spot_ids`.

Gameplay spawn populations/weights remain separate implementation data. This is
intentional: spawn balancing can change without silently changing the manual.

`Saldine` is classified as `OCEAN` for journal habitat presentation. `Chamba`
remains `SPECIAL`.

## FishingMenu

Removed from the menu:

- 30-name `DATA_SPECIES_ORDER`
- 30 direct FishData preloads
- 30 guide-description entries
- lure compatibility table
- wave/habitat compatibility table
- spelling/alias normalizer

The Data list now uses the catalog order returned by `FishingJournalService`.

The lure and wave dark overlays are calculated from each journal entry.

## Blowfish correction

The previous project had a real conflict:

- menu/reference-from-game: Topper + Minnow unavailable
- FishData: Topper + Minnow preferred

The user directly verified the Data-menu state in the original game, so
Blowfish FishData is now:

- usable: Spinner, Winder, Frog, Worm
- unavailable/dark: Topper, Minnow

The reference JSON was updated to match.

## Spot-population discrepancy handling

Pass 1 found gameplay-spawn inconsistencies for Jellyfish, Bullcat and Martian
Squid.

Pass 2 does **not invent spawn weights** to force those gameplay resources to
match the source list.

Instead:

- canonical journal/source locations are now stored in FishData;
- the Data menu and habitat/wave icons use those canonical locations;
- authored gameplay spot populations remain a separate balancing concern.

A future population-balancing pass can reconcile spawn membership/weights
without affecting the manual architecture.

## Validation

Pass 2 statically verifies:

- 30 unique stable species IDs;
- all 30 FishData resources have journal/manual fields;
- new lure compatibility exactly matches the previously verified Data-menu UI;
- new wave/habitat compatibility exactly matches the previously verified UI;
- FishingMenu contains no direct FishData database/preloads;
- no missing quoted `res://` resources;
- no duplicate GDScript function declarations.

Godot is not installed in the audit environment, so an F5 smoke test remains
the final engine-level validation.
