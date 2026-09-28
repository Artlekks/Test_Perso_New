extends RefCounted

const FightAccessibility = preload(
	"res://scripts/fishing_fight_accessibility.gd"
)

## Single authority for converting authored fish/specimen/loadout data into the
## plain runtime values consumed by the fishing fight. Keeping this calculation
## here prevents Encounter, FishBehavior and UI/debug code from independently
## reinterpreting the same species data.

const MIN_SIZE_RATIO: float = 0.50
const MAX_SIZE_RATIO: float = 1.75
const MIN_RUNTIME_MULTIPLIER: float = 0.01


static func resolve_specimen(
	data,
	size_cm: float,
	is_king: bool
) -> Dictionary:
	if data == null:
		return _empty_specimen_stats()

	var safe_average: float = maxf(float(data.average_size), 0.001)
	var safe_king: float = maxf(float(data.king_size), safe_average)
	var size_ratio_to_average: float = clampf(
		size_cm / safe_average,
		MIN_SIZE_RATIO,
		MAX_SIZE_RATIO
	)
	var size_ratio_to_king: float = maxf(size_cm / safe_king, 0.0)

	var stamina_size_scale: float = pow(
		maxf(size_ratio_to_average, 0.001),
		maxf(float(data.stamina_size_exponent), 0.0)
	)
	var strength_size_scale: float = lerpf(
		1.0,
		size_ratio_to_average,
		clampf(float(data.strength_size_influence), 0.0, 1.0)
	)

	var behavior_size_scale := _size_modifier(
		size_ratio_to_average,
		float(data.behavior_size_influence)
	)
	var pressure_size_scale := _size_modifier(
		size_ratio_to_average,
		float(data.pressure_size_influence)
	)
	var pull_size_scale := _size_modifier(
		size_ratio_to_average,
		float(data.pull_size_influence)
	)

	var profile = data.behavior_profile
	var profile_behavior: float = 1.0
	var profile_pressure: float = 1.0
	var profile_pull: float = 1.0
	var profile_recovery: float = 1.0
	var recovery_time_multiplier: float = 1.0
	var archetype_label: String = "UNPROFILED"
	var personality_label: String = "UNPROFILED"
	var difficulty_tier: int = 1
	var dominant_action: String = "UNPROFILED"

	if profile != null:
		profile_behavior = maxf(
			float(profile.fight_intensity_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		profile_pressure = maxf(
			float(profile.pressure_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		profile_pull = maxf(
			float(profile.pull_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		profile_recovery = maxf(
			float(profile.stamina_recovery_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		recovery_time_multiplier = maxf(
			float(profile.recovery_time_multiplier),
			0.5
		)
		archetype_label = profile.get_archetype_label()
		if profile.has_method("get_personality_label"):
			personality_label = profile.get_personality_label()
		difficulty_tier = clampi(int(profile.difficulty_tier), 1, 5)
		if profile.has_method("get_dominant_action_label"):
			dominant_action = profile.get_dominant_action_label()

	var king_stamina_scale: float = 1.0
	var king_strength_scale: float = 1.0
	var king_behavior_scale: float = 1.0
	var resistance_rounds: int = maxi(int(data.resistance_rounds), 1)

	if is_king:
		king_stamina_scale = maxf(float(data.king_stamina_multiplier), 1.0)
		king_strength_scale = maxf(float(data.king_strength_multiplier), 1.0)
		king_behavior_scale = maxf(float(data.king_behavior_multiplier), 1.0)
		resistance_rounds += maxi(int(data.king_extra_resistance_rounds), 0)

	# The same authored king behavior modifier drives pressure and pull at a
	# gentler square-root rate. This keeps kings recognizably stronger without
	# multiplying every output channel by the full behavior bonus.
	var king_output_scale: float = sqrt(king_behavior_scale)

	var max_stamina: float = maxf(
		float(data.base_stamina)
		* stamina_size_scale
		* king_stamina_scale,
		0.001
	)
	var strength: float = maxf(
		float(data.base_strength)
		* strength_size_scale
		* king_strength_scale,
		MIN_RUNTIME_MULTIPLIER
	)
	var behavior_intensity_multiplier: float = maxf(
		profile_behavior
		* behavior_size_scale
		* king_behavior_scale,
		MIN_RUNTIME_MULTIPLIER
	)
	var pressure_multiplier: float = maxf(
		profile_pressure
		* pressure_size_scale
		* king_output_scale,
		MIN_RUNTIME_MULTIPLIER
	)
	var pull_multiplier: float = maxf(
		profile_pull
		* pull_size_scale
		* king_output_scale,
		MIN_RUNTIME_MULTIPLIER
	)

	return {
		"valid": true,
		"size_cm": size_cm,
		"is_king": is_king,
		"size_ratio_to_average": size_ratio_to_average,
		"size_ratio_to_king": size_ratio_to_king,
		"stamina_size_scale": stamina_size_scale,
		"strength_size_scale": strength_size_scale,
		"behavior_size_scale": behavior_size_scale,
		"pressure_size_scale": pressure_size_scale,
		"pull_size_scale": pull_size_scale,
		"max_stamina": max_stamina,
		"strength": strength,
		"resistance_rounds": resistance_rounds,
		"recovery_time_min": maxf(
			float(data.recovery_time_min) * recovery_time_multiplier,
			0.0
		),
		"recovery_time_max": maxf(
			float(data.recovery_time_max) * recovery_time_multiplier,
			0.0
		),
		"behavior_intensity_multiplier": behavior_intensity_multiplier,
		"pressure_multiplier": pressure_multiplier,
		"pull_multiplier": pull_multiplier,
		"stamina_recovery_multiplier": profile_recovery,
		"behavior_profile": profile,
		"archetype": archetype_label,
		"personality": personality_label,
		"difficulty_tier": difficulty_tier,
		"dominant_action": dominant_action,
	}


static func resolve_context(
	fish,
	rod,
	bait,
	session_modifiers: Dictionary = {}
) -> Dictionary:
	if fish == null:
		return _empty_context_stats()

	var result: Dictionary = {
		"valid": true,
		"max_stamina": maxf(float(fish.max_stamina), 0.001),
		"strength": maxf(float(fish.strength), MIN_RUNTIME_MULTIPLIER),
		"resistance_rounds": maxi(int(fish.resistance_rounds), 1),
		"recovery_time_min": maxf(float(fish.recovery_time_min), 0.0),
		"recovery_time_max": maxf(float(fish.recovery_time_max), 0.0),
		"behavior_intensity_multiplier": maxf(
			float(fish.behavior_intensity_multiplier),
			MIN_RUNTIME_MULTIPLIER
		),
		"pressure_multiplier": maxf(
			float(fish.pressure_multiplier),
			MIN_RUNTIME_MULTIPLIER
		),
		"pull_multiplier": maxf(
			float(fish.pull_multiplier),
			MIN_RUNTIME_MULTIPLIER
		),
		"stamina_recovery_multiplier": maxf(
			float(fish.stamina_recovery_multiplier),
			MIN_RUNTIME_MULTIPLIER
		),
		"line_tolerance_multiplier": 1.0,
		"counter_steer_multiplier": 1.0,
		"rod_reel_speed_multiplier": 1.0,
		"stamina_drain_multiplier": 1.0,
		"hook_off_delay_multiplier": 1.0,
		"session_fish_pressure_multiplier": 1.0,
		"rod_id": "",
		"rod_fight_role": "NONE",
		"lure_id": "",
		"lure_fight_role": "NONE",
		"archetype": str(fish.archetype_label),
		"personality": str(fish.personality_label),
		"difficulty_tier": clampi(int(fish.difficulty_tier), 1, 5),
		"dominant_action": str(fish.dominant_action),
		"size_ratio_to_average": float(fish.size_ratio_to_average),
		"is_king": bool(fish.is_king),
	}

	if rod != null:
		result["line_tolerance_multiplier"] = maxf(
			float(rod.line_tolerance_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		result["counter_steer_multiplier"] = maxf(
			float(rod.counter_steer_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		result["rod_reel_speed_multiplier"] = maxf(
			float(rod.reel_speed_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		result["stamina_drain_multiplier"] *= maxf(
			float(rod.fight_fatigue_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		result["hook_off_delay_multiplier"] *= maxf(
			float(rod.hook_security_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		result["rod_id"] = str(rod.rod_id)
		result["rod_fight_role"] = str(rod.fight_role_label)

	# Lure identity already owns attraction, depth, retrieve action and snag risk.
	# Once hooked, the lure contributes only two bounded traits here: exhaustion
	# efficiency and hook security. Fish strength/pressure remain authoritative.
	if bait != null:
		result["stamina_drain_multiplier"] *= maxf(
			float(bait.fight_fatigue_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		result["hook_off_delay_multiplier"] *= maxf(
			float(bait.hook_security_multiplier),
			MIN_RUNTIME_MULTIPLIER
		)
		result["lure_id"] = str(bait.lure_id)
		result["lure_fight_role"] = str(bait.fight_role_label)

	# Temporary session modifiers are composed here, after fish + tackle, so the
	# fight still has one authoritative resolution path. They modify the player's
	# leverage/safety or resulting pressure; they never rewrite fish identity.
	if not session_modifiers.is_empty():
		result["stamina_drain_multiplier"] *= maxf(
			float(session_modifiers.get("stamina_drain_multiplier", 1.0)),
			MIN_RUNTIME_MULTIPLIER
		)
		result["hook_off_delay_multiplier"] *= maxf(
			float(session_modifiers.get("hook_off_delay_multiplier", 1.0)),
			MIN_RUNTIME_MULTIPLIER
		)
		result["line_tolerance_multiplier"] *= maxf(
			float(session_modifiers.get("line_tolerance_multiplier", 1.0)),
			MIN_RUNTIME_MULTIPLIER
		)
		result["counter_steer_multiplier"] *= maxf(
			float(session_modifiers.get("counter_steer_multiplier", 1.0)),
			MIN_RUNTIME_MULTIPLIER
		)
		result["session_fish_pressure_multiplier"] = maxf(
			float(session_modifiers.get("fish_pressure_multiplier", 1.0)),
			MIN_RUNTIME_MULTIPLIER
		)
		result["session_effect_ids"] = session_modifiers.get(
			"session_effect_ids",
			PackedStringArray()
		)

	# Bound the composed outputs so future buffs/weather can stack safely.
	result["stamina_drain_multiplier"] = clampf(
		float(result["stamina_drain_multiplier"]), 0.50, 2.50
	)
	result["hook_off_delay_multiplier"] = clampf(
		float(result["hook_off_delay_multiplier"]), 0.50, 3.0
	)
	result["line_tolerance_multiplier"] = clampf(
		float(result["line_tolerance_multiplier"]), 0.50, 3.0
	)
	result["counter_steer_multiplier"] = clampf(
		float(result["counter_steer_multiplier"]), 0.50, 2.50
	)
	result["session_fish_pressure_multiplier"] = clampf(
		float(result["session_fish_pressure_multiplier"]), 0.50, 1.50
	)

	# Difficulty metadata is descriptive only. It makes the authored progression
	# curve visible to QA/debug systems without allowing Encounter to reinterpret
	# or secretly modify fish stats.
	var accessibility_meta: Dictionary = FightAccessibility.build_context_metadata(
		int(result.get("difficulty_tier", 1)),
		rod
	)
	for key in accessibility_meta:
		result[key] = accessibility_meta[key]

	return result


static func is_valid_specimen_stats(stats: Dictionary) -> bool:
	if not bool(stats.get("valid", false)):
		return false

	var recovery_min := float(stats.get("recovery_time_min", -1.0))
	var recovery_max := float(stats.get("recovery_time_max", -1.0))

	return (
		float(stats.get("max_stamina", 0.0)) > 0.0
		and float(stats.get("strength", 0.0)) > 0.0
		and int(stats.get("resistance_rounds", 0)) >= 1
		and recovery_min >= 0.0
		and recovery_max >= recovery_min
		and float(stats.get("behavior_intensity_multiplier", 0.0)) > 0.0
		and float(stats.get("pressure_multiplier", 0.0)) > 0.0
		and float(stats.get("pull_multiplier", 0.0)) > 0.0
		and float(stats.get("stamina_recovery_multiplier", 0.0)) > 0.0
	)


static func is_valid_context(stats: Dictionary) -> bool:
	return (
		bool(stats.get("valid", false))
		and float(stats.get("max_stamina", 0.0)) > 0.0
		and float(stats.get("strength", 0.0)) > 0.0
		and float(stats.get("line_tolerance_multiplier", 0.0)) > 0.0
		and float(stats.get("counter_steer_multiplier", 0.0)) > 0.0
		and float(stats.get("rod_reel_speed_multiplier", 0.0)) > 0.0
		and float(stats.get("stamina_drain_multiplier", 0.0)) > 0.0
		and float(stats.get("hook_off_delay_multiplier", 0.0)) > 0.0
	)


static func _size_modifier(
	size_ratio_to_average: float,
	influence: float
) -> float:
	var safe_influence := clampf(influence, 0.0, 1.0)
	return maxf(
		1.0 + (size_ratio_to_average - 1.0) * safe_influence,
		0.50
	)


static func _empty_specimen_stats() -> Dictionary:
	return {
		"valid": false,
		"max_stamina": 0.0,
		"strength": 0.0,
		"resistance_rounds": 0,
		"recovery_time_min": 0.0,
		"recovery_time_max": 0.0,
		"behavior_intensity_multiplier": 1.0,
		"pressure_multiplier": 1.0,
		"pull_multiplier": 1.0,
		"stamina_recovery_multiplier": 1.0,
		"behavior_profile": null,
		"archetype": "UNPROFILED",
		"personality": "UNPROFILED",
		"difficulty_tier": 1,
		"dominant_action": "UNPROFILED",
		"size_ratio_to_average": 0.0,
		"size_ratio_to_king": 0.0,
	}


static func _empty_context_stats() -> Dictionary:
	return {
		"valid": false,
		"max_stamina": 0.0,
		"strength": 0.0,
		"resistance_rounds": 0,
		"recovery_time_min": 0.0,
		"recovery_time_max": 0.0,
		"behavior_intensity_multiplier": 1.0,
		"pressure_multiplier": 1.0,
		"pull_multiplier": 1.0,
		"stamina_recovery_multiplier": 1.0,
		"line_tolerance_multiplier": 1.0,
		"counter_steer_multiplier": 1.0,
		"rod_reel_speed_multiplier": 1.0,
		"stamina_drain_multiplier": 1.0,
		"hook_off_delay_multiplier": 1.0,
		"session_fish_pressure_multiplier": 1.0,
		"rod_id": "",
		"rod_fight_role": "NONE",
		"lure_id": "",
		"lure_fight_role": "NONE",
		"archetype": "UNPROFILED",
		"personality": "UNPROFILED",
		"difficulty_tier": 1,
		"difficulty_band": "INTRODUCTORY",
		"recommended_rod_power_tier": 0,
		"rod_power_tier": 0,
		"rod_tier_gap": 0,
		"rod_meets_recommendation": true,
		"starter_rod_supported": true,
		"dominant_action": "UNPROFILED",
		"size_ratio_to_average": 0.0,
		"is_king": false,
	}
