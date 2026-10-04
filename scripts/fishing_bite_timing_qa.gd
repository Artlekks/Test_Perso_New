extends RefCounted
class_name FishingBiteTimingQA

const Policy = preload("res://scripts/fishing_bite_timing_policy.gd")


static func run() -> Dictionary:
	var failures := PackedStringArray()
	var passed: int = 0
	var total: int = 0

	var steady := _profile(FishBehaviorProfile.FightArchetype.STEADY)
	var darting := _profile(FishBehaviorProfile.FightArchetype.DARTING)
	var aggressive := _profile(FishBehaviorProfile.FightArchetype.AGGRESSIVE)
	var heavy := _profile(FishBehaviorProfile.FightArchetype.HEAVY)
	var erratic := _profile(FishBehaviorProfile.FightArchetype.ERRATIC)

	var strike_read: Dictionary = Policy.resolve_for_profile(darting, 0.80, false)
	var nibble_read: Dictionary = Policy.resolve_for_profile(steady, 0.80, false)
	var load_read: Dictionary = Policy.resolve_for_profile(heavy, 0.80, false)
	var feint_read: Dictionary = Policy.resolve_for_profile(erratic, 0.80, false)
	var direct_read: Dictionary = Policy.resolve_for_profile(heavy, 0.80, true)

	var override_profile := _profile(FishBehaviorProfile.FightArchetype.STEADY)
	override_profile.bite_timing_style = FishBehaviorProfile.BiteTimingStyle.FEINT
	var override_read: Dictionary = Policy.resolve_for_profile(override_profile, 0.80, false)

	var slow_nibble := _profile(FishBehaviorProfile.FightArchetype.STEADY)
	slow_nibble.bite_commit_delay_multiplier = 1.25
	var slow_nibble_read: Dictionary = Policy.resolve_for_profile(slow_nibble, 0.80, false)

	var short_feint: Dictionary = Policy.resolve_for_profile(erratic, 0.22, false)

	var checks: Array[Dictionary] = [
		{
			"name": "steady auto-maps to nibble",
			"ok": steady.get_resolved_bite_timing_style() == FishBehaviorProfile.BiteTimingStyle.NIBBLE,
		},
		{
			"name": "darting auto-maps to strike",
			"ok": darting.get_resolved_bite_timing_style() == FishBehaviorProfile.BiteTimingStyle.STRIKE,
		},
		{
			"name": "aggressive auto-maps to strike",
			"ok": aggressive.get_resolved_bite_timing_style() == FishBehaviorProfile.BiteTimingStyle.STRIKE,
		},
		{
			"name": "heavy auto-maps to load",
			"ok": heavy.get_resolved_bite_timing_style() == FishBehaviorProfile.BiteTimingStyle.LOAD,
		},
		{
			"name": "erratic auto-maps to feint",
			"ok": erratic.get_resolved_bite_timing_style() == FishBehaviorProfile.BiteTimingStyle.FEINT,
		},
		{
			"name": "explicit style override wins over archetype",
			"ok": int(override_read.get("style", -1)) == FishBehaviorProfile.BiteTimingStyle.FEINT,
		},
		{
			"name": "direct committed take is hookable immediately",
			"ok": is_zero_approx(float(direct_read.get("commit_delay", -1.0))) and not bool(direct_read.get("requires_wait", true)),
		},
		{
			"name": "tentative bite punishes an early hook set",
			"ok": bool(nibble_read.get("early_hook_is_miss", false)),
		},
		{
			"name": "strike telegraph is shorter than nibble",
			"ok": float(strike_read.get("commit_delay", 99.0)) < float(nibble_read.get("commit_delay", -1.0)),
		},
		{
			"name": "heavy load waits longer than nibble",
			"ok": float(load_read.get("commit_delay", -1.0)) > float(nibble_read.get("commit_delay", 99.0)),
		},
		{
			"name": "erratic feint waits at least as long as heavy load",
			"ok": float(feint_read.get("commit_delay", -1.0)) >= float(load_read.get("commit_delay", 99.0)),
		},
		{
			"name": "delay multiplier lengthens tentative read",
			"ok": float(slow_nibble_read.get("commit_delay", -1.0)) > float(nibble_read.get("commit_delay", 99.0)),
		},
		{
			"name": "policy preserves authored total bite window",
			"ok": is_equal_approx(float(load_read.get("total_window", 0.0)), 0.80),
		},
		{
			"name": "very short bites still preserve a usable hook window",
			"ok": float(short_feint.get("hook_window", 0.0)) >= Policy.MIN_HOOK_WINDOW - 0.001,
		},
	]

	for check in checks:
		total += 1
		if bool(check.get("ok", false)):
			passed += 1
		else:
			failures.append(str(check.get("name", "unnamed check")))

	return {
		"passed_count": passed,
		"test_count": total,
		"failures": failures,
	}


static func _profile(archetype: int) -> FishBehaviorProfile:
	var profile := FishBehaviorProfile.new()
	profile.archetype = archetype
	return profile
