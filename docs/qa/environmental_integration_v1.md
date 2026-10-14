# Environmental Integration v1 — install / QA

This patch is layered over `fishing_game_clean_candidate_FRESH5.zip` with the **approved**
`FishingRainVFX_sea_coverage_angle_fix.zip` already installed. It does not replace rain,
wind, current, camera, gameplay scenes, textures, or user-edited rain parameters.

## Runtime contract

- `/root/GameClock`: owns persistent game minutes and pause behavior.
- `/root/GameWeather` (new): computes a deterministic Calm / Rain / Tempest schedule using the
  clock minute. Default window: 240 game minutes = 20 real minutes at standard clock speed.
  Windows with the same result make longer periods. Clock persistence automatically preserves
  weather on save/load and travel — no independent weather save file.
- `/root/GameWind`: unchanged. Still owns actual wind direction and speed.
- `FishingEnvironmentService`: production sessions opt into the world-weather feed. The
  existing weather condition resources, fish ecology, tackle calculations, and forecast UI
  use the same condition. Detached QA services remain independent and manual.
- World-owned `FishingRainVFX`: unchanged. `Rain Mode = Auto` reads the active gameplay tags;
  Rain Preview / Storm Preview are **visual-only**, not gameplay weather overrides.
- `environment_overlay.gd`: keeps the wind readout, but disables the retired 2D weather
  particle renderer by default so the world 3D rain is not doubled.

`FishingEnvironmentService.get_world_snapshot()` returns a read-only dictionary with
`clock`, `weather`, `wind`, `current`, `tide`, `spot_id`, `active_condition_ids`, `active_tags`.
It never invents physics values or applies bonus multipliers.

## Developer behavior

`FishingEnvironmentService.activate_condition(&"rain")` and `&"tempest"` still work in
runtime as temporary manual previews. They take precedence until the **next world weather
change event**. `enable_live_weather(false)` detaches automatic weather completely, if a
manual weather workflow is needed. World weather itself remains keyed to GameClock.

To adjust schedule frequency, edit `GameWeather`'s exported `weather_window_minutes`,
`rain_chance_percent`, and `tempest_chance_percent` defaults in
`scripts/world/game_weather_service.gd`. Do not adjust Rain Preview to simulate gameplay
weather: it is a visual testing switch.

## QA

1. Run `godot --headless --path . --script res://scripts/qa/environment_integration_v1_qa.gd`.
2. Run existing environment startup/clock, ecology, rain visual, wind and current integration QA.
3. In the editor, test *auto* weather at multiple clock times (manually move GameClock in
   a non-production QA save). Check UI conditions, actual rain and fish environment tags.
4. Travel between locations and enter / leave fishing. The clock and weather should be
   unchanged by the scene transition; rain must remain World-owned.
5. Pause, resume, save and reload: no offline advancement and identical weather at the
   same total game minute. Verify landscape, portrait and desktop views do not double rain.
6. Recheck approved rain Inspector parameters and splash top-row animations.

## Scope / later polish

No camera, shaders, current tint, wind size, rain geometry or drop irregularity edits.
Transitions currently switch weather conditions at their deterministic clock boundaries;
visual cross-fading, gust-dependent storm intensity and biome-specific presets are reserved
for a later visual polish pass after in-game QA. Snow/fog may subscribe later without
changing the weather/gameplay service contracts.
