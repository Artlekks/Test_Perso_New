extends RefCounted
class_name FishingMasterLandingGuideQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_landing_guide_policy.gd"
)
const LandingTechniquePolicy = preload(
	"res://scripts/fishing_landing_technique_policy.gd"
)
const EncounterScript = preload(
	"res://scripts/encounter.gd"
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

	var definition = mastery_catalog.get_technique(&"landing_technique") if mastery_catalog != null else null
	_record(report, "Landing Technique exists in mastery catalog",
		definition != null,
		"The master lesson requires the canonical landing_technique mastery.")
	if definition != null:
		_record(report, "Landing Guide is the canonical teacher",
			StringName(str(definition.teacher_id)) == &"master_landing_guide",
			"The encounter must use the authored teacher id.")
		_record(report, "Landing Technique requires Surface Control",
			_has_prerequisite(definition, &"surface_control"),
			"The fight-teaching order should remain Surface Control -> Landing Technique.")

	var unlock = UnlockStateScript.new()
	unlock.initialize()
	var mastery = MasteryServiceScript.new()
	mastery.configure(mastery_catalog, unlock)

	var blocked := mastery.can_learn(&"landing_technique", &"master_landing_guide")
	_record(report, "Landing Technique is blocked before Surface Control",
		not bool(blocked.get("can_learn", false)),
		"The Landing Guide must preserve the prerequisite gate.")

	var line_feel = mastery_catalog.get_technique(&"line_feel") if mastery_catalog != null else null
	if line_feel != null:
		mastery.learn_technique(&"line_feel", line_feel.teacher_id, false)
	var surface = mastery_catalog.get_technique(&"surface_control") if mastery_catalog != null else null
	if surface != null:
		mastery.learn_technique(&"surface_control", surface.teacher_id, false)
	var ready := mastery.can_learn(&"landing_technique", &"master_landing_guide")
	_record(report, "Surface Control makes Landing Technique learnable",
		bool(ready.get("can_learn", false)),
		"Completing Surface Angler should unlock the Landing Guide lesson.")
	var learned := mastery.learn_technique(&"landing_technique", &"master_landing_guide", false)
	_record(report, "Landing Guide can teach Landing Technique",
		bool(learned.get("success", false)),
		"A successful lesson must persist the canonical mastery.")
	_record(report, "Learned lesson exposes Landing Technique capability",
		mastery.has_capability(&"landing_technique"),
		"Encounter should see the landing capability immediately.")

	var final_surge_distance := 2.4
	var trigger := Policy.get_trigger_distance(final_surge_distance)
	_record(report, "Lesson begins before Final Surge distance",
		trigger > final_surge_distance,
		"The player needs room to demonstrate head-first control before the final-surge roll.")
	_record(report, "Spent fish inside approach range can open lesson",
		Policy.should_open_lesson(&"SPENT", 3.0, trigger, false, false, false),
		"The lesson should use the real spent-fish final approach.")
	_record(report, "Resisting fish cannot open landing lesson",
		not Policy.should_open_lesson(&"RESISTING", 3.0, trigger, false, false, false),
		"Landing Technique belongs after the fish is spent.")
	_record(report, "Distant spent fish stays ordinary",
		not Policy.should_open_lesson(&"SPENT", 5.0, trigger, false, false, false),
		"The master must not turn the middle of the fight into a landing challenge.")
	_record(report, "Only one lesson attempt is allowed per hooked fish",
		not Policy.should_open_lesson(&"SPENT", 3.0, trigger, true, false, false),
		"Moving in and out of range must not create repeated mastery rerolls.")
	_record(report, "Final Surge checked blocks lesson",
		not Policy.should_open_lesson(&"SPENT", 2.0, trigger, false, true, false),
		"Once the surge roll owns the landing, the teaching window is over.")
	_record(report, "Active Final Surge blocks lesson",
		not Policy.should_open_lesson(&"SPENT", 2.0, trigger, false, false, true),
		"Landing Guide must not overlap the existing surge combat state.")
	_record(report, "Invalid distance cannot open lesson",
		not Policy.should_open_lesson(&"SPENT", -1.0, trigger, false, false, false),
		"Broken distance data must fail closed.")

	var steady := Policy.get_expected_response(0.05)
	var counter_right := Policy.get_expected_response(0.80)
	var counter_left := Policy.get_expected_response(-0.80)
	_record(report, "Straight fish teaches steady head-first lead",
		steady == LandingTechniquePolicy.RESPONSE_STEADY,
		"An aligned fish should not be over-steered at the bank.")
	_record(report, "Right-angled fish teaches counter lead",
		counter_right == LandingTechniquePolicy.RESPONSE_COUNTER,
		"A crossing fish should be turned head-first before landing.")
	_record(report, "Left-angled fish teaches the same counter family",
		counter_left == LandingTechniquePolicy.RESPONSE_COUNTER,
		"Landing control must be symmetrical.")

	_record(report, "Straight response accepts K plus neutral steering",
		Policy.is_response_matching(steady, 0.05, true, 0.0),
		"The authored straight landing response must remain unchanged.")
	_record(report, "Straight response rejects strong side steering",
		not Policy.is_response_matching(steady, 0.05, true, 0.80),
		"Dragging an aligned fish sideways should not teach landing control.")
	_record(report, "Right-angled fish accepts left counter steer",
		Policy.is_response_matching(counter_right, 0.80, true, -0.80),
		"The rod should oppose the fish's lateral approach.")
	_record(report, "Left-angled fish accepts right counter steer",
		Policy.is_response_matching(counter_left, -0.80, true, 0.80),
		"Counter-steering must work in both directions.")
	_record(report, "Counter response rejects same-side steering",
		not Policy.is_response_matching(counter_right, 0.80, true, 0.80),
		"Following the fish sideways is not a head-first lead.")
	_record(report, "Landing lesson requires reel contact",
		not Policy.is_response_matching(counter_right, 0.80, false, -0.80),
		"The technique should not be teachable with a slack line.")

	var easy_window := Policy.get_response_window_seconds(1, false)
	var hard_window := Policy.get_response_window_seconds(5, false)
	var king_window := Policy.get_response_window_seconds(5, true)
	_record(report, "Hard fish tighten the teaching window",
		hard_window < easy_window,
		"The master lesson should preserve the already-authored Landing Technique difficulty.")
	_record(report, "King fish keep the tightest teaching window",
		king_window < hard_window and king_window >= 0.48,
		"King timing must remain demanding but readable.")
	_record(report, "Lesson window delegates exactly to Landing Technique",
		is_equal_approx(easy_window, LandingTechniquePolicy.get_window_seconds(1, false))
		and is_equal_approx(king_window, LandingTechniquePolicy.get_window_seconds(5, true)),
		"The teacher must not invent a second timing model.")

	var partial := Policy.advance_match_time(0.0, true, 0.09)
	_record(report, "Short correct lead remains incomplete",
		not Policy.is_response_complete(partial),
		"A quick key tap should not teach Landing Technique.")
	var interrupted := Policy.advance_match_time(partial, false, 0.02)
	_record(report, "Breaking the landing response resets hold",
		is_zero_approx(interrupted),
		"Partial head-first control should not bank hidden progress.")
	var complete := Policy.advance_match_time(partial, true, 0.09)
	_record(report, "Continuous landing response completes the hold",
		Policy.is_response_complete(complete),
		"The lesson should use the real 0.18-second controlled lead.")
	_record(report, "Lesson hold matches Landing Technique",
		is_equal_approx(Policy.get_hold_required_seconds(), LandingTechniquePolicy.RESPONSE_HOLD_SECONDS),
		"Master cadence must stay aligned with runtime mechanics.")
	_record(report, "Straight response label matches runtime",
		Policy.get_response_label(steady, 0.05) == LandingTechniquePolicy.get_response_label(steady, 0.05),
		"The teacher should speak the same control vocabulary as Landing Technique.")
	_record(report, "Counter response label preserves direction",
		Policy.get_response_label(counter_right, 0.80).contains("LEFT")
		and Policy.get_response_label(counter_left, -0.80).contains("RIGHT"),
		"The prompt must direct the player against the fish's lateral angle.")

	var encounter = EncounterScript.new()
	_record(report, "Encounter exposes landing-training success bridge",
		encounter.has_method("apply_landing_training_success"),
		"A successful master lesson must mark the current fish secured without forcing a duplicate landing prompt.")
	encounter.free()

	mastery.free()
	unlock.free()
	return report


static func _has_prerequisite(
	definition: FishingMasteryTechniqueDefinition,
	prerequisite: StringName
) -> bool:
	if definition == null:
		return false
	for raw_id in definition.prerequisite_ids:
		if StringName(str(raw_id)) == prerequisite:
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
