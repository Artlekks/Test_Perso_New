extends RefCounted
class_name FishingMasterCurrentReaderQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_current_reader_policy.gd"
)
const ReadCurrentResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/read_current.tres"
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
	var definition := (
		mastery_catalog.get_technique(&"read_current")
		if mastery_catalog != null
		else null
	)
	_record(
		report,
		"Read Current exists for the master lesson",
		definition != null,
		"The in-world lesson must teach the canonical mastery definition."
	)
	_record(
		report,
		"Current Reader is the canonical teacher",
		definition != null and definition.teacher_id == &"master_current_reader",
		"The lesson must use the same teacher identity already authored in mastery data."
	)
	_record(
		report,
		"Read Current exposes the read-current capability",
		definition != null and definition.has_capability(&"read_current"),
		"Completing the lesson must unlock the existing current-reading feature."
	)

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var mastery := FishingMasteryService.new()
	mastery.configure(mastery_catalog, unlock)
	var wrong_teacher := mastery.learn_technique(
		&"read_current",
		&"not_the_current_reader",
		false
	)
	_record(
		report,
		"Wrong master cannot teach Read Current",
		str(wrong_teacher.get("reason", "")) == "wrong_teacher",
		"Master encounters must not bypass teacher identity."
	)
	var learned := mastery.learn_technique(
		&"read_current",
		definition.teacher_id if definition != null else &"",
		false
	)
	_record(
		report,
		"Current Reader can teach Read Current",
		bool(learned.get("success", false)),
		"The completed lesson must be able to persist the canonical technique."
	)
	_record(
		report,
		"Learned lesson exposes current reading",
		mastery.has_capability(&"read_current"),
		"World presentation should query the mastery capability after the lesson."
	)

	var along := Policy.get_along_current_drift(
		Vector3.ZERO,
		Vector3(0.08, 0.0, 0.0),
		Vector3(0.04, 0.0, 0.0)
	)
	_record(
		report,
		"Movement with current counts as drift",
		along > 0.079,
		"The lesson should recognize passive movement in the water's actual direction."
	)
	var cross := Policy.get_along_current_drift(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 0.08),
		Vector3(0.04, 0.0, 0.0)
	)
	_record(
		report,
		"Cross-current movement does not fake the lesson",
		is_zero_approx(cross),
		"Player/lure movement perpendicular to the flow should not count as reading it."
	)
	var against := Policy.get_along_current_drift(
		Vector3.ZERO,
		Vector3(-0.08, 0.0, 0.0),
		Vector3(0.04, 0.0, 0.0)
	)
	_record(
		report,
		"Movement against current does not count",
		is_zero_approx(against),
		"Repositioning against the flow must not satisfy passive drift."
	)
	var weak := Policy.get_along_current_drift(
		Vector3.ZERO,
		Vector3(0.08, 0.0, 0.0),
		Vector3(0.001, 0.0, 0.0)
	)
	_record(
		report,
		"Sheltered water does not count as a current read",
		is_zero_approx(weak),
		"The player should need actual moving water rather than any lure displacement."
	)

	var paused := Policy.advance_observation(
		0.5,
		0.02,
		Vector3(0.04, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(0.04, 0.0, 0.0),
		true,
		1.0
	)
	_record(
		report,
		"Reeling pauses observation progress",
		is_equal_approx(float(paused.get("observation_seconds", 0.0)), 0.5)
		and is_equal_approx(float(paused.get("along_current_drift_meters", 0.0)), 0.02),
		"The lesson is to observe passive drift, not drag the lure through the water."
	)
	var sheltered := Policy.advance_observation(
		0.5,
		0.02,
		Vector3(0.001, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(0.04, 0.0, 0.0),
		false,
		1.0
	)
	_record(
		report,
		"Weak water pauses observation progress",
		is_equal_approx(float(sheltered.get("observation_seconds", 0.0)), 0.5)
		and not bool(sheltered.get("active_water", true)),
		"Calm pockets should make the player search for a readable flow."
	)
	var valid := Policy.advance_observation(
		0.0,
		0.0,
		Vector3(0.04, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(0.06, 0.0, 0.0),
		false,
		1.0
	)
	_record(
		report,
		"Passive drift advances both lesson dimensions",
		float(valid.get("observation_seconds", 0.0)) > 0.99
		and float(valid.get("along_current_drift_meters", 0.0)) > 0.059,
		"A real drift should build both observation time and directional travel."
	)
	_record(
		report,
		"Time alone cannot complete the lesson",
		not Policy.is_complete(Policy.REQUIRED_OBSERVATION_SECONDS + 1.0, 0.0),
		"Waiting over static water must not teach current reading."
	)
	_record(
		report,
		"Distance alone cannot complete the lesson",
		not Policy.is_complete(0.1, Policy.REQUIRED_ALONG_CURRENT_DRIFT_METERS + 0.5),
		"A single displacement spike must not count as observation."
	)
	_record(
		report,
		"Time plus directional drift completes the lesson",
		Policy.is_complete(
			Policy.REQUIRED_OBSERVATION_SECONDS,
			Policy.REQUIRED_ALONG_CURRENT_DRIFT_METERS
		),
		"The lesson should complete only after sustained real current movement."
	)
	_record(
		report,
		"Progress ratio uses the weaker requirement",
		Policy.get_progress_ratio(
			Policy.REQUIRED_OBSERVATION_SECONDS,
			Policy.REQUIRED_ALONG_CURRENT_DRIFT_METERS * 0.5
		) > 0.49
		and Policy.get_progress_ratio(
			Policy.REQUIRED_OBSERVATION_SECONDS,
			Policy.REQUIRED_ALONG_CURRENT_DRIFT_METERS * 0.5
		) < 0.51,
		"Player feedback should not show completion while one requirement still lags."
	)

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
