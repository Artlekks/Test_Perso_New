extends RefCounted
## Environmental Gameplay Integration v1: one deterministic read-only assessment.
## This policy never advances the clock, rolls RNG, or changes lure/camera state.
## Existing weather/tide modifiers remain the legacy authority until separately
## audited. Species-specific ecology is opt-in (all old FishData default neutral).
##
## The units coming from current_service are project-authored world units,
## NOT guaranteed measured metres/second; flow_ratio is a design index.

const MIN_SPECIES_MULTIPLIER: float = 0.65
const MAX_SPECIES_MULTIPLIER: float = 1.35


static func build_snapshot(
	clock_snapshot: Dictionary,
	wind_snapshot: Dictionary,
	tide_snapshot: Dictionary,
	current_velocity: Vector2,
	weather_tags: PackedStringArray,
	spot_id: String = ""
) -> Dictionary:
	var total_minutes: int = int(clock_snapshot.get("total_minutes", 480))
	var hour: float = float(posmod(total_minutes, 1440)) / 60.0
	# A simplified 06:00-18:00 local daylight envelope. It is not latitude,
	# season or astronomy data. Smooth transitions avoid hard activity jumps.
	var sunrise: float = _smooth_step(5.0, 8.0, hour)
	var sunset: float = 1.0 - _smooth_step(17.0, 20.0, hour)
	var daylight: float = clampf(sunrise * sunset, 0.0, 1.0)
	var dawn: float = clampf(1.0 - absf(hour - 6.5) / 2.0, 0.0, 1.0)
	var dusk: float = clampf(1.0 - absf(hour - 18.5) / 2.0, 0.0, 1.0)
	var twilight: float = maxf(dawn, dusk)
	var night: float = clampf(1.0 - daylight, 0.0, 1.0)

	var rain: float = 0.0
	var clouds: float = 0.10
	var unsafe_storm: bool = false
	if weather_tags.has("storm") or weather_tags.has("tempest"):
		rain = 0.90
		clouds = 0.95
		unsafe_storm = true
	elif weather_tags.has("rain"):
		rain = 0.50
		clouds = 0.75
	elif weather_tags.has("cloudy") or weather_tags.has("overcast"):
		clouds = 0.75
	# These are qualitative proxies, NOT measurements. Precipitation does
	# not instantly imply that an entire waterbody becomes turbid.
	var visibility: float = clampf(
		(0.12 + 0.88 * daylight) * (1.0 - clouds * 0.42), 0.0, 1.0
	)
	var turbidity_proxy: float = clampf(0.08 + rain * 0.22, 0.0, 1.0)
	var wind_speed: float = maxf(float(wind_snapshot.get("speed_mps", 0.0)), 0.0)
	var wave_proxy: float = clampf(wind_speed / 12.0 + rain * 0.12, 0.0, 1.0)
	var flow_speed: float = current_velocity.length()
	var flow_ratio: float = clampf(flow_speed / 1.0, 0.0, 1.0)
	var tide_active: bool = bool(tide_snapshot.get("active", false))
	var tide_level: float = clampf(float(tide_snapshot.get("water_level_ratio", 0.5)), 0.0, 1.0)

	return {
		"spot_id": spot_id,
		"total_minutes": total_minutes,
		"clock_available": clock_snapshot.has("total_minutes"),
		"wind_available": bool(wind_snapshot.get("available", wind_snapshot.has("speed_mps"))),
		"daylight_0_1": daylight,
		"twilight_0_1": twilight,
		"night_0_1": night,
		"visual_light_0_1": visibility,
		"rain_proxy_0_1": rain,
		"turbidity_proxy_0_1": turbidity_proxy,
		"wave_proxy_0_1": wave_proxy,
		"wind_speed_mps": wind_speed,
		"wind_velocity_xz": wind_snapshot.get("velocity_xz", Vector2.ZERO),
		"current_velocity_xz": current_velocity,
		"flow_ratio_0_1": flow_ratio,
		"tide_active": tide_active,
		"tide_level_0_1": tide_level,
		"tide_phase_id": tide_snapshot.get("phase_id", &"none"),
		"unsafe_storm": unsafe_storm,
		"weather_tags": weather_tags.duplicate(),
		"quality": "authored_simplification",
		"note": "Light/turbidity/waves are simplified proxies; local tide/current come from existing services.",
	}


static func species_activity_multiplier(fish: FishData, ecology: Dictionary) -> float:
	if fish == null:
		return 0.0
	# No new effect until species ecology has been deliberately authored.
	var cycle: int = int(fish.ecological_activity_cycle)
	var flow_niche: int = int(fish.ecological_flow_niche)
	var visual_niche: int = int(fish.ecological_visibility_niche)
	if cycle == 0 and flow_niche == 0 and visual_niche == 0:
		return 1.0
	# Missing providers must never silently turn unavailable data into an
	# apparent day or slack-flow preference.
	if not bool(ecology.get("clock_available", true)):
		cycle = 0
	if not bool(ecology.get("current_available", true)):
		flow_niche = 0
	var multiplier: float = 1.0
	if cycle == 1: # Daylight-active
		multiplier *= lerpf(0.82, 1.16, clampf(float(ecology.get("daylight_0_1", 0.5)), 0.0, 1.0))
	elif cycle == 2: # Twilight-active (not every species)
		multiplier *= lerpf(0.84, 1.20, clampf(float(ecology.get("twilight_0_1", 0.0)), 0.0, 1.0))
	elif cycle == 3: # Night-active
		multiplier *= lerpf(0.82, 1.16, clampf(float(ecology.get("night_0_1", 0.5)), 0.0, 1.0))

	var flow: float = clampf(float(ecology.get("flow_ratio_0_1", 0.5)), 0.0, 1.0)
	if flow_niche == 1: # Prefers low flow
		multiplier *= lerpf(1.14, 0.80, flow)
	elif flow_niche == 2: # Intermediate current, not maximum
		multiplier *= lerpf(0.86, 1.16, 1.0 - absf(2.0 * flow - 1.0))
	elif flow_niche == 3: # Strong flow specialist
		multiplier *= lerpf(0.82, 1.14, flow)

	var visibility: float = clampf(float(ecology.get("visual_light_0_1", 0.5)), 0.0, 1.0)
	if visual_niche == 1: # Bright/clear visual feeding
		multiplier *= lerpf(0.86, 1.12, visibility)
	elif visual_niche == 2: # Low-light specialist
		multiplier *= lerpf(1.12, 0.86, visibility)
	return clampf(multiplier, MIN_SPECIES_MULTIPLIER, MAX_SPECIES_MULTIPLIER)


static func _smooth_step(edge0: float, edge1: float, value: float) -> float:
	var u: float = clampf((value - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)
