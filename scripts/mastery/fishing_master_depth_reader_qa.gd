extends RefCounted
class_name FishingMasterDepthReaderQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_depth_reader_policy.gd"
)
const ReadDepthResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/read_depth.tres"
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
		mastery_catalog.ensure_technique(ReadDepthResource)
	var definition := (
		mastery_catalog.get_technique(&"read_depth")
		if mastery_catalog != null
		else null
	)
	_record(
		report,
		"Read Depth exists for the master lesson",
		definition != null,
		"The in-world lesson must teach the canonical mastery definition."
	)
	_record(
		report,
		"Depth Reader is the canonical teacher",
		definition != null and definition.teacher_id == &"master_depth_reader",
		"The lesson must keep the authored teacher identity."
	)
	_record(
		report,
		"Read Depth exposes the read-depth capability",
		definition != null and definition.has_capability(&"read_depth"),
		"Completing the lesson must unlock the existing depth-reading feature."
	)

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var mastery := FishingMasteryService.new()
	mastery.configure(mastery_catalog, unlock)
	var wrong_teacher := mastery.learn_technique(
		&"read_depth",
		&"not_the_depth_reader",
		false
	)
	_record(
		report,
		"Wrong master cannot teach Read Depth",
		str(wrong_teacher.get("reason", "")) == "wrong_teacher",
		"Master encounters must not bypass teacher identity."
	)
	var learned := mastery.learn_technique(
		&"read_depth",
		definition.teacher_id if definition != null else &"",
		false
	)
	_record(
		report,
		"Depth Reader can teach Read Depth",
		bool(learned.get("success", false)),
		"The completed lesson must persist the canonical technique."
	)
	_record(
		report,
		"Learned lesson exposes depth reading",
		mastery.has_capability(&"read_depth"),
		"Fishing presentation should query the mastery capability after learning."
	)

	_record(
		report,
		"Too-shallow water has no valid depth ratio",
		is_zero_approx(Policy.get_depth_ratio(0.1, 0.2)),
		"Tiny puddles must not satisfy a water-column lesson."
	)
	_record(
		report,
		"Surface third is classified as shallow",
		Policy.get_depth_band(0.08, 0.60) == &"shallow",
		"The first third of the water column should read as shallow."
	)
	_record(
		report,
		"Middle third is classified as mid-water",
		Policy.get_depth_band(0.30, 0.60) == &"mid",
		"The lesson must distinguish the middle of the water column."
	)
	_record(
		report,
		"Lower third is classified as deep",
		Policy.get_depth_band(0.50, 0.60) == &"deep",
		"The bottom third should read as deep water."
	)

	var paused := Policy.advance_observation(
		0.4,
		true,
		false,
		false,
		0.30,
		0.60,
		true,
		1.0
	)
	_record(
		report,
		"Reeling pauses depth observation",
		is_equal_approx(float(paused.get("observation_seconds", 0.0)), 0.4)
		and not bool(paused.get("seen_mid", true)),
		"The lesson must observe natural sinking rather than player-driven depth changes."
	)
	var invalid := Policy.advance_observation(
		0.4,
		true,
		false,
		false,
		0.15,
		0.20,
		false,
		1.0
	)
	_record(
		report,
		"Insufficient total depth pauses observation",
		is_equal_approx(float(invalid.get("observation_seconds", 0.0)), 0.4)
		and not bool(invalid.get("valid_water", true)),
		"The player should need a meaningful water column."
	)

	var shallow := Policy.advance_observation(
		0.0,
		false,
		false,
		false,
		0.08,
		0.60,
		false,
		0.4
	)
	_record(
		report,
		"Passive shallow observation records the surface band",
		bool(shallow.get("seen_shallow", false))
		and not bool(shallow.get("seen_mid", false)),
		"A natural sink should begin by teaching the upper water column."
	)
	var mid := Policy.advance_observation(
		float(shallow.get("observation_seconds", 0.0)),
		bool(shallow.get("seen_shallow", false)),
		bool(shallow.get("seen_mid", false)),
		bool(shallow.get("seen_deep", false)),
		0.30,
		0.60,
		false,
		0.4
	)
	_record(
		report,
		"Passive mid-water observation records the middle band",
		bool(mid.get("seen_shallow", false))
		and bool(mid.get("seen_mid", false))
		and not bool(mid.get("seen_deep", false)),
		"The middle band must be observed independently."
	)
	var deep := Policy.advance_observation(
		float(mid.get("observation_seconds", 0.0)),
		bool(mid.get("seen_shallow", false)),
		bool(mid.get("seen_mid", false)),
		bool(mid.get("seen_deep", false)),
		0.50,
		0.60,
		false,
		0.4
	)
	_record(
		report,
		"Passive deep observation records the lower band",
		bool(deep.get("seen_shallow", false))
		and bool(deep.get("seen_mid", false))
		and bool(deep.get("seen_deep", false)),
		"The full column should be visible only after reaching deep water."
	)
	_record(
		report,
		"Time alone cannot complete the lesson",
		not Policy.is_complete(
			Policy.REQUIRED_OBSERVATION_SECONDS + 1.0,
			true,
			false,
			false
		),
		"Waiting in one depth band must not teach the entire water column."
	)
	_record(
		report,
		"All depth bands without observation time cannot complete",
		not Policy.is_complete(0.1, true, true, true),
		"A rapid depth jump must not replace sustained observation."
	)
	_record(
		report,
		"Full passive water-column read completes the lesson",
		Policy.is_complete(
			float(deep.get("observation_seconds", 0.0)),
			bool(deep.get("seen_shallow", false)),
			bool(deep.get("seen_mid", false)),
			bool(deep.get("seen_deep", false))
		),
		"Shallow, middle and deep observation plus time should finish the lesson."
	)
	_record(
		report,
		"Progress ratio is capped by missing depth bands",
		Policy.get_progress_ratio(
			Policy.REQUIRED_OBSERVATION_SECONDS,
			true,
			true,
			false
		) > 0.66
		and Policy.get_progress_ratio(
			Policy.REQUIRED_OBSERVATION_SECONDS,
			true,
			true,
			false
		) < 0.67,
		"Feedback must not show completion until all three bands are observed."
	)
	_record(
		report,
		"Progress reaches one only with the complete lesson",
		is_equal_approx(
			Policy.get_progress_ratio(
				Policy.REQUIRED_OBSERVATION_SECONDS,
				true,
				true,
				true
			),
			1.0
		),
		"The lesson progress readout should align with completion."
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
