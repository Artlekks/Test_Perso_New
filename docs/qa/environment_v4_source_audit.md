# Environmental Integration v4 — Source Audit & Regression Plan

**Snapshot:** `fishing_game_clean_candidate_FRESH3.zip` (provided October 13, 2026). The ZIP was used as the authoritative baseline; no earlier script patches were overlaid. No gameplay file has been modified by this audit.

## Audit status and limits

**Source archive integrity: PASS.** Zipfile CRC and extraction succeeded. The archive includes `project.godot`, 498 `.gd` scripts, 140 `.tscn` scenes, 475 `.tres` resources, and all 30 BOF4 fish resource files. Excluding `.godot`, `.git` and `build` is appropriate: they are caches, version-control metadata and generated output respectively.

**Static linkage: PASS within the inspected scope.** Across GDScript `load`/`preload` calls and literal scene/resource `ext_resource` paths, 2,923 referenced project files resolve; 0 missing. There are 284 unique `class_name` declarations without collision, and 727 inspected UID declarations/sidecars without collisions. Dynamic paths, imported/built outputs and runtime-generated filenames are not validated by this check. These results **do not establish that GDScript parses or gameplay works**.

**Godot runtime: NOT EXECUTED IN THIS AUDIT ENVIRONMENT.** The Godot 4.7.2 binary was unavailable here. The supplied Windows runner executes real Godot tests on your machine; source-level assertions and reference checks are not substitutes for that.

## Confirmed integration paths

- **Clock:** `/root/WorldLocations` defers mounting `/root/GameClock`; `GameClock` advances one game minute every **five** real seconds, pauses with the SceneTree, and persists time with a primary/backup JSON save (`scripts/world/world_location_service.gd`, `scripts/world/game_clock_service.gd`).
- **Wind:** `/root/GameWind` is deterministically keyed to the game clock. `WindCastRuntime` subscribes to the existing Caster event and bends only intermediate airborne path points; endpoints are preserved (`scripts/world/game_wind_service.gd`, `scripts/world/wind_cast_runtime.gd`, `scripts/world/wind_cast_path.gd`).
- **Tide:** the production tide service binds to the shared clock and uses a 745-game-minute period. Current and tide services are linked in session composition (`scripts/fishing_tide_service.gd`, `scripts/fishing_session_services.gd`).
- **Ecology:** fish-selection context in Encounter requests lure-position ecology, and the environment service samples the registered current service. Only **blue_gill, rainbow_trout, black_bass and bonito** have authored nonneutral ecology settings; the other 26 resource files are neutral (`scripts/encounter.gd`, `scripts/fishing_environment_service.gd`, `scripts/fishing_ecology_policy.gd`, `data/bof4/fish/`).
- **Lure presentation:** Encounter separately multiplies its established presentation score by the v3 environment presentation value, capped at **0.88–1.12** (`scripts/encounter.gd`, `scripts/fishing_habitat_presentation_policy.gd`). No cast-input code is replaced here.

## Findings requiring follow-up

### P1 — Current sampling phase diverges between ecology and physical lure drift

**Evidence:** `scripts/fishing_environment_service.gd::get_ecology_snapshot` passes `0.0` as `time_seconds` to `sample_current_velocity`/`sample_current_at_uv`. In `scripts/fishing_current_service.gd`, the default `time_seconds = -1.0` instead samples live `Time.get_ticks_msec()`, including authored oscillating current gusts. Real lure drift and some mastery/UI consumers call the live/default path. `data/bof4/spots/ocean_2.tres` enables these oscillations (`current_gust_strength = 0.18`, period `7.0` seconds). Consequently, an ecology assessment can use a different instantaneous current speed from actual lure movement at the same position.

**Risk:** species-flow response and presentation feedback may disagree with observed drift. Repeating a deterministic test with `0.0` does not catch the runtime mismatch.

**Proposed regression before a fix:** inject a known sampling time into both paths and verify spatial/current agreement at `t=0`, quarter-period and half-period. Then choose *one* timestamp source for physics and ecology at bite evaluation. Preserve replay determinism and the existing QA fixture's explicit sample-time assumptions. Do not change this during a parser/startup emergency.

### P2 — Weather and legacy time-of-day conditions are not automatically scheduled

