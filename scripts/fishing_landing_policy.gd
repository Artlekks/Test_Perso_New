extends RefCounted
class_name FishingLandingPolicy

## Pure rules for the last few metres of a fight.
##
## Landing is baseline angling knowledge, not a mastery unlock. A fish that has
## already been exhausted can still make one final burst close to shore. The
## policy only decides how likely/strong that burst is; Encounter owns runtime
## state and Bait owns movement.

const MIN_FINAL_SURGE_CHANCE: float = 0.10
const MAX_FINAL_SURGE_CHANCE: float = 0.82


static func is_in_final_surge_window(
	distance_meters: float,
	trigger_distance_meters: float
) -> bool:
	return (
		distance_meters >= 0.0
		and distance_meters <= maxf(trigger_distance_meters, 0.05)
	)


static func get_final_surge_chance(
	difficulty_tier: int,
	size_ratio_to_average: float,
	is_king: bool
) -> float:
	var tier := clampi(difficulty_tier, 1, 5)
	var size_bonus := clampf(
		(size_ratio_to_average - 1.0) / 0.75,
		0.0,
		1.0
	) * 0.14
	var king_bonus := 0.22 if is_king else 0.0
	var chance := (
		0.12
		+ float(tier - 1) * 0.075
		+ size_bonus
		+ king_bonus
	)
	return clampf(
		chance,
		MIN_FINAL_SURGE_CHANCE,
		MAX_FINAL_SURGE_CHANCE
	)


static func get_final_surge_stamina_ratio(
	difficulty_tier: int,
	is_king: bool
) -> float:
	var tier := clampi(difficulty_tier, 1, 5)
	var ratio := 0.16 + float(tier - 1) * 0.025
	if is_king:
		ratio += 0.08
	return clampf(ratio, 0.14, 0.36)


static func get_final_surge_intensity(
	difficulty_tier: int,
	is_king: bool
) -> float:
	var tier := clampi(difficulty_tier, 1, 5)
	var intensity := 0.78 + float(tier - 1) * 0.045
	if is_king:
		intensity += 0.08
	return clampf(intensity, 0.75, 1.08)


static func build_snapshot(
	distance_meters: float,
	chance: float,
	stamina_ratio: float,
	intensity: float
) -> Dictionary:
	return {
		"active": true,
		"label": "FINAL SURGE",
		"distance_meters": maxf(distance_meters, 0.0),
		"chance": clampf(chance, 0.0, 1.0),
		"stamina_ratio": clampf(stamina_ratio, 0.0, 1.0),
		"intensity": maxf(intensity, 0.0),
	}
