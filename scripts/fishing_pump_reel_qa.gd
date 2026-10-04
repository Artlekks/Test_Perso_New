extends RefCounted
class_name FishingPumpReelQA

const Policy = preload("res://scripts/fishing_pump_reel_policy.gd")


static func run() -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	_record(
		report,
		"Released reel can start from light pressure",
		Policy.can_start(false, &"light", 0.20, false, 0.0),
		"Pump & Reel should begin from controlled light pressure."
	)
	_record(
		report,
		"Released reel can start from working pressure",
		Policy.can_start(false, &"working", 0.50, false, 0.0),
		"Working pressure should be the ideal Pump & Reel setup."
	)
	_record(
		report,
		"Held reel cannot start a pump cycle",
		not Policy.can_start(true, &"working", 0.50, false, 0.0),
		"The technique must require release -> lift -> reel cadence."
	)
	_record(
		report,
		"Slack blocks pump bonus",
		not Policy.can_start(false, &"slack", 0.02, false, 0.0),
		"An already slack line is not a valid leverage point."
	)
	_record(
		report,
		"Heavy pressure blocks pump bonus",
		not Policy.can_start(false, &"heavy", 0.85, false, 0.0),
		"Pump & Reel must not reward lifting into an already heavy line."
	)
	_record(
		report,
		"Overload blocks pump bonus",
		not Policy.can_start(false, &"overload", 1.0, false, 0.0),
		"Overloaded line pressure should remain a failure risk."
	)
	_record(
		report,
		"Thrash blocks pump bonus",
		not Policy.can_start(false, &"working", 0.50, true, 0.0),
		"Players should read a thrash instead of pumping blindly through it."
	)
	_record(
		report,
		"Cooldown prevents spam",
		not Policy.can_start(false, &"working", 0.50, false, 0.10),
		"Repeated S/K mashing must not stack free pump bonuses."
	)

	var light_impulse := Policy.get_lift_tension_impulse(0.15)
	var working_impulse := Policy.get_lift_tension_impulse(0.60)
	_record(
		report,
		"Light line gets stronger lift support",
		light_impulse > working_impulse,
		"Lift support should preserve tautness without pushing heavy pressure harder."
	)

	var edge_bonus := Policy.get_stamina_bonus_ratio(0.10)
	var working_bonus := Policy.get_stamina_bonus_ratio(0.52)
	_record(
		report,
		"Working pressure gives best fatigue bonus",
		working_bonus > edge_bonus,
		"Good pressure control should make Pump & Reel more efficient."
	)
	_record(
		report,
		"Fatigue bonus is deliberately small",
		working_bonus <= 0.04 and edge_bonus >= 0.0,
		"Pump & Reel should improve technique, not erase fish stamina."
	)
	_record(
		report,
		"Timing window and cooldown are bounded",
		Policy.PUMP_REEL_WINDOW_SECONDS >= 0.45
		and Policy.PUMP_REEL_WINDOW_SECONDS <= 0.90
		and Policy.PUMP_REEL_COOLDOWN_SECONDS > 0.0,
		"The cadence needs a readable but non-spammable timing window."
	)

	var snapshot := Policy.build_snapshot(
		true,
		0.30,
		0.10,
		Policy.RESULT_LIFTED,
		2,
		0.50
	)
	_record(
		report,
		"Snapshot is presentation-ready",
		bool(snapshot.get("active", false))
		and str(snapshot.get("last_result", "")) == "lifted"
		and int(snapshot.get("success_count", 0)) == 2,
		"Future mastery/UI should consume one stable read model."
	)

	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


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
