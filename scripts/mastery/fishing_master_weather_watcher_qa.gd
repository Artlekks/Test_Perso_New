extends RefCounted
class_name FishingMasterWeatherWatcherQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_weather_watcher_policy.gd"
)
const MasteryServiceScript = preload(
	"res://scripts/mastery/fishing_mastery_service.gd"
)
const UnlockStateScript = preload(
	"res://scripts/fishing_unlock_state.gd"
)


static func run(mastery_catalog: Resource) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	var definition = mastery_catalog.get_technique(&"weather_sense") if mastery_catalog != null else null
	_record(report, "Weather Sense exists in mastery catalog",
		definition != null,
		"The master lesson requires the canonical weather_sense mastery.")
	if definition != null:
		_record(report, "Weather Watcher is the canonical teacher",
			StringName(str(definition.teacher_id)) == &"master_weather_watcher",
			"The encounter must use the authored teacher id.")
		_record(report, "Weather Sense remains observational",
			definition.has_capability(&"weather_sense"),
			"The lesson should unlock interpretation, not a hidden weather buff.")

	var unlock = UnlockStateScript.new()
	unlock.initialize()
	var mastery = MasteryServiceScript.new()
	mastery.configure(mastery_catalog, unlock)
	var wrong_teacher := mastery.learn_technique(&"weather_sense", &"wrong_master", false)
	_record(report, "Wrong master cannot teach Weather Sense",
		str(wrong_teacher.get("reason", "")) == "wrong_teacher",
		"Weather Sense must remain tied to Weather Watcher.")
	var ready := mastery.can_learn(&"weather_sense", &"master_weather_watcher")
	_record(report, "Weather Watcher lesson is independently learnable",
		bool(ready.get("can_learn", false)),
		"Weather reading is a foundational observation skill, not a rank gate.")
	var learned := mastery.learn_technique(&"weather_sense", &"master_weather_watcher", false)
	_record(report, "Weather Watcher can teach Weather Sense",
		bool(learned.get("success", false)),
		"A successful practical read must persist the canonical technique.")
	_record(report, "Learned lesson exposes Weather Sense capability",
		mastery.has_capability(&"weather_sense"),
		"Environment presentation should see the capability immediately.")

	_record(report, "Surface-biased profile selects surface",
		Policy.get_target_band(1.45, 1.00, 0.80) == &"surface",
		"A clear surface weather bias must teach a surface placement.")
	_record(report, "Mid-biased profile selects mid-water",
		Policy.get_target_band(0.85, 1.40, 0.95) == &"mid",
		"A clear middle-column bias must teach mid-water placement.")
	_record(report, "Deep-biased profile selects deep water",
		Policy.get_target_band(0.80, 1.00, 1.45) == &"deep",
		"A clear deep weather bias must teach deep placement.")
	_record(report, "Nearly even profile stays balanced",
		Policy.get_target_band(1.00, 1.03, 0.98) == &"even",
		"Neutral weather should not invent a false depth preference.")
	_record(report, "Near-tied strongest layers stay balanced",
		Policy.get_target_band(1.20, 1.18, 0.92) == &"even",
		"The lesson should not pretend a tiny top-two difference is meaningful.")
	_record(report, "Zeroed profile fails safely to balanced",
		Policy.get_target_band(0.0, 0.0, 0.0) == &"even",
		"Broken or empty activity data should fail closed.")

	_record(report, "Surface target accepts shallow lure",
		Policy.is_target_depth(&"surface", 0.20, 1.00),
		"The surface lesson must use actual depth ratio.")
	_record(report, "Surface target rejects deep lure",
		not Policy.is_target_depth(&"surface", 0.80, 1.00),
		"A deep lure should not satisfy a surface-biased weather read.")
	_record(report, "Mid target accepts middle lure",
		Policy.is_target_depth(&"mid", 0.50, 1.00),
		"Mid-water weather should be demonstrated in the middle column.")
	_record(report, "Mid target rejects shallow lure",
		not Policy.is_target_depth(&"mid", 0.20, 1.00),
		"The lesson must distinguish middle water from the surface.")
	_record(report, "Deep target accepts deep lure",
		Policy.is_target_depth(&"deep", 0.80, 1.00),
		"Deep-biased weather should use a genuinely deep lure position.")
	_record(report, "Deep target rejects shallow lure",
		not Policy.is_target_depth(&"deep", 0.20, 1.00),
		"A surface lure cannot demonstrate a deep weather read.")
	_record(report, "Balanced target accepts central column",
		Policy.is_target_depth(&"even", 0.50, 1.00),
		"Neutral conditions should reward a balanced placement.")
	_record(report, "Balanced target rejects extreme surface",
		not Policy.is_target_depth(&"even", 0.05, 1.00),
		"Balanced does not mean any arbitrary depth is correct.")
	_record(report, "Too-shallow water cannot satisfy lesson",
		not Policy.is_target_depth(&"mid", 0.10, 0.20),
		"The master needs a real water column to teach weather depth bias.")

	var first := Policy.advance_hold(0.0, &"mid", 0.50, 1.00, 0.70)
	_record(report, "Correct placement accumulates hold time",
		float(first.get("hold_seconds", 0.0)) > 0.69,
		"The player must maintain the favored layer rather than touch it once.")
	_record(report, "Partial hold remains incomplete",
		not bool(first.get("complete", false)),
		"A brief pass through the correct layer should not teach Weather Sense.")
	var reset := Policy.advance_hold(float(first.get("hold_seconds", 0.0)), &"mid", 0.90, 1.00, 0.20)
	_record(report, "Leaving favored layer resets continuous hold",
		is_zero_approx(float(reset.get("hold_seconds", -1.0))),
		"Hidden partial progress should not survive an incorrect placement.")
	var complete := Policy.advance_hold(0.70, &"mid", 0.50, 1.00, 0.70)
	_record(report, "Continuous correct placement completes lesson",
		bool(complete.get("complete", false)),
		"The authored hold duration needs one deterministic completion point.")
	_record(report, "Invalid water reports invalid state",
		not bool(Policy.advance_hold(0.5, &"mid", 0.10, 0.20, 1.0).get("valid_water", true)),
		"Shallow-water failure should be explicit for lesson feedback.")
	_record(report, "Progress ratio clamps at zero",
		is_zero_approx(Policy.get_progress_ratio(-2.0)),
		"UI feedback must remain stable for invalid negative state.")
	_record(report, "Progress ratio clamps at one",
		is_equal_approx(Policy.get_progress_ratio(99.0), 1.0),
		"Completed observation should never exceed 100 percent.")
	_record(report, "Surface label is readable",
		Policy.get_band_label(&"surface") == "SURFACE",
		"The master needs a clear teaching vocabulary.")
	_record(report, "Balanced label explains neutral weather",
		Policy.get_band_label(&"even") == "BALANCED MID-COLUMN",
		"Neutral conditions should be described as balance, not a fake bias.")

	mastery.free()
	unlock.free()
	return report


static func _record(
	report: Dictionary,
	name: String,
	passed: bool,
	failure_message: String
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [name, failure_message])
	report["failures"] = failures
