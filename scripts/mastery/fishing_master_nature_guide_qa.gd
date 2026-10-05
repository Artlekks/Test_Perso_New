extends RefCounted
class_name FishingMasterNatureGuideQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_nature_guide_policy.gd"
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
		mastery_catalog.get_technique(&"one_with_nature")
		if mastery_catalog != null
		else null
	)
	_record(report, "One With Nature exists", definition != null, "Nature Guide requires the canonical capstone technique.")
	if definition != null:
		_record(report, "Nature Guide is canonical teacher", StringName(str(definition.teacher_id)) == &"master_nature_guide", "The lesson must use the authored teacher id.")
		_record(report, "Capstone exposes One With Nature capability", definition.has_capability(&"one_with_nature"), "The lesson should unlock the existing runtime capability.")
		_record(report, "Capstone requires Quiet Approach", _has_prerequisite(definition, &"quiet_approach"), "Fieldcraft synthesis must build on stillness.")
		_record(report, "Capstone requires Read Fish Sign", _has_prerequisite(definition, &"read_fish_sign"), "Fieldcraft synthesis must build on observation.")

	var unlock = UnlockStateScript.new()
	unlock.initialize()
	var mastery = MasteryServiceScript.new()
	mastery.configure(mastery_catalog, unlock)
	var blocked := mastery.learn_technique(&"one_with_nature", &"master_nature_guide", false)
	_record(report, "Capstone is blocked before prerequisites", str(blocked.get("reason", "")) == "missing_prerequisite", "Nature Guide must not bypass the mastery tree.")

	var quiet = mastery_catalog.get_technique(&"quiet_approach") if mastery_catalog != null else null
	var sign_definition = mastery_catalog.get_technique(&"read_fish_sign") if mastery_catalog != null else null
	if quiet != null:
		mastery.learn_technique(&"quiet_approach", quiet.teacher_id, false)
	var still_blocked := mastery.can_learn(&"one_with_nature", &"master_nature_guide")
	_record(report, "Quiet Approach alone is insufficient", not bool(still_blocked.get("can_learn", false)), "Read Fish Sign must still matter.")
	if sign_definition != null:
		mastery.learn_technique(&"read_fish_sign", sign_definition.teacher_id, false)
	var ready := mastery.can_learn(&"one_with_nature", &"master_nature_guide")
	_record(report, "Both prerequisites unlock the Nature Guide lesson", bool(ready.get("can_learn", false)), "The in-world lesson should become available through normal mastery progression.")
	var wrong := mastery.learn_technique(&"one_with_nature", &"wrong_master", false)
	_record(report, "Wrong master cannot teach the capstone", str(wrong.get("reason", "")) == "wrong_teacher", "Teacher identity remains authoritative.")
	var learned := mastery.learn_technique(&"one_with_nature", &"master_nature_guide", false)
	_record(report, "Nature Guide can teach the capstone", bool(learned.get("success", false)), "A completed lesson must use the existing mastery service.")
	_record(report, "Learned lesson exposes runtime capability", mastery.has_capability(&"one_with_nature"), "Ambient fish should see the learned capstone immediately.")

	_record(report, "Lesson settle time matches runtime capstone", is_equal_approx(Policy.REQUIRED_SETTLE_SECONDS, 3.5), "The tutorial should teach the exact runtime stillness window.")
	_record(report, "Lesson disturbance threshold matches runtime capstone", is_equal_approx(Policy.MAX_SETTLED_DISTURBANCE, 0.06), "The tutorial should not use an easier stillness rule than gameplay.")
	_record(report, "Lesson presentation floor matches runtime capstone", is_equal_approx(Policy.MIN_NATURAL_PRESENTATION, 0.92), "The tutorial should teach the actual natural-presentation threshold.")
	_record(report, "Wary target threshold matches fish-sign vocabulary", is_equal_approx(Policy.MIN_WARY_WARINESS, 0.48), "A fish classified as wary by Read Fish Sign should qualify for the synthesis lesson.")
	_record(report, "Target must stay close to the lure", Policy.MAX_TARGET_DISTANCE_METERS <= 1.75, "The lesson should demonstrate presentation to a real nearby fish rather than any fish in the zone.")
	_record(report, "Presentation hold is deliberate but short", Policy.REQUIRED_PRESENTATION_SECONDS >= 0.70 and Policy.REQUIRED_PRESENTATION_SECONDS <= 0.80, "The final demonstration should be readable without becoming another waiting lesson.")

	var settle := Policy.advance_settle_time(0.0, 0.0, 1.5)
	_record(report, "Quiet time builds settle progress", settle > 1.49 and settle < Policy.REQUIRED_SETTLE_SECONDS, "The player must genuinely become still.")
	settle = Policy.advance_settle_time(settle, 0.02, 2.1)
	_record(report, "Sustained quiet completes the settle", Policy.is_settled(settle), "Low residual disturbance should allow the lesson to enter presentation.")
	var broken := Policy.advance_settle_time(settle, 0.25, 0.1)
	_record(report, "Movement resets settle progress", is_zero_approx(broken), "One With Nature cannot be taught while the player keeps moving.")
	_record(report, "Natural presentation threshold passes", Policy.is_natural_presentation(0.92), "The exact capstone floor should count.")
	_record(report, "Forced presentation fails", not Policy.is_natural_presentation(0.91), "The lesson must not round a poor retrieve up to success.")
	_record(report, "Wary readable fish qualifies", Policy.is_wary_target(0.48, 1.0, true), "A real wary visible fish should be a valid lesson target.")
	_record(report, "Bold fish does not qualify", not Policy.is_wary_target(0.47, 1.0, true), "The capstone is specifically about sensitive fish.")
	_record(report, "Unreadable fish does not qualify", not Policy.is_wary_target(0.80, 1.0, false), "The lesson must synthesize Read Fish Sign rather than reveal hidden fish.")
	_record(report, "Distant fish does not qualify", not Policy.is_wary_target(0.80, 2.0, true), "The player must actually present the lure to the target.")

	var partial := Policy.advance_presentation_time(0.0, Policy.REQUIRED_SETTLE_SECONDS, 1.0, 0.80, 1.0, true, true, 0.35)
	_record(report, "Valid synthesis starts presentation hold", partial > 0.34 and partial < Policy.REQUIRED_PRESENTATION_SECONDS, "All real fieldcraft conditions should accumulate the final demonstration.")
	var finished := Policy.advance_presentation_time(partial, Policy.REQUIRED_SETTLE_SECONDS, 1.0, 0.80, 1.0, true, true, 0.45)
	_record(report, "Continuous valid synthesis completes lesson", Policy.is_complete(Policy.REQUIRED_SETTLE_SECONDS, finished), "The final demonstration should complete only after a stable natural presentation.")
	var no_sign := Policy.advance_presentation_time(0.50, Policy.REQUIRED_SETTLE_SECONDS, 1.0, 0.80, 1.0, true, false, 0.10)
	_record(report, "Losing the fish sign resets presentation hold", is_zero_approx(no_sign), "Read Fish Sign must stay part of the capstone lesson.")
	var poor := Policy.advance_presentation_time(0.50, Policy.REQUIRED_SETTLE_SECONDS, 0.70, 0.80, 1.0, true, true, 0.10)
	_record(report, "Poor presentation resets final hold", is_zero_approx(poor), "Stillness alone must not teach One With Nature.")
	var bold := Policy.advance_presentation_time(0.50, Policy.REQUIRED_SETTLE_SECONDS, 1.0, 0.20, 1.0, true, true, 0.10)
	_record(report, "Bold target resets final hold", is_zero_approx(bold), "The lesson should prove control around a fish that actually cares about disturbance.")
	var far := Policy.advance_presentation_time(0.50, Policy.REQUIRED_SETTLE_SECONDS, 1.0, 0.80, 3.0, true, true, 0.10)
	_record(report, "Distant target resets final hold", is_zero_approx(far), "A natural lure somewhere else in the zone is not a valid demonstration.")
	var unsettled := Policy.advance_presentation_time(0.50, 1.0, 1.0, 0.80, 1.0, true, true, 0.10)
	_record(report, "Breaking stillness resets final hold", is_zero_approx(unsettled), "The two halves of the capstone cannot be completed independently.")
	_record(report, "Incomplete presentation does not finish lesson", not Policy.is_complete(Policy.REQUIRED_SETTLE_SECONDS, 0.30), "The master should not grant the skill on settle alone.")
	_record(report, "Settle progress clamps to zero", is_zero_approx(Policy.get_settle_progress_ratio(-1.0)), "Lesson feedback must never go negative.")
	_record(report, "Settle progress clamps to one", is_equal_approx(Policy.get_settle_progress_ratio(99.0), 1.0), "Lesson feedback must never exceed completion.")
	_record(report, "Presentation progress clamps to zero", is_zero_approx(Policy.get_presentation_progress_ratio(-1.0)), "Final demonstration feedback must never go negative.")
	_record(report, "Presentation progress clamps to one", is_equal_approx(Policy.get_presentation_progress_ratio(99.0), 1.0), "Final demonstration feedback must never exceed completion.")

	mastery.free()
	unlock.free()
	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


static func _has_prerequisite(definition, prerequisite_id: StringName) -> bool:
	if definition == null:
		return false
	for raw_id in definition.prerequisite_ids:
		if str(raw_id) == str(prerequisite_id):
			return true
	return false


static func _record(report: Dictionary, name: String, passed: bool, detail: String) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [name, detail])
	report["failures"] = failures
