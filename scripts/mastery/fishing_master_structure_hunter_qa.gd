extends RefCounted
class_name FishingMasterStructureHunterQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_structure_hunter_policy.gd"
)
const ReadStructureResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/read_structure.tres"
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
		mastery_catalog.ensure_technique(ReadStructureResource)
	var definition := (
		mastery_catalog.get_technique(&"read_structure")
		if mastery_catalog != null
		else null
	)
	_record(report, "Read Structure exists for the master lesson", definition != null,
		"The lesson must teach the canonical mastery definition.")
	_record(report, "Structure Hunter is the canonical teacher",
		definition != null and definition.teacher_id == &"master_structure_hunter",
		"The encounter must keep the authored teacher identity.")
	_record(report, "Read Structure exposes the structure capability",
		definition != null and definition.has_capability(&"read_structure"),
		"Completing the lesson must unlock the existing structure-reading feature.")

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var mastery := FishingMasteryService.new()
	mastery.configure(mastery_catalog, unlock)
	var wrong_teacher := mastery.learn_technique(&"read_structure", &"not_the_structure_hunter", false)
	_record(report, "Wrong master cannot teach Read Structure",
		str(wrong_teacher.get("reason", "")) == "wrong_teacher",
		"Master encounters must not bypass teacher identity.")
	var learned := mastery.learn_technique(
		&"read_structure",
		definition.teacher_id if definition != null else &"",
		false
	)
	_record(report, "Structure Hunter can teach Read Structure",
		bool(learned.get("success", false)),
		"The completed lesson must persist the canonical technique.")
	_record(report, "Learned lesson exposes structure reading",
		mastery.has_capability(&"read_structure"),
		"Fishing systems should query the mastery capability after learning.")

	_record(report, "Horizontal distance ignores vertical movement",
		is_equal_approx(
			Policy.horizontal_distance(Vector3(0, 0, 0), Vector3(0, 5, 1)),
			1.0
		),
		"The lesson must trace bottom contour across the water, not count lure sinking as travel.")
	_record(report, "Depth span measures the observed bottom range",
		is_equal_approx(Policy.get_depth_span(0.45, 0.72), 0.27),
		"Bottom contour change should be measured directly from local total depth.")
	_record(report, "Unknown depth range reports zero",
		is_zero_approx(Policy.get_depth_span(-1.0, -1.0)),
		"An uninitialized cast must not fake a depth break.")

	var first := Policy.advance_trace(
		0.0, 0.0, -1.0, -1.0, false,
		false, Vector3.ZERO, Vector3(0, 0, 0),
		0.50, false, 0.4
	)
	_record(report, "First valid sample begins observation",
		bool(first.get("sample_accepted", false))
		and float(first.get("observation_seconds", 0.0)) > 0.0,
		"A valid water-column sample should start the trace.")
	_record(report, "First sample does not invent horizontal travel",
		is_zero_approx(float(first.get("horizontal_travel", -1.0))),
		"The start point must not count as movement.")

	var second := Policy.advance_trace(
		float(first.get("observation_seconds", 0.0)),
		float(first.get("horizontal_travel", 0.0)),
		float(first.get("min_total_depth", -1.0)),
		float(first.get("max_total_depth", -1.0)),
		bool(first.get("structure_contact", false)),
		true, Vector3(0, 0, 0), Vector3(0.35, 0, 0),
		0.56, false, 0.4
	)
	_record(report, "Tracing accumulates horizontal travel",
		is_equal_approx(float(second.get("horizontal_travel", 0.0)), 0.35),
		"The lesson should reward actually moving the lure across the contour.")
	_record(report, "Tracing records minimum and maximum local depth",
		is_equal_approx(float(second.get("min_total_depth", 0.0)), 0.50)
		and is_equal_approx(float(second.get("max_total_depth", 0.0)), 0.56),
		"The contour read needs the full observed depth range.")

	var third := Policy.advance_trace(
		float(second.get("observation_seconds", 0.0)),
		float(second.get("horizontal_travel", 0.0)),
		float(second.get("min_total_depth", -1.0)),
		float(second.get("max_total_depth", -1.0)),
		bool(second.get("structure_contact", false)),
		true, Vector3(0.35, 0, 0), Vector3(0.72, 0, 0),
		0.68, false, 0.5
	)
	_record(report, "A meaningful contour change reaches the depth-break threshold",
		float(third.get("depth_span", 0.0)) >= Policy.REQUIRED_DEPTH_BREAK_METERS,
		"The lesson should recognize a shelf/drop-off from real bottom depth change.")
	_record(report, "Contour path can complete the structure lesson",
		bool(third.get("complete", false)),
		"Enough time, travel and a real depth break should teach Read Structure.")

	var shallow := Policy.advance_trace(
		0.5, 0.3, 0.4, 0.5, false,
		true, Vector3.ZERO, Vector3(0.2, 0, 0),
		0.15, false, 0.5
	)
	_record(report, "Too-shallow water pauses observation",
		is_equal_approx(float(shallow.get("observation_seconds", 0.0)), 0.5)
		and not bool(shallow.get("valid_water", true)),
		"Tiny shoreline water should not satisfy a structure-reading lesson.")

	var teleport := Policy.advance_trace(
		0.5, 0.3, 0.4, 0.5, false,
		true, Vector3.ZERO, Vector3(4.0, 0, 0),
		0.8, false, 0.5
	)
	_record(report, "Large position jumps are rejected as trace samples",
		not bool(teleport.get("sample_accepted", true))
		and is_equal_approx(float(teleport.get("horizontal_travel", 0.0)), 0.3),
		"A recast/teleport must not instantly complete the travel requirement.")

	_record(report, "Time alone cannot complete the lesson",
		not Policy.is_complete(5.0, 0.1, 0.5, false),
		"Standing still over one patch of water must not teach structure.")
	_record(report, "Travel without a structural read cannot complete",
		not Policy.is_complete(5.0, 2.0, 0.02, false),
		"Open water movement alone must not count as reading structure.")
	_record(report, "Depth break without enough travel cannot complete",
		not Policy.is_complete(5.0, 0.2, 0.30, false),
		"One local depth fluctuation should not replace tracing the contour.")
	_record(report, "Real snag cover can satisfy the structure signal",
		Policy.is_complete(
			Policy.REQUIRED_OBSERVATION_SECONDS,
			Policy.REQUIRED_HORIZONTAL_TRAVEL_METERS,
			0.02,
			true
		),
		"Existing fishing_snag cover should count as real structure even without a shelf.")
	_record(report, "Direct cover contact persists through later samples",
		bool(Policy.advance_trace(
			1.0, 0.4, 0.5, 0.55, true,
			true, Vector3.ZERO, Vector3(0.2, 0, 0),
			0.54, false, 0.3
		).get("structure_contact", false)),
		"Once real cover is observed in the cast, the lesson should remember it.")
	_record(report, "Progress is capped by missing structure information",
		Policy.get_progress_ratio(
			Policy.REQUIRED_OBSERVATION_SECONDS,
			Policy.REQUIRED_HORIZONTAL_TRAVEL_METERS,
			0.0,
			false
		) == 0.0,
		"Feedback should not imply mastery before the player actually reads an edge or cover.")
	_record(report, "Progress reaches one for a full contour read",
		is_equal_approx(Policy.get_progress_ratio(
			Policy.REQUIRED_OBSERVATION_SECONDS,
			Policy.REQUIRED_HORIZONTAL_TRAVEL_METERS,
			Policy.REQUIRED_DEPTH_BREAK_METERS,
			false
		), 1.0),
		"Lesson progress should align with completion.")
	_record(report, "Progress reaches one for real cover after enough tracing",
		is_equal_approx(Policy.get_progress_ratio(
			Policy.REQUIRED_OBSERVATION_SECONDS,
			Policy.REQUIRED_HORIZONTAL_TRAVEL_METERS,
			0.0,
			true
		), 1.0),
		"A genuine snag/cover read is an equally valid structure lesson path.")

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
