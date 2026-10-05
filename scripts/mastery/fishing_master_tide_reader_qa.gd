extends RefCounted
class_name FishingMasterTideReaderQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_tide_reader_policy.gd"
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
		mastery_catalog.get_technique(&"tide_sense")
		if mastery_catalog != null
		else null
	)
	_record(
		report,
		"Tide Sense exists in mastery catalog",
		definition != null,
		"The master encounter requires the canonical tide_sense technique."
	)
	if definition != null:
		_record(
			report,
			"Tide Reader is the canonical teacher",
			StringName(str(definition.teacher_id)) == &"master_tide_reader",
			"The encounter must use the authored Tide Reader teacher id."
		)
		_record(
			report,
			"Tide Sense remains an observation capability",
			definition.has_capability(&"tide_sense"),
			"The lesson must unlock interpretation rather than a hidden tide buff."
		)
		_record(
			report,
			"Tide Sense keeps exactly two authored prerequisites",
			definition.prerequisite_ids.size() == 2,
			"The master lesson should preserve the current + weather synthesis gate."
		)
		_record(
			report,
			"Read Current is a Tide Sense prerequisite",
			definition.prerequisite_ids.has("read_current"),
			"Tide Reader must build on real current reading."
		)
		_record(
			report,
			"Weather Sense is a Tide Sense prerequisite",
			definition.prerequisite_ids.has("weather_sense"),
			"Tide Reader must build on water-column/environment reading."
		)

	# QA must start from a blank in-memory mastery state. Do NOT call
	# FishingUnlockState.initialize() here: initialize() loads the player's
	# persistent user://fishing_unlocks.json and makes this deterministic test
	# depend on whatever techniques the current save already knows.
	var unlock = UnlockStateScript.new()
	var mastery = MasteryServiceScript.new()
	mastery.configure(mastery_catalog, unlock)

	var wrong_teacher := mastery.learn_technique(
		&"tide_sense",
		&"wrong_master",
		false
	)
	_record(
		report,
		"Wrong master cannot teach Tide Sense",
		str(wrong_teacher.get("reason", "")) == "wrong_teacher",
		"Tide Sense must remain tied to Tide Reader."
	)

	var initially_locked := mastery.can_learn(
		&"tide_sense",
		&"master_tide_reader"
	)
	_record(
		report,
		"Tide Sense starts behind its prerequisites",
		str(initially_locked.get("reason", "")) == "missing_prerequisite",
		"The lesson should not bypass Read Current and Weather Sense."
	)

	var current_def = (
		mastery_catalog.get_technique(&"read_current")
		if mastery_catalog != null
		else null
	)
	var current_learned := {}
	if current_def != null:
		current_learned = mastery.learn_technique(
			&"read_current",
			current_def.teacher_id,
			false
		)
	_record(
		report,
		"Read Current can be prepared for Tide Reader QA",
		bool(current_learned.get("success", false)),
		"The prerequisite chain must remain learnable through canonical data."
	)

	var still_locked := mastery.can_learn(
		&"tide_sense",
		&"master_tide_reader"
	)
	_record(
		report,
		"Read Current alone is not enough",
		str(still_locked.get("reason", "")) == "missing_prerequisite"
		and str(still_locked.get("missing_technique_id", "")) == "weather_sense",
		"Tide Sense should still require Weather Sense."
	)

	var weather_def = (
		mastery_catalog.get_technique(&"weather_sense")
		if mastery_catalog != null
		else null
	)
	var weather_learned := {}
	if weather_def != null:
		weather_learned = mastery.learn_technique(
			&"weather_sense",
			weather_def.teacher_id,
			false
		)
	_record(
		report,
		"Weather Sense can be prepared for Tide Reader QA",
		bool(weather_learned.get("success", false)),
		"The second prerequisite must remain reachable through canonical data."
	)

	var ready := mastery.can_learn(
		&"tide_sense",
		&"master_tide_reader"
	)
	_record(
		report,
		"Both prerequisites unlock the Tide Reader lesson",
		bool(ready.get("can_learn", false)),
		"The authored chain should open only after current and weather knowledge."
	)

	var tide_learned := mastery.learn_technique(
		&"tide_sense",
		&"master_tide_reader",
		false
	)
	_record(
		report,
		"Tide Reader can teach Tide Sense",
		bool(tide_learned.get("success", false)),
		"A successful practical lesson must persist the canonical technique."
	)
	_record(
		report,
		"Learned lesson exposes Tide Sense capability",
		mastery.has_capability(&"tide_sense"),
		"Environment presentation should see the capability immediately."
	)

	_record(
		report,
		"Incoming tide targets shallow water",
		Policy.get_target_band(&"incoming") == Policy.TARGET_SHALLOW,
		"Flood tide should combine current reading with the shallow-water opportunity authored by Tide Sense."
	)
	_record(
		report,
		"Outgoing tide targets deep water",
		Policy.get_target_band(&"outgoing") == Policy.TARGET_DEEP,
		"Ebb tide should combine current reading with the deep-water opportunity authored by Tide Sense."
	)
	_record(
		report,
		"Slack tide has no teaching depth target",
		Policy.get_target_band(&"slack") == Policy.TARGET_NONE,
		"The master must not invent a directional read during slack water."
	)
	_record(
		report,
		"Strong incoming tide is teachable",
		Policy.is_moving_tide(&"incoming", 0.80),
		"The flood-tide lesson needs real moving water."
	)
	_record(
		report,
		"Strong outgoing tide is teachable",
		Policy.is_moving_tide(&"outgoing", 0.80),
		"The ebb-tide lesson needs real moving water."
	)
	_record(
		report,
		"Slack water cannot teach Tide Sense",
		not Policy.is_moving_tide(&"slack", 0.90),
		"High flow data must not override the fact that slack has no direction."
	)
	_record(
		report,
		"Weak tidal movement waits instead of faking a lesson",
		not Policy.is_moving_tide(&"incoming", 0.05),
		"Near-slack water should not count as a clear tidal read."
	)

	_record(
		report,
		"Incoming target accepts a shallow lure",
		Policy.is_target_depth(&"incoming", 0.25, 1.00),
		"Flood tide should be demonstrated in the shallower part of the column."
	)
	_record(
		report,
		"Incoming target rejects a deep lure",
		not Policy.is_target_depth(&"incoming", 0.75, 1.00),
		"A deep lure should not satisfy the flood-tide lesson."
	)
	_record(
		report,
		"Outgoing target accepts a deep lure",
		Policy.is_target_depth(&"outgoing", 0.75, 1.00),
		"Ebb tide should be demonstrated in deeper water."
	)
	_record(
		report,
		"Outgoing target rejects a shallow lure",
		not Policy.is_target_depth(&"outgoing", 0.25, 1.00),
		"A shallow lure should not satisfy the ebb-tide lesson."
	)
	_record(
		report,
		"Too-shallow water cannot satisfy Tide Reader",
		not Policy.is_target_depth(&"incoming", 0.10, 0.20),
		"The lesson needs a real water column."
	)

	var along := Policy.get_along_current_drift(
		Vector3.ZERO,
		Vector3(0.05, 0.0, 0.0),
		Vector3(0.20, 0.0, 0.0)
	)
	_record(
		report,
		"Drift with the real current is measurable",
		along > 0.049,
		"Tide Reader must reuse passive current motion rather than a fake timer."
	)
	var against := Policy.get_along_current_drift(
		Vector3.ZERO,
		Vector3(-0.05, 0.0, 0.0),
		Vector3(0.20, 0.0, 0.0)
	)
	_record(
		report,
		"Motion against current does not count as tidal drift",
		is_zero_approx(against),
		"The lesson should only credit displacement carried by the active flow."
	)

	var partial := Policy.advance_observation(
		0.0,
		0.0,
		&"incoming",
		0.80,
		Vector3(0.20, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(0.05, 0.0, 0.0),
		0.25,
		1.00,
		false,
		0.70
	)
	_record(
		report,
		"Valid tide read accumulates observation time",
		float(partial.get("observation_seconds", 0.0)) > 0.69,
		"The player must hold the correct read continuously."
	)
	_record(
		report,
		"Valid tide read accumulates passive drift",
		float(partial.get("along_current_drift_meters", 0.0)) > 0.049,
		"The lure must actually move with the existing current."
	)
	_record(
		report,
		"Partial tidal read remains incomplete",
		not bool(partial.get("complete", false)),
		"A brief correct moment must not instantly teach Tide Sense."
	)

	var wrong_depth := Policy.advance_observation(
		float(partial.get("observation_seconds", 0.0)),
		float(partial.get("along_current_drift_meters", 0.0)),
		&"incoming",
		0.80,
		Vector3(0.20, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(0.05, 0.0, 0.0),
		0.80,
		1.00,
		false,
		0.20
	)
	_record(
		report,
		"Wrong depth resets continuous tidal read",
		is_zero_approx(float(wrong_depth.get("observation_seconds", -1.0)))
		and is_zero_approx(float(wrong_depth.get("along_current_drift_meters", -1.0))),
		"The player cannot bank progress while ignoring the tide's depth shift."
	)

	var reeling := Policy.advance_observation(
		0.80,
		0.05,
		&"incoming",
		0.80,
		Vector3(0.20, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(0.05, 0.0, 0.0),
		0.25,
		1.00,
		true,
		0.20
	)
	_record(
		report,
		"Reeling resets passive tide observation",
		is_zero_approx(float(reeling.get("observation_seconds", -1.0))),
		"Read Current remains part of the synthesis: the water must move the lure."
	)

	var slack := Policy.advance_observation(
		0.80,
		0.05,
		&"slack",
		0.90,
		Vector3(0.20, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(0.05, 0.0, 0.0),
		0.25,
		1.00,
		false,
		0.20
	)
	_record(
		report,
		"Slack water resets the lesson",
		is_zero_approx(float(slack.get("observation_seconds", -1.0))),
		"Tide Reader should wait for directional water rather than preserve stale progress."
	)

	var complete := Policy.advance_observation(
		0.80,
		0.03,
		&"incoming",
		0.80,
		Vector3(0.20, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(0.02, 0.0, 0.0),
		0.25,
		1.00,
		false,
		0.60
	)
	_record(
		report,
		"Continuous correct read reaches deterministic completion",
		bool(complete.get("complete", false)),
		"The lesson needs one stable completion threshold."
	)
	_record(
		report,
		"Progress ratio clamps at zero",
		is_zero_approx(Policy.get_progress_ratio(-2.0, -1.0)),
		"Lesson feedback must remain stable for invalid negative state."
	)
	_record(
		report,
		"Progress ratio clamps at one",
		is_equal_approx(Policy.get_progress_ratio(99.0, 99.0), 1.0),
		"Completed observation should never exceed 100 percent."
	)
	_record(
		report,
		"Incoming label is readable",
		Policy.get_movement_label(&"incoming") == "INCOMING TIDE",
		"The master needs clear teaching language."
	)
	_record(
		report,
		"Outgoing target label is readable",
		Policy.get_target_label(&"outgoing") == "DEEP WATER",
		"The lesson should explain the ebb-tide placement without raw multipliers."
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
	var failures: PackedStringArray = report.get(
		"failures",
		PackedStringArray()
	)
	failures.append("%s — %s" % [name, failure_message])
	report["failures"] = failures
