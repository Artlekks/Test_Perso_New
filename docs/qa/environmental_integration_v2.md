# Environmental Integration v2 — smooth weather presentation

Install **after Environmental Integration v1** and the approved
`FishingRainVFX_sea_coverage_angle_fix`. This patch only changes world rain
presentation and adds a pure visual policy, its QA and this note. It does NOT
rewrite the scheduler, fishing modifiers, sea shader, camera, wind, current,
or user-approved `actors/FishingRainVFX.tscn` settings.

## New behavior

- In `Rain Mode = Auto`, rain follows the existing gameplay weather tags.
  The actual condition changes immediately; particles and ripple spawn rate
  fade in/out visually without changing fish ecology or weather calculations.
- Visual fade durations are adjustable in the Rain node Inspector under
  **Weather Transitions - Visual Only** (default 2.5 s in, 4.0 s out,
  3.0 s Rain/Tempest blend). Setting any duration to 0 disables that fade.
- When arriving in a location that is already raining, rain starts at full
  intensity: entering a scene should not replay a rain transition.
- Rain Preview, Storm Preview, Clear, and `enabled` behave as before.
  Previews do not set gameplay weather or save data.
- The live FishingEnvironmentService tags remain highest priority, including
  its manual weather preview. When no fishing controller/tags are present,
  world rain falls back to `/root/GameWeather`'s schedule. No second weather
  clock, RNG, or duplicated calculation is introduced.
- During a fade-out, falling rain persists until fully transparent and the
  ripple spawn rate decays. Existing splashes complete their animations.
  Settled Rain still uses 220 drops, the approved color/opacity, and 80
  splashes/second; settled Tempest retains its 1.3x ripple rate.

## Verification

1. `godot --headless --path . --script res://scripts/qa/environment_integration_v1_qa.gd`
2. `godot --headless --path . --script res://scripts/qa/environment_integration_v2_qa.gd`
3. Run existing weather, rainfall, world location and clock QA.
4. In-game, switch the Rain Inspector preview between Clear, Rain Preview,
   Storm Preview, Clear. Check fade timing, splash taper, UI visibility,
   and that rain's fully-settled look matches the approved screenshot.
5. Set Rain Mode back to Auto. Advance the game clock across a weather
   boundary. Fish ecology should respond immediately; world rain fades.
6. Enter a new spot while already raining: rain should appear immediately.
   Test exploration, fishing, world travel, save/load, desktop and mobile.

The Pure presentation policy in
`scripts/environment_fx/environment_weather_presentation_policy.gd`
can be reused for later snow or mist effects without introducing any new
weather states at this stage.

## Explicitly deferred

Per-drop angle randomness, shoreline/deep-water current color grading,
additional conditions (snow/fog), and visual wind speed changes are NOT
part of this patch. Keep the approved geometry and movement unchanged.
