extends RefCounted
class_name FishingFightCombatQA

const PressurePolicy = preload(
	"res://scripts/fishing_fight_pressure_policy.gd"
)
const FightIntent = preload(
	"res://scripts/fishing_fight_intent.gd"
)


static func run() -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	var safe_min := 0.30
	var safe_max := 0.70
	var low := PressurePolicy.get_fatigue_multiplier(0.31, safe_min, safe_max)
	var middle := PressurePolicy.get_fatigue_multiplier(0.50, safe_min, safe_max)
	var high := PressurePolicy.get_fatigue_multiplier(0.69, safe_min, safe_max)

	_record(report, "Safe pressure has continuous leverage", low > 0.0 and middle > low and high > middle, "Higher legal line pressure should exhaust the fish faster without changing failure thresholds.")
	_record(report, "Middle pressure stays near baseline", absf(middle - 1.0) < 0.02, "The middle of the existing safe band should preserve the old fight pace.")
	_record(report, "Slack gives no fatigue leverage", is_zero_approx(PressurePolicy.get_fatigue_multiplier(0.20, safe_min, safe_max)), "A slack line should not tire the fish through reeling pressure.")
	_record(report, "Overload gives no fatigue leverage", is_zero_approx(PressurePolicy.get_fatigue_multiplier(0.80, safe_min, safe_max)), "Unsafe overload is a failure risk, not a secret faster exhaustion exploit.")
	_record(report, "Pressure bands are stable", PressurePolicy.get_band(0.35, safe_min, safe_max) == &"light" and PressurePolicy.get_band(0.50, safe_min, safe_max) == &"working" and PressurePolicy.get_band(0.65, safe_min, safe_max) == &"heavy", "Line Feel and future HUD work need stable light/working/heavy pressure vocabulary.")

	var surge := FightIntent.build_snapshot(FightIntent.SURGE_AWAY, 0.9, 1.0, 0.0, 0.0, 1.0, false)
	_record(report, "Surge intent is readable", surge.get("intent_id", &"") == &"surge_away" and str(surge.get("label", "")) == "RUN", "Fish movement choices should expose a stable intent instead of forcing UI to infer it from velocity.")

	var left_run := FightIntent.build_snapshot(FightIntent.SIDE_RUN, 0.8, 1.0, -1.0, 0.0, 0.6, false)
	var right_run := FightIntent.build_snapshot(FightIntent.SIDE_RUN, 0.8, 1.0, 1.0, 0.0, 0.6, false)
	_record(report, "Side-run direction is readable", str(left_run.get("label", "")) == "RUN LEFT" and str(right_run.get("label", "")) == "RUN RIGHT", "Counter-steering lessons need to know which way the fish is committing.")

	var dive := FightIntent.build_snapshot(FightIntent.DIVE, 0.8, 1.0, 0.1, -1.0, 0.8, false)
	_record(report, "Dive intent stays distinct", dive.get("intent_id", &"") == &"dive" and float(dive.get("depth", 0.0)) < -0.9, "Deep-water control must be able to distinguish a dive from generic resistance.")

	var thrash := FightIntent.build_snapshot(FightIntent.ERRATIC, 1.0, 0.4, 0.7, -0.3, 1.0, true)
	_record(report, "Thrash overrides normal intent label", thrash.get("intent_id", &"") == &"thrash" and str(thrash.get("label", "")) == "THRASH", "Sudden high-risk bursts need an explicit telegraph hook for presentation and mastery systems.")

	var pressure_snapshot := PressurePolicy.build_snapshot(0.69, safe_min, safe_max)
	_record(report, "Pressure snapshot is UI-ready", pressure_snapshot.get("band", &"") == &"heavy" and float(pressure_snapshot.get("safe_ratio", 0.0)) > 0.9, "Future Line Feel presentation should consume one read model rather than recompute fight rules.")

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
