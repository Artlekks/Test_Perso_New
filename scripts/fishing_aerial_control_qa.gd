extends RefCounted
class_name FishingAerialControlQA

const Policy = preload("res://scripts/fishing_aerial_control_policy.gd")


static func run() -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	var flying := _profile(
		FishBehaviorProfile.FightArchetype.DARTING,
		1.0,
		0.4, 0.8, 0.2, 3.5, 1.2
	)
	var rainbow := _profile(
		FishBehaviorProfile.FightArchetype.DARTING,
		0.95,
		0.9, 1.5, 0.5, 1.8, 1.6
	)
	var salmon := _profile(
		FishBehaviorProfile.FightArchetype.AGGRESSIVE,
		0.9,
		1.8, 1.5, 0.6, 1.7, 0.7
	)
	var heavy := _profile(
		FishBehaviorProfile.FightArchetype.HEAVY,
		0.9,
		2.0, 0.5, 3.2, 0.05, 0.2
	)
	var low_vertical := _profile(
		FishBehaviorProfile.FightArchetype.STEADY,
		0.4,
		0.1, 0.5, 0.5, 1.2, 1.0
	)

	var rise := _intent(&"rise", "RISE", 0.78, 1.0)
	var dive := _intent(&"dive", "DIVE", 0.78, 1.0)
	var thrash_rise := _intent(&"rise", "THRASH", 1.0, 0.5, true)

	_record(report, "Only clean RISE intents can breach", Policy.is_rise_intent(rise) and not Policy.is_rise_intent(dive) and not Policy.is_rise_intent(thrash_rise), "Aerial control must extend the existing rise vocabulary instead of turning every intent into a jump.")

	var flying_chance := Policy.get_breach_chance(flying)
	var rainbow_chance := Policy.get_breach_chance(rainbow)
	var heavy_chance := Policy.get_breach_chance(heavy)
	_record(report, "Rise-heavy fish breach more often", flying_chance > rainbow_chance and rainbow_chance > heavy_chance, "Existing species rise weights should materially drive aerial frequency.")
	_record(report, "Low-vertical profiles do not breach", is_zero_approx(Policy.get_breach_chance(low_vertical)), "Slow/low-vertical species should not become aerial simply because they have a rise weight.")
	_record(report, "Breach chance is capped", flying_chance > 0.0 and flying_chance <= Policy.MAX_BREACH_CHANCE, "A rise-heavy fish should be aerial but never breach on every rise.")

	_record(report, "Cooldown suppresses repeat breaches", not Policy.should_start(rise, flying, 0.0, 0.5), "Aerial events need spacing so repeated RISE selections cannot spam the player.")
	_record(report, "Non-rise intent cannot start aerial control", not Policy.should_start(dive, flying, 0.0, 0.0), "The event must remain attached to RISE.")
	_record(report, "Visual-family gate can disable a breach", not Policy.should_start(rise, flying, 0.0, 0.0, false), "Non-fish silhouette families can opt out without changing their behavior profile.")
	_record(report, "Chance roll is deterministic at policy boundary", Policy.should_start(rise, flying, flying_chance * 0.5, 0.0) and not Policy.should_start(rise, flying, minf(flying_chance + 0.10, 1.0), 0.0), "Encounter supplies randomness; policy should remain unit-testable.")

	var flying_low_security := Policy.get_expected_response(flying, 0.90)
	var rainbow_low_security := Policy.get_expected_response(rainbow, 0.90)
	var salmon_secure := Policy.get_expected_response(salmon, 1.20)
	_record(report, "Acrobatic risers ask for bow/low rod", flying_low_security == Policy.RESPONSE_BOW_LOW and rainbow_low_security == Policy.RESPONSE_BOW_LOW, "Fast aerial fish should not be solved by blindly holding K through the jump.")
	_record(report, "Power riser can ask for high follow", salmon_secure == Policy.RESPONSE_HIGH_FOLLOW, "Aerial response must not collapse into one universal release rule.")

	var borderline := _profile(
		FishBehaviorProfile.FightArchetype.STEADY,
		0.9,
		0.3, 1.2, 0.4, 1.7, 1.3
	)
	var borderline_low := Policy.get_expected_response(borderline, 0.85)
	var borderline_secure := Policy.get_expected_response(borderline, 1.30)
	_record(report, "Hook security can change a borderline response", borderline_low == Policy.RESPONSE_BOW_LOW and borderline_secure == Policy.RESPONSE_HIGH_FOLLOW, "Tackle should matter to aerial control without rewriting fish strength/personality.")

	_record(report, "Bow response requires released K plus low rod", Policy.is_response_matching(Policy.RESPONSE_BOW_LOW, false, -1.0) and not Policy.is_response_matching(Policy.RESPONSE_BOW_LOW, true, -1.0) and not Policy.is_response_matching(Policy.RESPONSE_BOW_LOW, false, 0.0), "The low-rod lesson must use the established K + W pressure controls, not a new button.")
	_record(report, "High follow requires K plus high rod", Policy.is_response_matching(Policy.RESPONSE_HIGH_FOLLOW, true, 1.0) and not Policy.is_response_matching(Policy.RESPONSE_HIGH_FOLLOW, false, 1.0) and not Policy.is_response_matching(Policy.RESPONSE_HIGH_FOLLOW, true, 0.0), "Power breaches should ask for a different existing-control response.")

	var held := Policy.advance_match_time(0.0, true, 0.07)
	held = Policy.advance_match_time(held, true, 0.07)
	_record(report, "Aerial response needs a brief hold", Policy.is_response_complete(held), "One noisy input frame should not resolve a breach.")
	_record(report, "Wrong input resets aerial hold", is_zero_approx(Policy.advance_match_time(0.10, false, 0.02)), "The player must maintain the response rather than tap accidentally.")

	var short_window := Policy.get_window_seconds(_intent(&"rise", "RISE", 0.7, 0.20))
	var long_window := Policy.get_window_seconds(_intent(&"rise", "RISE", 0.7, 4.0))
	_record(report, "Aerial windows stay bounded", short_window >= Policy.MIN_WINDOW_SECONDS and long_window <= Policy.MAX_WINDOW_SECONDS and long_window > short_window, "Fast/slow fish can vary the read without becoming unreadable or trivial.")

	var bow_fail_weak := Policy.get_failure_tension_impulse(Policy.RESPONSE_BOW_LOW, 0.0, 1.0)
	var bow_fail_hard := Policy.get_failure_tension_impulse(Policy.RESPONSE_BOW_LOW, 1.0, 1.0)
	var follow_fail := Policy.get_failure_tension_impulse(Policy.RESPONSE_HIGH_FOLLOW, 1.0, 1.0)
	_record(report, "Wrong bow response spikes tension", bow_fail_weak > 0.0 and bow_fail_hard > bow_fail_weak and bow_fail_hard < 0.20, "Failure should create line-break pressure without directly forcing a terminal result.")
	_record(report, "Wrong high-follow response creates slack", follow_fail < 0.0 and absf(follow_fail) < 0.20, "Missing a power breach should feed the existing hook-off system instead of inventing a new failure state.")

	var bow_success := Policy.get_success_stabilization_impulse(Policy.RESPONSE_BOW_LOW, 0.8)
	var follow_success := Policy.get_success_stabilization_impulse(Policy.RESPONSE_HIGH_FOLLOW, 0.8)
	_record(report, "Correct responses get mirrored stabilization", bow_success > 0.0 and follow_success < 0.0 and is_equal_approx(absf(bow_success), absf(follow_success)), "Required low/high rod inputs should be nudged back toward safe pressure after a successful read.")

	var snapshot := Policy.build_snapshot(true, 0.5, 0.07, Policy.RESPONSE_BOW_LOW, Policy.RESULT_READING, 2, rise, flying, 0.95, 0.0)
	_record(report, "Snapshot exposes species/tackle read", bool(snapshot.get("active", false)) and str(snapshot.get("expected_response", "")) == "bow_low" and float(snapshot.get("breach_chance", 0.0)) > 0.0 and is_equal_approx(float(snapshot.get("hook_security", 0.0)), 0.95), "Debug/UI should consume one stable aerial-control snapshot.")

	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


static func _profile(
	archetype: int,
	vertical: float,
	surge: float,
	side: float,
	dive: float,
	rise: float,
	erratic: float
) -> FishBehaviorProfile:
	var profile := FishBehaviorProfile.new()
	profile.archetype = archetype
	profile.vertical_activity = vertical
	profile.surge_weight = surge
	profile.side_run_weight = side
	profile.dive_weight = dive
	profile.rise_weight = rise
	profile.erratic_weight = erratic
	return profile


static func _intent(
	intent_id: StringName,
	label: String,
	intensity: float,
	duration: float,
	thrashing: bool = false
) -> Dictionary:
	return {
		"intent_id": intent_id,
		"label": label,
		"lateral": 0.0,
		"intensity": intensity,
		"duration": duration,
		"thrashing": thrashing,
	}


static func _record(
	report: Dictionary,
	name: String,
	passed: bool,
	detail: String
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return

	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [name, detail])
	report["failures"] = failures
