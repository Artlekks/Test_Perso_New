# FishingGame Architecture — Pass 4: System Ownership

**Date:** 2026-09-27  
**Baseline:** Pass 3 modular-menu candidate

## Goal

Stop `fishing.gd` from owning persistent service construction and the QA/debug
subsystem in addition to gameplay orchestration.

## New ownership

### FishingSessionServices

`fishing_session_services.gd` now owns:

- FishingProgress
- FishingInventory
- FishingTradeService
- FishingUnlockState
- FishingRewardService
- FishingJournalService
- their catalog/resource dependencies
- the Progress -> Inventory binding

The SceneTree now has one explicit session-service root rather than six
independently-created service roots.

`Fishing` keeps typed references for compatibility with existing callers, but
it receives them from the session container.

### FishingDebugController

`fishing_debug_controller.gd` now owns:

- FishingDebugSettings
- FishingDebugMenu
- F10 detection
- debug overlay open/close lifecycle
- spot override handling
- shadow/environment QA synchronization
- the SAVE DBG catch-persistence gate

`Fishing` now only routes input to that controller.

## Fishing controller result

`fishing.gd`:

- before Pass 4: **1844 lines**
- after Pass 4: **1585 lines**

It remains the fishing phase/gameplay orchestrator, but it is no longer the
service factory or debug-menu controller.

## Scene split decision

The original audit proposed extracting `FishingHUD.tscn` and
`FishingSystem.tscn`.

That scene-graph move is intentionally **not performed in this static-only
environment**. The current scene has many exported Node references and a scene
split would change NodePaths/ownership without Godot available to validate them.

The important architecture boundary—service and debug ownership—is established
first. A scene-composition split can be done later if profiling/maintenance
still justifies it.

## Behavior frozen

Pass 4 does not modify:

- camera scripts;
- bait scripts;
- FishingMenu scene;
- FishingTestScene node hierarchy;
- cast/fight/catch mechanics;
- Data/Equip/Hints UI behavior.

The noted post-follow fisherman framing issue remains deferred until the
post-refactor gameplay regression pass.

## Static validation

- missing quoted res:// references: **0**
- duplicate function declarations: **0**
- duplicate class_name declarations: **0**
- frozen camera/bait/menu/test-scene files changed: **no**
