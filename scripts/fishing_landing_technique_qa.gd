extends RefCounted
class_name FishingLandingTechniqueQA

const LandingTechniquePolicy = preload(
	"res://scripts/fishing_landing_technique_policy.gd"
)
const LandingPolicy = preload(
	"res://scripts/fishing_landing_policy.gd"
)
const LandingTechniqueResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/landing_technique.tres"
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
		mastery_catalog.ensure_technique(LandingTechniqueResource)

	var trigger := LandingTechniquePolicy.get_trigger_distance(2.4)
	_record(
		report,
		"Landing approach begins before Final Surge",
		trigger > 2.4,
		"The head-first setup must happen before the existing final-surge distance check."
	)
	_record(
		report,
		"Known mastery can start landing approach",
		LandingTechniquePolicy.should_start(3.0, trigger, false, false, false, true),
		"A trained angler should receive the final-approach read while the fish is still hooked and spent."
	)
	_record(
		report,
		"Unknown mastery does not create a new challenge",
		not LandingTechniquePolicy.should_start(3.0, trigger, false, false, false, false),
		"Learning Landing Technique must add an advantage, not make untrained fishing harder."
	)
	_record(
		report,
		"Landing approach is one-shot per fish",
		not LandingTechniquePolicy.should_start(3.0, trigger, true, false, false, true),
		"Moving in and out of shore range must not allow repeated landing-technique rerolls."
	)
	_record(
		report,
		"Final Surge ownership blocks landing setup",
		not LandingTechniquePolicy.should_start(2.0, trigger, false, true, false, true)
		and not LandingTechniquePolicy.should_start(2.0, trigger, false, false, true, true),
		"Once Final Surge has been checked or started, Landing Technique must not overlap it."
	)
	_record(
		report,
		"Distant spent fish stays ordinary",
		not LandingTechniquePolicy.should_start(5.0, trigger, false, false, false, true),
		"The technique belongs to the final approach, not the middle of the fight."
	)

	_record(
		report,
		"Straight fish maps to steady landing",
		LandingTechniquePolicy.get_expected_response(0.05) == LandingTechniquePolicy.RESPONSE_STEADY,
		"An already aligned fish should be led straight instead of forcing unnecessary steering."
	)
	_record(
		report,
		"Angled fish maps to counter landing",
		LandingTechniquePolicy.get_expected_response(0.75) == LandingTechniquePolicy.RESPONSE_COUNTER,
		"A fish crossing the approach should be turned head-first before it reaches shore."
	)
	_record(
		report,
		"Straight landing requires K and neutral steering",
		LandingTechniquePolicy.is_response_matching(
			LandingTechniquePolicy.RESPONSE_STEADY,
			0.05,
			true,
			0.0
		),
		"Landing straight should mean controlled forward pressure without sawing the rod sideways."
	)
	_record(
		report,
		"Straight landing rejects side steering",
		not LandingTechniquePolicy.is_response_matching(
			LandingTechniquePolicy.RESPONSE_STEADY,
			0.05,
			true,
			0.80
		),
		"A player should not get credit for dragging an aligned fish sideways at the bank."
	)
	_record(
		report,
		"Right-angled fish needs left counter steer",
		LandingTechniquePolicy.is_response_matching(
			LandingTechniquePolicy.RESPONSE_COUNTER,
			0.80,
			true,
			-0.80
		),
		"The final approach should reward turning the fish against its lateral angle."
	)
	_record(
		report,
		"Left-angled fish needs right counter steer",
		LandingTechniquePolicy.is_response_matching(
			LandingTechniquePolicy.RESPONSE_COUNTER,
			-0.80,
			true,
			0.80
		),
		"Landing control must be symmetrical in both directions."
	)
	_record(
		report,
		"Landing counter rejects same-side steering",
		not LandingTechniquePolicy.is_response_matching(
			LandingTechniquePolicy.RESPONSE_COUNTER,
			0.80,
			true,
			0.80
		),
		"Following the fish sideways should not count as leading its head into the landing line."
	)
	_record(
		report,
		"Landing response requires reel contact",
		not LandingTechniquePolicy.is_response_matching(
			LandingTechniquePolicy.RESPONSE_COUNTER,
			0.80,
			false,
			-0.80
		),
		"Head-first landing needs maintained line contact rather than free slack."
	)

	var hold_time := LandingTechniquePolicy.advance_match_time(0.0, true, 0.10)
	hold_time = LandingTechniquePolicy.advance_match_time(hold_time, true, 0.10)
	_record(
		report,
		"Landing response completes after stable hold",
		LandingTechniquePolicy.is_response_complete(hold_time),
		"A landing should reward a short controlled lead rather than a one-frame key tap."
	)
	_record(
		report,
		"Broken landing response resets hold",
		is_zero_approx(LandingTechniquePolicy.advance_match_time(0.12, false, 0.02)),
		"Partial steering should not bank hidden progress across mistakes."
	)
	var easy_window := LandingTechniquePolicy.get_window_seconds(1, false)
	var hard_window := LandingTechniquePolicy.get_window_seconds(5, false)
	var king_window := LandingTechniquePolicy.get_window_seconds(5, true)
	_record(
		report,
		"Hard fish tighten landing window",
		hard_window < easy_window,
		"Experienced fish should be harder to line up at the bank without changing the control vocabulary."
	)
	_record(
		report,
		"King fish keep the tightest landing window",
		king_window < hard_window and king_window >= 0.48,
		"King specimens should remain dangerous without making the response unreadably short."
	)

	var base_easy_chance := LandingPolicy.get_final_surge_chance(1, 1.0, false)
	var base_hard_chance := LandingPolicy.get_final_surge_chance(5, 1.0, false)
	var base_king_chance := LandingPolicy.get_final_surge_chance(5, 1.25, true)
	var secured_easy_chance := LandingTechniquePolicy.adjust_final_surge_chance(
		base_easy_chance,
		1,
		false
	)
	var secured_hard_chance := LandingTechniquePolicy.adjust_final_surge_chance(
		base_hard_chance,
		5,
		false
	)
	var secured_king_chance := LandingTechniquePolicy.adjust_final_surge_chance(
		base_king_chance,
		5,
		true
	)
	_record(
		report,
		"Clean landing reduces Final Surge chance",
		secured_easy_chance < base_easy_chance
		and secured_hard_chance < base_hard_chance
		and secured_king_chance < base_king_chance,
		"Landing Technique should improve the odds without replacing the existing Final Surge mechanic."
	)
	_record(
		report,
		"King fish retain meaningful Final Surge risk",
		secured_king_chance > secured_hard_chance
		and secured_king_chance > 0.20,
		"A perfect landing setup should not trivialize trophy fish."
	)
	var base_stamina := LandingPolicy.get_final_surge_stamina_ratio(5, false)
	var base_king_stamina := LandingPolicy.get_final_surge_stamina_ratio(5, true)
	_record(
		report,
		"Clean landing softens Final Surge stamina",
		LandingTechniquePolicy.adjust_final_surge_stamina_ratio(base_stamina, false) < base_stamina,
		"If the fish still surges, good landing control should shorten the burst rather than cancel it."
	)
	_record(
		report,
		"King landing mitigation stays conservative",
		LandingTechniquePolicy.adjust_final_surge_stamina_ratio(base_king_stamina, true) < base_king_stamina
		and LandingTechniquePolicy.adjust_final_surge_stamina_ratio(base_king_stamina, true) > LandingTechniquePolicy.adjust_final_surge_stamina_ratio(base_stamina, false),
		"King fish should benefit less from the same landing advantage."
	)
	var base_intensity := LandingPolicy.get_final_surge_intensity(5, false)
	_record(
		report,
		"Clean landing softens Final Surge intensity",
		LandingTechniquePolicy.adjust_final_surge_intensity(base_intensity, false) < base_intensity,
		"The last kick can remain dramatic while becoming more controlled after a good head-first approach."
	)

	var technique := (
		mastery_catalog.get_technique(&"landing_technique")
		if mastery_catalog != null
		else null
	)
	_record(
		report,
		"Landing Technique registers incrementally",
		technique != null and technique.has_capability(&"landing_technique"),
		"The mastery must append safely without replacing the user's existing technique catalog."
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
