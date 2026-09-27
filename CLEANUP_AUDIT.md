# FishingGame Cleanup / Refactor Audit — Pass 1

**Date:** 2026-09-27  
**Input:** `fishing_game_clean_candidate_FRESH (2)(1).zip`

## Scope

Pass 1 is deliberately conservative. It does **not** change the working
fishing feel, camera, casting, fight logic, menu geometry, or content model.

Goals:

1. remove automatic QA/save mutation from normal startup;
2. make full-tackle QA opt-in;
3. remove verified exact duplicate unreferenced UI exports;
4. refresh cleanup documentation;
5. produce a source-only test archive without `.git/` or `.godot/`.

## Production hygiene

### Automatic catch reset / catalog seed removed

Normal gameplay startup no longer:

- clears fish progress/inventory on a fresh `user://`;
- seeds one specimen of every fish;
- reads or creates the temporary catch-pipeline/manual-catalog marker files.

Removed from `scripts/fishing.gd`:

- `CATCH_PIPELINE_CLEAN_TEST_MARKER`
- `MANUAL_FULL_CATALOG_TEST_MARKER`
- `_prepare_clean_catch_pipeline_test_once()`
- `_seed_manual_full_catalog_test_once()`
- QA-only `CatchScoring` preload

The now-unused `FishingInventory.reset_fish_inventory_for_testing()` helper was
also removed.

Old marker files already present in `user://` are harmless because this build
does not read them.

### Equip full-catalog QA defaults OFF

`FishingMenu.show_full_tackle_catalog_for_testing` remains available for
explicit development testing, but now defaults to `false`.

Normal gameplay therefore does not show fake quantities or permit unowned
tackle unless a developer deliberately enables the QA option.

## Duplicate UI cleanup

Removed **28 exact duplicate PNG exports** plus their matching
`.import` sidecars where present.

Canonical live copies remain under:

- `assets/ui/fishing_menu/`
- `assets/ui/fishing_menu/lure_icons/`
- `assets/ui/fishing_menu/wave_icons/`
- `assets/ui/tech_bubbles/`

Editable source art (`.ase`, `.aseprite`, etc.) was preserved.

Model/source-art duplicate groups were intentionally left for a later art-source
cleanup pass.

## Packaging

The uploaded project contained approximately:

- `.git/`: **76.3 MiB**
- `.godot/`: **16.8 MiB**

The Pass 1 candidate excludes both. This does **not** mean you should delete
your working Git repository; the supplied ZIP is a source/test candidate.

## Current source metrics

Before Pass 1, excluding `.git/.godot`:

- files: **752**
- size: **5.17 MiB**

After duplicate removal / QA cleanup, before doc rewrite:

- files: **696**
- size: **5.11 MiB**

BOF4 content remains:

- fish: **30**
- lures: **20**
- rods: **6**
- fishing spots: **11**

## Static validation

- missing quoted `res://` resources: **0**
- removed files still referenced: **0**
- duplicate UI/sprite image groups remaining: **0**
- GDScript files with duplicate function declarations: **0**
- duplicate `class_name` declarations: **0**

Godot itself is not installed in this audit environment, so final engine
validation is still: open this Pass 1 candidate and press F5.

## Deferred to Pass 2+

Not changed here:

- fish/manual data duplicated in `FishingMenu`;
- stable `species_id` normalization;
- Blowfish lure-compatibility source conflict;
- Jellyfish/Bullcat/Martian Squid spot-data reconciliation;
- `FishingMenu.gd` split;
- `fishing.gd` split;
- service ownership;
- catch/inventory transactional persistence;
- fish-shadow bait lookup optimization;
- camera projection optimization.


## Pass 2 completion

Single-source-of-truth refactor completed.

Fish identity/manual/lure-compatibility/source-location data now flows from
FishData through FishingJournalService into FishingMenu.

See `PASS2_SINGLE_SOURCE.md` for the implementation boundary and validation.


## Pass 3 completion

FishingMenu page implementations have been split into Equip, Data, Hints and
Help controller modules using a conservative delegation boundary.

Scene structure and gameplay/camera scripts were frozen during this pass.

See `PASS3_MODULAR_MENU.md`.


## Pass 4 completion

Persistent fishing services now live under `FishingSessionServices`, and the
QA/debug subsystem lives under `FishingDebugController`.

The main fishing controller remains responsible for gameplay phase orchestration
only plus presentation coordination that is tightly coupled to those phases.

See `PASS4_SYSTEM_OWNERSHIP.md`.


## Pass 5 completion

Safe performance polish completed. Ambient fish shadows now share a cached bait
reference and the hidden menu no longer repaints its Time label every frame.

Camera optimization was deliberately deferred to the post-refactor regression
phase because camera framing has an open behavioral issue.

See `PASS5_PERFORMANCE.md` and `POST_REFACTOR_REGRESSION_QUEUE.md`.
