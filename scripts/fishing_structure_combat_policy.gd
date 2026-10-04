extends RefCounted
class_name FishingStructureCombatPolicy

const DEFAULT_ESCAPE_DEADZONE := 0.20


static func get_escape_steering_sign(
	bait_world_position: Vector3,
	structure_world_position: Vector3
) -> float:
	var delta_x := bait_world_position.x - structure_world_position.x
	if absf(delta_x) <= 0.001:
		return 0.0
	return signf(delta_x)


static func is_steering_away(
	player_steering: float,
	escape_sign: float,
	deadzone: float = DEFAULT_ESCAPE_DEADZONE
) -> bool:
	return (
		absf(player_steering) > deadzone
		and absf(escape_sign) > 0.01
		and signf(player_steering) == signf(escape_sign)
	)


static func is_fish_driving_into_structure(
	fish_lateral: float,
	escape_sign: float,
	deadzone: float = DEFAULT_ESCAPE_DEADZONE
) -> bool:
	return (
		absf(fish_lateral) > deadzone
		and absf(escape_sign) > 0.01
		and signf(fish_lateral) != signf(escape_sign)
	)


static func get_structure_seek_lateral(
	base_lateral: float,
	escape_sign: float,
	seek_strength: float
) -> float:
	if absf(escape_sign) <= 0.01:
		return clampf(base_lateral, -1.0, 1.0)
	var toward_structure := -signf(escape_sign)
	return clampf(
		lerpf(
			base_lateral,
			toward_structure,
			clampf(seek_strength, 0.0, 1.0)
		),
		-1.0,
		1.0
	)


static func get_abrasion_rate_multiplier(
	safe_pressure_ratio: float,
	fish_pressure: float,
	fish_driving_in: bool,
	player_steering_away: bool,
	knows_structure_fighting: bool
) -> float:
	# High safe pressure is efficient in open water, but scraping hard against
	# structure is exactly when brute force becomes dangerous.
	var multiplier := lerpf(
		0.65,
		1.35,
		clampf(safe_pressure_ratio, 0.0, 1.0)
	)
	multiplier *= lerpf(
		0.85,
		1.30,
		clampf(fish_pressure, 0.0, 1.0)
	)
	if fish_driving_in:
		multiplier *= 1.35
	if player_steering_away:
		# The action matters even before the technique is taught; mastery makes
		# the deliberate side-pressure response substantially more effective.
		multiplier *= 0.22 if knows_structure_fighting else 0.52
	return maxf(multiplier, 0.0)


static func get_lure_snag_build_multiplier(knows_snag_escape: bool) -> float:
	return 0.55 if knows_snag_escape else 1.0


static func get_lure_snag_recovery_multiplier(knows_snag_escape: bool) -> float:
	return 1.65 if knows_snag_escape else 1.0


static func build_structure_snapshot(
	contact: Dictionary,
	abrasion: float,
	escape_sign: float,
	steering_away: bool,
	fish_driving_in: bool,
	knows_structure_fighting: bool
) -> Dictionary:
	var result := contact.duplicate(true)
	result["abrasion"] = clampf(abrasion, 0.0, 1.0)
	result["escape_steering_sign"] = escape_sign
	result["steering_away"] = steering_away
	result["fish_driving_in"] = fish_driving_in
	result["structure_fighting_known"] = knows_structure_fighting
	return result