**Evidence:** `activate_condition` is invoked by authored tests/debug operations, not by a production dynamic weather driver. The clock *does* produce daylight/twilight/night proxies for opt-in species ecology, but existing condition groups such as `dawn`/`night` are not automatically activated on the basis of time in production. Weather is not yet a synchronized, evolving global forecast.

**Impact:** a scientifically meaningful weather cycle and the old manually selected environmental conditions are still separate concepts; rain/storm scenarios currently require authoring/test controls. This is an **incomplete feature**, not evidence of a broken existing UI.

**Next design step:** one deterministic, seeded weather timeline per location with transition rules and observable effects; no blanket rain=bonus assumption. Add save/travel/restart consistency tests.

### P3 — Tide-current relationship is a limited authored model

**Evidence:** `FishingTideService.get_current_multiplier_for_spot` changes current magnitude according to phase, but `FishingCurrentService.sample_spot_at_uv` does not automatically reverse the authored vector as the tide switches from incoming to outgoing. Depending on location, this may be acceptable, but should not be interpreted as a universal physical treatment of tidal channels.

**Next design step:** location-specific tidal flow and slack offsets, not a universal direction flip. Add cases for sheltered beach versus inlet, and for water-level vs current peaks.

### P4 — Compound balance needs empirical testing

Four species ecology weights are clamped **0.65–1.35** and presentation multipliers **0.88–1.12**, but these still combine with older weather/tide bite modifiers, lure baseline, prepared bait, mastery and spatial density. Numeric local clamps alone cannot prove acceptable catch-rate outcomes. Run controlled, seeded encounter batches before tuning any coefficients or expanding species profiles.

## Regression procedure (Godot 4.7.2 on Windows)

1. Back up your project and clock save as usual. Copy the new `tools/qa/run_environment_v4_regression.ps1` into the matching `tools/qa/` directory. It adds no gameplay scripts.
2. In PowerShell opened in your project root:

   ```powershell
   .\tools\qa\run_environment_v4_regression.ps1 -GodotExe "C:\path\to\Godot_v4.7.2-stable_win64.exe"
   ```

   The first invocation imports the source project if required and recreates `.godot`; that is normal. Later invocations may use `-SkipImport`.
3. It runs **eight independent Godot environmental QA suites**, one engine process per suite, captures output under `build/environment-v4-regression-<timestamp>/` and generates `summary.csv`. To include the existing current/presentation check, add `-IncludePresentation`.
4. Share `summary.csv` and any failing logs. **Any nonzero exit or script parse error blocks a green sign-off.** A suite passing does not guarantee the camera or in-game presentation is visually correct.

### Required hands-on scenarios after script tests

| Scenario | Expected observation |
|---|---|
| Exploration; resize/float/dock | Header clock/wind/tide/current remain readable; menu bottom anchor consistent |
| Five-second progression and reload | Clock resumes correctly; wind and tide match saved time |
| Cast into current, A/D/K retrieve | Physical lure drift, ecology response and presentation are consistent |
| Headwind/tailwind/crosswind cast | Airborne bow varies modestly; landing target and control semantics preserved |
| Light/dusk/night at comparable spots | Only the four profiled species show new opt-in ecology differences |
| Storm/rain authoring | Visual detection and condition tags respond; 26 neutral species stay neutral to **new ecology**, not necessarily to legacy global weather bonuses |
| Normal fishing, bite, hookset, fish fight | No regressions to camera/input/hookset and save journal |
| Desktop + mobile portrait/landscape | Correct header and gameplay separation; no UI or fishing control regression |

## Sign-off gate

- **PASS now:** snapshot extraction, static literal dependencies, duplicate class/UID checks, four species resource scoping.
- **OPEN:** eight Godot QA runs, startup/gameplay acceptance, wind/current/physics time synchronization, compound bite-rate balance.
- **Do not mark v4 complete until:** no Godot parse/startup error, all environmental QA green, existing fishing regression remains green, camera and dock/mobile basic smoke passes, and sampled bite-rate results are reviewed.

The next implementation should be a small synchronized-current sampling correction **after** this QA baseline is captured, followed by a weather/diurnal scheduling pass and regression. The camera pitch/yaw audit remains a separate later milestone.
