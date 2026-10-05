extends RefCounted
class_name FishingMasterDriftAnglerQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_drift_angler_policy.gd"
)
const ReadCurrentResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/read_current.tres"
)
const DriftCastingResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/drift_casting.tres"
)


static func run(
	mastery_catalog: FishingMasteryTechniqueCatalog
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	if mastery_catalog != null and mastery_catalog.has_method("ensure_technique"):
		mastery_catalog.ensure_technique(ReadCurrentResource)
		mastery_catalog.ensure_technique(DriftCastingResource)
	var definition := (
		mastery_catalog.get_technique(&"drift_casting")
		if mastery_catalog != null
		else null
	)
	_record(report, "Drift Casting exists", definition != null, "The lesson must teach the canonical Drift Casting definition.")
	_record(report, "Drift Angler is canonical teacher", definition != null and definition.teacher_id == &"master_drift_angler", "The in-world lesson must preserve the authored teacher identity.")
	_record(report, "Drift Casting requires Read Current", definition != null and _has_prerequisite(definition, &"read_current"), "Drift Casting must build on current reading.")
	_record(report, "Drift Casting exposes current compensation", definition != null and definition.has_capability(&"current_compensation"), "Learning the technique should expose the existing prediction capability.")

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var mastery := FishingMasteryService.new()
	mastery.configure(mastery_catalog, unlock)
	var blocked := mastery.learn_technique(&"drift_casting", &"master_drift_angler", false)
	_record(report, "Prerequisite blocks early Drift Casting", str(blocked.get("reason", "")) == "missing_prerequisite", "The master lesson must not bypass Read Current.")
	var read_current := mastery.learn_technique(&"read_current", &"master_current_reader", false)
	_record(report, "Read Current can satisfy prerequisite", bool(read_current.get("success", false)), "The existing Current Reader lesson should unlock the prerequisite normally.")
	var wrong_teacher := mastery.learn_technique(&"drift_casting", &"wrong_master", false)
	_record(report, "Wrong teacher cannot teach Drift Casting", str(wrong_teacher.get("reason", "")) == "wrong_teacher", "Teacher identity must remain authoritative.")
	var learned := mastery.learn_technique(&"drift_casting", &"master_drift_angler", false)
	_record(report, "Drift Angler can teach Drift Casting", bool(learned.get("success", false)), "Completing the lesson must unlock the canonical technique.")
	_record(report, "Learned technique exposes drift preview", mastery.has_capability(&"current_compensation"), "The lesson should reveal the existing drift-path preview, not create new physics.")

	var across := Policy.evaluate_cast(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.05, 0.0, 0.0)
	)
	_record(report, "Across-current cast qualifies", bool(across.get("compensated_cast", false)), "A perpendicular cast should demonstrate compensation.")
	_record(report, "Across-current alignment is near zero", absf(float(across.get("alignment", 1.0))) < 0.01, "Policy should measure cast/current geometry correctly.")

	var upstream := Policy.evaluate_cast(
		Vector3.ZERO,
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.05, 0.0, 0.0)
	)
	_record(report, "Upstream cast qualifies", bool(upstream.get("compensated_cast", false)) and bool(upstream.get("upstream_cast", false)), "Casting against the flow should be a valid Drift Casting setup.")

	var downstream := Policy.evaluate_cast(
		Vector3.ZERO,
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.05, 0.0, 0.0)
	)
	_record(report, "Straight-downstream cast is rejected", not bool(downstream.get("compensated_cast", true)), "Throwing with the current should not count as compensation.")

	var still_water := Policy.evaluate_cast(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.001, 0.0, 0.0)
	)
	_record(report, "Still water cannot teach Drift Casting", not bool(still_water.get("active_water", true)) and not bool(still_water.get("compensated_cast", true)), "The lesson requires real moving water.")

	var short_cast := Policy.evaluate_cast(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 0.10),
		Vector3(0.05, 0.0, 0.0)
	)
	_record(report, "Drop-at-feet cast is rejected", not bool(short_cast.get("long_enough", true)), "The player should make a meaningful cast before using the current.")

	var along_step := Policy.get_along_current_step(
		Vector3.ZERO,
		Vector3(0.06, 0.0, 0.0),
		Vector3(0.05, 0.0, 0.0)
	)
	_record(report, "Downstream passive motion counts", along_step > 0.059, "Current-carried displacement should advance the lesson.")
	var against_step := Policy.get_along_current_step(
		Vector3.ZERO,
		Vector3(-0.06, 0.0, 0.0),
		Vector3(0.05, 0.0, 0.0)
	)
	_record(report, "Against-current motion does not count", is_zero_approx(against_step), "Dragging against the flow must not fake passive drift.")

	var cross_track := Policy.get_cross_track_drift(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.05, 0.0, 1.0)
	)
	_record(report, "Across-flow drift leaves cast line", cross_track > 0.049, "An across-current cast should visibly bend away from its original cast line.")
	var no_cross_track := Policy.get_cross_track_drift(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, 1.08)
	)
	_record(report, "Motion along cast line has no cross-track drift", is_zero_approx(no_cross_track), "Pure cast-direction movement should not satisfy the across-flow geometry requirement.")

	var reeled := Policy.advance_observation(
		0.8,
		0.03,
		0.02,
		Vector3.ZERO,
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.02, 0.0, 1.0),
		Vector3(0.04, 0.0, 1.0),
		Vector3(0.05, 0.0, 0.0),
		0.0,
		true,
		0.5
	)
	_record(report, "Reeling resets passive-drift demonstration", bool(reeled.get("reset", false)) and is_zero_approx(float(reeled.get("observation_seconds", -1.0))), "Drift Casting should be demonstrated by the water, not by K input.")

	var paused := Policy.advance_observation(
		0.6,
		0.02,
		0.01,
		Vector3.ZERO,
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.01, 0.0, 1.0),
		Vector3(0.02, 0.0, 1.0),
		Vector3(0.001, 0.0, 0.0),
		0.0,
		false,
		0.5
	)
	_record(report, "Weak current pauses lesson progress", is_equal_approx(float(paused.get("observation_seconds", 0.0)), 0.6), "A temporary calm pocket should not fabricate current movement.")

	var advanced := Policy.advance_observation(
		0.0,
		0.0,
		0.0,
		Vector3.ZERO,
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.06, 0.0, 1.0),
		Vector3(0.05, 0.0, 0.0),
		0.0,
		false,
		1.0
	)
	_record(report, "Valid drift advances time and distance", float(advanced.get("observation_seconds", 0.0)) > 0.99 and float(advanced.get("along_current_drift_meters", 0.0)) > 0.059, "A passive across-current drift should advance the real lesson dimensions.")
	_record(report, "Valid across drift records geometry", float(advanced.get("max_cross_track_drift_meters", 0.0)) > 0.059, "The lesson should remember the largest real cross-track displacement.")

	_record(report, "Time alone cannot complete", not Policy.is_complete(Policy.REQUIRED_OBSERVATION_SECONDS + 1.0, 0.0, 1.0, false), "Waiting without current-carried distance should not teach Drift Casting.")
	_record(report, "Distance alone cannot complete", not Policy.is_complete(0.1, Policy.REQUIRED_ALONG_CURRENT_DRIFT_METERS + 1.0, 1.0, false), "A single displacement spike should not teach the technique.")
	_record(report, "Across cast needs cross-track geometry", not Policy.is_complete(2.0, 0.10, 0.0, false), "An across-flow setup must actually bend away from the original cast line.")
	_record(report, "Across cast can complete", Policy.is_complete(2.0, 0.10, 0.04, false), "Sustained passive drift with real cross-track movement should complete the lesson.")
	_record(report, "Upstream cast can complete without cross-track", Policy.is_complete(2.0, 0.10, 0.0, true), "An upstream cast already demonstrates compensation geometry and should not need lateral displacement.")
	var half_progress := Policy.get_progress_ratio(Policy.REQUIRED_OBSERVATION_SECONDS, Policy.REQUIRED_ALONG_CURRENT_DRIFT_METERS, Policy.REQUIRED_CROSS_TRACK_DRIFT_METERS * 0.5, false)
	_record(report, "Progress ratio respects weakest requirement", half_progress > 0.49 and half_progress < 0.51, "Lesson feedback must not show completion while geometry still lags.")

	mastery.free()
	unlock.free()
	return report


static func _has_prerequisite(
	definition: FishingMasteryTechniqueDefinition,
	prerequisite_id: StringName
) -> bool:
	if definition == null:
		return false
	for raw_id in definition.prerequisite_ids:
		if str(raw_id) == str(prerequisite_id):
			return true
	return false


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
