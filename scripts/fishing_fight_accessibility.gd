extends RefCounted

## Deterministic difficulty/fairness auditor. This is deliberately separate from
## FightResolver: the resolver answers "what are the fight stats?" while this
## service answers "does that authored fight fit our progression contract?"
## Nothing in this script silently buffs or nerfs live gameplay.

const POLICY = preload(
	"res://data/bof4/fight/default_difficulty_policy.tres"
)


static func get_policy():
	return POLICY


static func get_rod_power_tier(rod) -> int:
	if rod == null:
		return 0
	return clampi(int(rod.power_tier), 0, 3)


static func get_recommended_rod_power_tier(fish_tier: int) -> int:
	return POLICY.get_recommended_rod_power_tier(fish_tier)


static func build_context_metadata(fish_tier: int, rod) -> Dictionary:
	var actual_rod_tier := get_rod_power_tier(rod)
	var recommended := get_recommended_rod_power_tier(fish_tier)
	return {
		"difficulty_band": POLICY.get_tier_label(fish_tier),
		"recommended_rod_power_tier": recommended,
		"rod_power_tier": actual_rod_tier,
		"rod_tier_gap": actual_rod_tier - recommended,
		"rod_meets_recommendation": actual_rod_tier >= recommended,
		"starter_rod_supported": POLICY.starter_rod_should_support(fish_tier),
	}


static func audit_specimen(
	fish_data,
	fight_stats: Dictionary,
	rod,
	tension_profile,
	is_king: bool,
	base_bite_window_seconds: float = -1.0,
	stamina_drain_per_second: float = -1.0,
	lure = null
) -> Dictionary:
	if fish_data == null or fight_stats.is_empty():
		return {"valid": false}

	var profile = fish_data.behavior_profile
	if profile == null:
		return {"valid": false}

	var fish_tier := clampi(int(profile.difficulty_tier), 1, 5)
	var bite_base := (
		base_bite_window_seconds
		if base_bite_window_seconds > 0.0
		else float(POLICY.reference_bite_window_seconds)
	)
	var drain_speed := (
		stamina_drain_per_second
		if stamina_drain_per_second > 0.0
		else float(POLICY.reference_stamina_drain_per_second)
	)
	var stamina_drain_multiplier: float = 1.0
	var hook_off_delay_multiplier: float = 1.0
	if rod != null:
		stamina_drain_multiplier *= maxf(float(rod.fight_fatigue_multiplier), 0.01)
		hook_off_delay_multiplier *= maxf(float(rod.hook_security_multiplier), 0.01)
	if lure != null:
		stamina_drain_multiplier *= maxf(float(lure.fight_fatigue_multiplier), 0.01)
		hook_off_delay_multiplier *= maxf(float(lure.hook_security_multiplier), 0.01)
	drain_speed *= stamina_drain_multiplier
	var bite_window_seconds := (
		bite_base * maxf(float(profile.bite_window_multiplier), 0.0)
	)
	var active_reel_seconds := (
		maxf(float(fight_stats.get("max_stamina", 0.0)), 0.0)
		/ maxf(drain_speed, 0.001)
		* maxi(int(fight_stats.get("resistance_rounds", 1)), 1)
	)
	var minimum_bite := POLICY.get_minimum_bite_window_seconds(fish_tier)
	var duration_budget := POLICY.get_max_active_reel_seconds(fish_tier, is_king)

	var line_break_grace := 0.0
	var hook_off_grace := 0.0
	if tension_profile != null:
		line_break_grace = maxf(float(tension_profile.line_break_delay), 0.0)
		hook_off_grace = maxf(float(tension_profile.hook_off_delay), 0.0)
	if rod != null:
		line_break_grace *= maxf(float(rod.line_tolerance_multiplier), 0.01)
	hook_off_grace *= hook_off_delay_multiplier

	var equipment := build_context_metadata(fish_tier, rod)
	var bite_accessible := bite_window_seconds + 0.0001 >= minimum_bite
	var duration_accessible := active_reel_seconds <= duration_budget + 0.0001
	var line_failure_readable := (
		line_break_grace + 0.0001
		>= float(POLICY.minimum_line_break_grace_seconds)
	)
	var hook_failure_readable := (
		hook_off_grace + 0.0001
		>= float(POLICY.minimum_hook_off_grace_seconds)
	)

	return {
		"valid": true,
		"fish_tier": fish_tier,
		"difficulty_band": POLICY.get_tier_label(fish_tier),
		"bite_window_seconds": bite_window_seconds,
		"minimum_bite_window_seconds": minimum_bite,
		"active_reel_seconds": active_reel_seconds,
		"active_reel_budget_seconds": duration_budget,
		"line_break_grace_seconds": line_break_grace,
		"hook_off_grace_seconds": hook_off_grace,
		"stamina_drain_multiplier": stamina_drain_multiplier,
		"hook_off_delay_multiplier": hook_off_delay_multiplier,
		"bite_accessible": bite_accessible,
		"duration_accessible": duration_accessible,
		"line_failure_readable": line_failure_readable,
		"hook_failure_readable": hook_failure_readable,
		"starter_rod_supported": bool(equipment.get("starter_rod_supported", false)),
		"recommended_rod_power_tier": int(equipment.get("recommended_rod_power_tier", 0)),
		"rod_power_tier": int(equipment.get("rod_power_tier", 0)),
		"rod_tier_gap": int(equipment.get("rod_tier_gap", 0)),
		"rod_meets_recommendation": bool(equipment.get("rod_meets_recommendation", false)),
		"passes_fairness_envelope": (
			bite_accessible
			and duration_accessible
			and line_failure_readable
			and hook_failure_readable
		),
	}
