extends RefCounted
class_name FishingMasterSignReaderQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_sign_reader_policy.gd"
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

	var definition = (
		mastery_catalog.get_technique(&"read_fish_sign")
		if mastery_catalog != null
		else null
	)
	_record(report, "Read Fish Sign exists", definition != null, "The master requires the canonical read_fish_sign technique.")
	if definition != null:
		_record(report, "Sign Reader is canonical teacher", StringName(str(definition.teacher_id)) == &"master_sign_reader", "The lesson must use the authored teacher id.")
		_record(report, "Read Fish Sign exposes capability", definition.has_capability(&"read_fish_sign"), "The lesson should unlock observation, not a hidden fish buff.")
		_record(report, "Read Fish Sign has no forced prerequisite", definition.prerequisite_ids.is_empty(), "The observation lesson should remain independently teachable before the Nature Guide capstone.")

	var unlock = UnlockStateScript.new()
	unlock.initialize()
	var mastery = MasteryServiceScript.new()
	mastery.configure(mastery_catalog, unlock)
	var wrong := mastery.learn_technique(&"read_fish_sign", &"wrong_master", false)
	_record(report, "Wrong master cannot teach Read Fish Sign", str(wrong.get("reason", "")) == "wrong_teacher", "Master identity must remain authoritative.")
	var ready := mastery.can_learn(&"read_fish_sign", &"master_sign_reader")
	_record(report, "Sign Reader lesson is available from canonical data", bool(ready.get("can_learn", false)), "The in-world lesson should not need a debug unlock.")
	var learned := mastery.learn_technique(&"read_fish_sign", &"master_sign_reader", false)
	_record(report, "Sign Reader teaches Read Fish Sign", bool(learned.get("success", false)), "A successful lesson must persist through the mastery service.")
	_record(report, "Learned lesson exposes runtime capability", mastery.has_capability(&"read_fish_sign"), "Fish-sign presentation should see the capability immediately.")

	var unavailable := {
		"available": false,
		"sign_count": 3,
		"dominant_sign": &"surface_boil",
	}
	var quiet := {
		"available": true,
		"sign_count": 0,
		"dominant_sign": &"none",
	}
	var boil := {
		"available": true,
		"sign_count": 2,
		"dominant_sign": &"surface_boil",
	}
	var bubbles := {
		"available": true,
		"sign_count": 1,
		"dominant_sign": &"deep_bubbles",
	}
	_record(report, "Unavailable sign data cannot teach the lesson", not Policy.has_clear_sign(unavailable), "The master should wait for the real ambient-fish runtime instead of trusting stale data.")
	_record(report, "Quiet water is not a clear sign", not Policy.has_clear_sign(quiet), "The master must not teach from empty water.")
	_record(report, "Surface boil is a clear sign", Policy.has_clear_sign(boil), "A real visible sign should be teachable.")
	_record(report, "Deep bubbles are a clear indirect sign", Policy.has_clear_sign(bubbles), "Read Fish Sign includes indirect evidence from deeper fish.")
	_record(report, "Surface boil label is stable", Policy.get_sign_label(&"surface_boil") == "surface boil", "Lesson feedback needs a deterministic sign vocabulary.")
	_record(report, "Feeding-turn label is stable", Policy.get_sign_label(&"feeding_turn") == "feeding turn", "The master should name feeding behavior consistently.")
	_record(report, "Baitfish-scatter label is stable", Policy.get_sign_label(&"baitfish_scatter") == "baitfish scatter", "The master should name small-fish movement consistently.")
	_record(report, "Deep-bubbles label is stable", Policy.get_sign_label(&"deep_bubbles") == "deep bubbles", "The master should name deep indirect activity consistently.")
	_record(report, "Shadow-track label is stable", Policy.get_sign_label(&"shadow_track") == "shadow track", "The baseline visible movement sign needs a stable name.")

	var first := Policy.advance_observation(0.0, &"none", boil, 0.60)
	_record(report, "First clear sign starts a stable read", float(first.get("stable_seconds", 0.0)) > 0.59 and StringName(str(first.get("tracked_sign", ""))) == &"surface_boil", "Observation should begin only from a real sign.")
	var second := Policy.advance_observation(float(first.get("stable_seconds", 0.0)), StringName(str(first.get("tracked_sign", &"none"))), boil, 0.70)
	_record(report, "Same sign accumulates observation time", float(second.get("stable_seconds", 0.0)) > 1.29, "The player must watch one pattern hold instead of sampling unrelated moments.")
	_record(report, "Stable observation reaches completion", Policy.is_observation_complete(float(second.get("stable_seconds", 0.0))), "The lesson needs a deterministic report point.")
	_record(report, "Partial observation is not complete", not Policy.is_observation_complete(0.80), "Calling a sign too early should not pass.")
	var changed := Policy.advance_observation(0.90, &"surface_boil", bubbles, 0.10)
	_record(report, "Changing sign resets the stable read", float(changed.get("stable_seconds", 0.0)) <= 0.101 and StringName(str(changed.get("tracked_sign", ""))) == &"deep_bubbles", "Different water signs must not be stitched into one observation.")
	var lost := Policy.advance_observation(0.90, &"surface_boil", quiet, 0.10)
	_record(report, "Losing the sign clears progress", is_zero_approx(float(lost.get("stable_seconds", -1.0))) and StringName(str(lost.get("tracked_sign", "x"))) == &"none", "The lesson should wait for a genuinely persistent sign.")
	_record(report, "Progress ratio clamps at zero", is_zero_approx(Policy.get_progress_ratio(-2.0)), "Lesson UI should never report negative progress.")
	_record(report, "Progress ratio clamps at one", is_equal_approx(Policy.get_progress_ratio(99.0), 1.0), "Lesson UI should never exceed completion.")

	mastery.free()
	unlock.free()
	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


static func _record(report: Dictionary, name: String, passed: bool, detail: String) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [name, detail])
	report["failures"] = failures
