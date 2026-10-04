extends RefCounted
class_name FishingRunReadingQA

const Policy = preload("res://scripts/fishing_run_reading_policy.gd")


static func run() -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	var surge := _intent(&"surge_away", "RUN", 0.0, 0.80, false, 1.20)
	var left_run := _intent(&"side_run", "RUN LEFT", -0.85, 0.70, false, 1.10)
	var right_run := _intent(&"side_run", "RUN RIGHT", 0.85, 0.70, false, 1.10)
	var dive := _intent(&"dive", "DIVE", 0.0, 0.75, false, 1.20)
	var rise := _intent(&"rise", "RISE", 0.0, 0.55, false, 1.10)
	var erratic := _intent(&"erratic", "ERRATIC", 0.35, 0.70, false, 0.80)
	var thrash := _intent(&"side_run", "THRASH", -0.9, 1.0, true, 0.40)

	_record(report, "Surge asks player to ease", Policy.get_expected_response(surge) == Policy.RESPONSE_EASE, "A hard run should reward giving line instead of blindly holding K.")
	_record(report, "Dive asks player to ease", Policy.get_expected_response(dive) == Policy.RESPONSE_EASE, "A dive should use the same pressure-relief read as a power surge.")
	_record(report, "Rise asks player to reel", Policy.get_expected_response(rise) == Policy.RESPONSE_REEL, "A rising fish should reward taking line before slack develops.")
	_record(report, "Side run asks for counter steering", Policy.get_expected_response(left_run) == Policy.RESPONSE_COUNTER, "Directional runs should build on the existing A/D counter-steer mechanic.")
	_record(report, "Erratic asks for steady hands", Policy.get_expected_response(erratic) == Policy.RESPONSE_STEADY, "Erratic movement should punish chasing every twitch rather than adding another button.")
	_record(report, "Thrash overrides normal intent with ease", Policy.get_expected_response(thrash) == Policy.RESPONSE_EASE, "A thrash is a high-pressure event and should override the underlying run read.")

	_record(report, "Released K correctly reads a surge", Policy.is_response_matching(surge, false, 0.0), "Surge read should accept an actual reel release.")
	_record(report, "Held K does not read a surge", not Policy.is_response_matching(surge, true, 0.0), "Blindly holding K through a run must not score the read.")
	_record(report, "Left run is countered with right steering", Policy.is_response_matching(left_run, true, 1.0), "Counter-steering should require the opposite A/D direction while reeling.")
	_record(report, "Left run rejects same-direction steering", not Policy.is_response_matching(left_run, true, -1.0), "Following the fish's run is not counter pressure.")
	_record(report, "Right run is countered with left steering", Policy.is_response_matching(right_run, true, -1.0), "Both directional run signs must resolve symmetrically.")
	_record(report, "Rise is read by reeling", Policy.is_response_matching(rise, true, 0.0), "Taking line on a rise should be the readable opposite of easing on a dive.")
	_record(report, "Erratic read requires steady steering", Policy.is_response_matching(erratic, true, 0.0) and not Policy.is_response_matching(erratic, true, 1.0), "The player should maintain the reel without over-correcting erratic lateral movement.")

	var held := Policy.advance_match_time(0.0, true, 0.06)
	held = Policy.advance_match_time(held, true, 0.06)
	_record(report, "Correct response must be held briefly", Policy.is_read_complete(held), "A single matching frame should not award Reading the Run.")
	var reset := Policy.advance_match_time(0.08, false, 0.02)
	_record(report, "Breaking the response resets hold progress", is_zero_approx(reset), "The short confirmation hold prevents accidental reads from input noise.")

	var short_window := Policy.get_read_window_seconds(_intent(&"side_run", "RUN", 1.0, 0.5, false, 0.20))
	var long_window := Policy.get_read_window_seconds(_intent(&"side_run", "RUN", 1.0, 0.5, false, 4.0))
	_record(report, "Read windows stay within authored bounds", short_window >= Policy.MIN_READ_WINDOW_SECONDS and long_window <= Policy.MAX_READ_WINDOW_SECONDS and long_window > short_window, "Fast fish need readable windows without making slow runs trivial.")

	var low_bonus := Policy.get_stamina_control_bonus_ratio(_intent(&"rise", "RISE", 0.0, 0.0, false, 1.0))
	var high_bonus := Policy.get_stamina_control_bonus_ratio(_intent(&"rise", "RISE", 0.0, 1.0, false, 1.0))
	_record(report, "Run-read reward is small and intensity-scaled", low_bonus >= 0.0 and high_bonus > low_bonus and high_bonus <= 0.02, "Reading the Run should improve control without replacing normal fatigue and Pump & Reel.")

	var snapshot := Policy.build_snapshot(true, 0.4, 0.06, Policy.RESPONSE_COUNTER, Policy.RESULT_READING, 2, left_run)
	_record(report, "Snapshot is presentation-ready", bool(snapshot.get("active", false)) and str(snapshot.get("expected_response", "")) == "counter" and str(snapshot.get("intent_label", "")) == "RUN LEFT" and int(snapshot.get("success_count", 0)) == 2, "Future mastery/UI should consume one stable read model instead of re-deriving intent rules.")

	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


static func _intent(
	intent_id: StringName,
	label: String,
	lateral: float,
	intensity: float,
	thrashing: bool,
	duration: float
) -> Dictionary:
	return {
		"intent_id": intent_id,
		"label": label,
		"lateral": lateral,
		"intensity": intensity,
		"thrashing": thrashing,
		"duration": duration,
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
