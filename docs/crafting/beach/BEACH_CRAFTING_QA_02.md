# Beach Crafting Vertical Slice 0.2 — Automated QA

This pass adds a non-destructive debug QA suite for the beach crafting slice.

The suite runs automatically in debug builds when `FishingSessionServices`
initializes and previews every legal recipe/material combination. Previewing does
not consume materials, create lure instances, or write crafting saves.

## Tests

1. Catalog integrity and lure-template references.
2. All legal recipe combinations produce a valid preview.
3. Every legal material combination has a distinct three-property result; this
   catches ingredients that are paid for but do nothing because of score clamps.
4. All physical lure outputs remain within the supported fishing bounds.
5. Material identity: Driftwood raises buoyancy, Iron lowers it, Sea Glass raises
   attraction, and Seaweed Fibre raises handling.
6. Repeated material slots charge repeated quantity (`Shell + Shell = 2 Shell`).
7. Material inventory spending is atomic: failed recipes consume nothing and
   successful costs consume exactly once.

## Surface Lure correction

The original Surface Lure baseline Handling was +1. With Seaweed Fibre as both
core and accent, Handling reached the +4 clamp before the accent was applied, so
some legal combinations cost an extra material without changing the lure.

The baseline Handling is now 0. The Surface Lure still naturally favors
buoyancy, while all 18 legal material combinations produce distinct property
sets.

## Runtime output

Debug startup prints:

`Beach Crafting QA: 7/7 tests passed (36 recipe combinations).`

The report is also available through:

`FishingSessionServices.get_beach_crafting_qa_report()`

and can be rerun with:

`FishingSessionServices.run_beach_crafting_qa()`
