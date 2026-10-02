# FishingGame Architecture — Pass 3: Modular Menu Controllers

**Date:** 2026-09-27  
**Baseline:** Pass 2 single-source candidate

## Goal

Break the 2,455-line `FishingMenu.gd` monolith into page-specific modules
without changing the scene hierarchy, pixel calibration, transitions, menu
inputs, fishing gameplay, camera behavior, or data ownership established in
Pass 2.

## Strategy: conservative strangler refactor

`FishingMenu` remains the coordinator and temporary state owner.

The implementation of page behavior is now separated into:

- `fishing_menu_equip_controller.gd`
- `fishing_menu_data_controller.gd`
- `fishing_menu_hints_controller.gd`
- `fishing_menu_help_controller.gd`

The old private method names still exist in `FishingMenu`, but they are thin
delegation wrappers. This deliberately keeps every pre-existing internal call
site intact while moving the implementation out of the monolith.

This is safer than simultaneously changing state ownership, scene scripts,
selector hierarchy, and behavior in a single pass.

## Result

`FishingMenu.gd`:

- before Pass 3: **2455 lines**
- after Pass 3: **1737 lines**

Controller modules:

- `fishing_menu_equip_controller.gd`: 504 lines / 19 extracted functions
- `fishing_menu_data_controller.gd`: 350 lines / 14 extracted functions
- `fishing_menu_hints_controller.gd`: 154 lines / 10 extracted functions
- `fishing_menu_help_controller.gd`: 33 lines / 2 extracted functions

The coordinator still owns:

- open/close/pause lifecycle;
- page routing;
- top-level page transitions;
- Exit confirmation;
- shared selector orchestration;
- service references;
- current page state fields.

Page-specific implementations now live outside the coordinator.

## Behavior intentionally frozen

Pass 3 does not change:

- `FishingMenu.tscn`;
- any UI texture/coordinate;
- selector calibration;
- navigation mappings;
- Data detail animation;
- Equip/Hints behavior;
- fishing mechanics;
- cast camera;
- bait visuals;
- fish behavior/tension.

`FishingMenu.tscn` was validated byte-for-byte unchanged.

Core gameplay/camera scripts were also validated byte-for-byte unchanged.

## Deferred camera regression

During Pass 2 smoke testing, a possible pre-existing framing issue was noted:

After the camera follows a distant lure/fish, the fisherman may remain too high
or too central on screen as the action comes back toward shore. Starting the
next fishing cycle then makes the camera restore the normal bottom-left
fisherman composition abruptly.

Per user decision, this is **logged but intentionally not fixed during the
architecture passes**. It belongs in the post-refactor gameplay/camera
regression pass, where we can determine whether it predates the refactor.

## Why state still lives in FishingMenu

Moving code and state ownership simultaneously would create a large regression
surface without an engine executable available in this audit environment.

Pass 3 establishes the module boundary first. A later pass can move state into
the controllers if that still provides value after engine smoke testing.

## Static validation

- missing quoted `res://` references: **0**
- duplicate function declarations: **0**
- FishingMenu scene changed: **no**
- frozen gameplay/camera scripts changed: **no**

Godot is not installed in this environment, so the final validation remains:
open the Pass 3 candidate and run the normal menu smoke test in Godot.
