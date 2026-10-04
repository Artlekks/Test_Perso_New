extends RefCounted
class_name FishingWarinessPolicy

const QUIET_APPROACH_NOISE_MULTIPLIER: float = 0.32
const MIN_SCARE_RADIUS: float = 2.4
const MAX_SCARE_RADIUS: float = 5.4
const BASE_STRESS_GAIN_PER_SECOND: float = 1.65
const BASE_STRESS_DECAY_PER_SECOND: float = 0.34
const SPOOK_THRESHOLD: float = 0.72


static func get_effective_noise(
	raw_noise: float,
	has_quiet_approach: bool
) -> float:
	var noise := clampf(raw_noise, 0.0, 1.0)
	if has_quiet_approach:
		noise *= QUIET_APPROACH_NOISE_MULTIPLIER
	return noise


static func get_scare_radius(wariness: float) -> float:
	return lerpf(
		MIN_SCARE_RADIUS,
		MAX_SCARE_RADIUS,
		clampf(wariness, 0.0, 1.0)
	)


static func get_proximity_factor(
	distance_to_player: float,
	wariness: float
) -> float:
	var radius := get_scare_radius(wariness)
	if radius <= 0.0 or distance_to_player >= radius:
		return 0.0
	return 1.0 - clampf(distance_to_player / radius, 0.0, 1.0)


static func get_stress_delta(
	raw_noise: float,
	distance_to_player: float,
	wariness: float,
	has_quiet_approach: bool,
	delta: float
) -> float:
	var effective_noise := get_effective_noise(
		raw_noise,
		has_quiet_approach
	)
	var proximity := get_proximity_factor(
		distance_to_player,
		wariness
	)
	var sensitivity := lerpf(
		0.45,
		1.35,
		clampf(wariness, 0.0, 1.0)
	)
	var gain := (
		effective_noise
		* proximity
		* sensitivity
		* BASE_STRESS_GAIN_PER_SECOND
		* maxf(delta, 0.0)
	)
	if gain > 0.0:
		return gain
	return -BASE_STRESS_DECAY_PER_SECOND * maxf(delta, 0.0)


static func should_spook(stress: float) -> bool:
	return stress >= SPOOK_THRESHOLD


static func build_snapshot(
	raw_noise: float,
	distance_to_player: float,
	wariness: float,
	has_quiet_approach: bool
) -> Dictionary:
	var effective_noise := get_effective_noise(
		raw_noise,
		has_quiet_approach
	)
	return {
		"raw_noise": clampf(raw_noise, 0.0, 1.0),
		"effective_noise": effective_noise,
		"wariness": clampf(wariness, 0.0, 1.0),
		"scare_radius": get_scare_radius(wariness),
		"proximity": get_proximity_factor(
			distance_to_player,
			wariness
		),
		"quiet_approach": has_quiet_approach,
	}
