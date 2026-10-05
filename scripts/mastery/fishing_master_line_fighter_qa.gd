extends RefCounted
class_name FishingMasterLineFighterQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_line_fighter_policy.gd"
)
const LineFeelResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/line_feel.tres"
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
		mastery_catalog.ensure_technique(LineFeelResource)
	var definition := (
		mastery_catalog.get_technique(&"line_feel")
		if mastery_catalog != null
		else null
	)
	_record(report, "Line Feel exists for the master lesson", definition != null,
		"The encounter must teach the canonical mastery definition.")
	_record(report, "Line Fighter is the canonical teacher",
		definition != null and definition.teacher_id == &"master_line_fighter",
		"The encounter must preserve the authored teacher identity.")
	_record(report, "Line Feel exposes its capability",
		definition != null and definition.has_capability(&"line_feel"),
		"Completing the lesson must expose the existing Line Feel capability.")

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var mastery := FishingMasteryService.new()
	mastery.configure(mastery_catalog, unlock)
	var wrong_teacher := mastery.learn_technique(&"line_feel", &"not_the_line_fighter", false)
	_record(report, "Wrong master cannot teach Line Feel",
		str(wrong_teacher.get("reason", "")) == "wrong_teacher",
		"Master encounters must respect the canonical teacher id.")
	var learned := mastery.learn_technique(
		&"line_feel",
		definition.teacher_id if definition != null else &"",
		false
	)
	_record(report, "Line Fighter can teach Line Feel",
		bool(learned.get("success", false)),
		"A completed lesson must persist the canonical technique.")
	_record(report, "Learned lesson exposes Line Feel",
		mastery.has_capability(&"line_feel"),
		"Fight systems should be able to query the capability after learning.")

	var state := _state()
	state = _step(state, Policy.BAND_LIGHT, false, 0.0, 0.1)
	_record(report, "Light pressure arms the pull read",
		bool(state.get("pull_armed", false)) and not bool(state.get("pull_done", false)),
		"The player must first feel a light line before recovering it.")
	state = _step(state, Policy.BAND_WORKING, true, 0.0, 0.1)
	_record(report, "Reeling light pressure into working completes pull",
		bool(state.get("pull_done", false)),
		"A clean take-up should demonstrate the pull response.")

	var no_reel := _state()
	no_reel = _step(no_reel, Policy.BAND_LIGHT, false, 0.0, 0.1)
	no_reel = _step(no_reel, Policy.BAND_WORKING, false, 0.0, 0.1)
	_record(report, "Pressure transition without reeling does not count as pull",
		not bool(no_reel.get("pull_done", false)),
		"The lesson must observe an intentional take-up, not passive fish movement.")

	var overshoot := _state()
	overshoot = _step(overshoot, Policy.BAND_LIGHT, true, 0.0, 0.1)
	overshoot = _step(overshoot, Policy.BAND_HEAVY, true, 0.0, 0.1)
	_record(report, "Overshooting light directly to heavy does not count as clean pull",
		not bool(overshoot.get("pull_done", false)),
		"Line Feel should reward controlled recovery into working pressure.")

	var hold := _state()
	hold = _step(hold, Policy.BAND_WORKING, true, 0.0, 0.35)
	_record(report, "Short working hold remains incomplete",
		not bool(hold.get("hold_done", false))
		and is_equal_approx(float(hold.get("hold_seconds", 0.0)), 0.35),
		"The hold response should require sustained control.")
	hold = _step(hold, Policy.BAND_WORKING, true, 0.0, 0.35)
	_record(report, "Sustained working pressure completes hold",
		bool(hold.get("hold_done", false)),
		"The player should prove they can stabilize the working band.")

	var biased_hold := _state()
	biased_hold = _step(biased_hold, Policy.BAND_WORKING, true, 0.8, 0.5)
	_record(report, "Large W/S correction does not build hold time",
		is_zero_approx(float(biased_hold.get("hold_seconds", -1.0))),
		"Hold means steady pressure, not constant rod correction.")
	biased_hold = _step(biased_hold, Policy.BAND_WORKING, true, 0.0, 0.5)
	biased_hold = _step(biased_hold, Policy.BAND_LIGHT, true, 0.0, 0.1)
	_record(report, "Leaving working pressure resets an unfinished hold",
		is_zero_approx(float(biased_hold.get("hold_seconds", -1.0))),
		"The hold demonstration must be continuous.")

	var yield_state := _state()
	yield_state = _step(yield_state, Policy.BAND_HEAVY, true, 0.0, 0.1)
	_record(report, "Heavy pressure arms the yield read",
		bool(yield_state.get("yield_armed", false)),
		"The player must first feel genuine heavy pressure.")
	yield_state = _step(yield_state, Policy.BAND_WORKING, false, 0.0, 0.1)
	_record(report, "Releasing back into working pressure completes yield",
		bool(yield_state.get("yield_done", false)),
		"A controlled reel release should satisfy the yield response.")

	var bow_yield := _state()
	bow_yield = _step(bow_yield, Policy.BAND_HEAVY, true, 0.0, 0.1)
	bow_yield = _step(bow_yield, Policy.BAND_WORKING, true, -0.5, 0.1)
	_record(report, "Forward rod bias can perform a controlled yield",
		bool(bow_yield.get("yield_done", false)),
		"The existing W/S pressure control should be a valid second route.")

	var passive_drop := _state()
	passive_drop = _step(passive_drop, Policy.BAND_HEAVY, true, 0.0, 0.1)
	passive_drop = _step(passive_drop, Policy.BAND_WORKING, true, 0.0, 0.1)
	_record(report, "Passive heavy-to-working movement does not count as yield",
		not bool(passive_drop.get("yield_done", false)),
		"The lesson should require a player response rather than random fish easing.")

	var slack_yield := _state()
	slack_yield = _step(slack_yield, Policy.BAND_HEAVY, true, 0.0, 0.1)
	slack_yield = _step(slack_yield, Policy.BAND_SLACK, false, 0.0, 0.1)
	_record(report, "Dumping heavy pressure into slack fails the yield attempt",
		not bool(slack_yield.get("yield_done", false))
		and not bool(slack_yield.get("yield_armed", true)),
		"Yield must preserve contact with the fish.")

	var overload := _state()
	overload = _step(overload, Policy.BAND_HEAVY, true, 0.0, 0.1)
	overload = _step(overload, Policy.BAND_OVERLOAD, true, 0.0, 0.1)
	_record(report, "Overload cancels the current yield setup",
		not bool(overload.get("yield_armed", true))
		and bool(overload.get("unsafe", false)),
		"The player must read heavy pressure before reaching line-break territory.")

	_record(report, "Slack is classified as unsafe",
		bool(_step(_state(), Policy.BAND_SLACK, false, 0.0, 0.1).get("unsafe", false)),
		"The lesson should clearly distinguish controlled yield from slack.")
	_record(report, "Overload is classified as unsafe",
		bool(_step(_state(), Policy.BAND_OVERLOAD, true, 0.0, 0.1).get("unsafe", false)),
		"The lesson should recognize excessive pressure as a mistake.")
	_record(report, "Working pressure is not unsafe",
		not bool(_step(_state(), Policy.BAND_WORKING, true, 0.0, 0.1).get("unsafe", true)),
		"Normal working pressure must remain the stable target.")

	_record(report, "All three demonstrations are required",
		not Policy.is_complete(true, true, false)
		and not Policy.is_complete(true, false, true)
		and not Policy.is_complete(false, true, true),
		"No single pressure trick should teach the entire mastery.")
	_record(report, "Pull hold and yield together complete Line Feel",
		Policy.is_complete(true, true, true),
		"The complete lesson should represent all three authored responses.")

	_record(report, "Fresh progress begins at zero",
		is_zero_approx(Policy.get_progress_ratio(false, 0.0, false, false)),
		"Lesson feedback should not grant phantom progress.")
	_record(report, "Partial hold contributes partial progress",
		Policy.get_progress_ratio(
			false,
			Policy.REQUIRED_HOLD_SECONDS * 0.5,
			false,
			false
		) > 0.0,
		"The sustained hold phase should give readable intermediate feedback.")
	_record(report, "Completed lesson progress reaches one",
		is_equal_approx(Policy.get_progress_ratio(true, 0.0, true, true), 1.0),
		"Progress display should agree with completion.")

	var full := _state()
	full = _step(full, Policy.BAND_LIGHT, false, 0.0, 0.1)
	full = _step(full, Policy.BAND_WORKING, true, 0.0, 0.35)
	full = _step(full, Policy.BAND_WORKING, true, 0.0, 0.35)
	full = _step(full, Policy.BAND_HEAVY, true, 0.0, 0.1)
	full = _step(full, Policy.BAND_WORKING, false, 0.0, 0.1)
	_record(report, "A realistic pressure sequence completes the lesson",
		bool(full.get("complete", false)),
		"The policy must be completable with ordinary fight inputs in one fish.")
	_record(report, "Completed demonstrations remain completed",
		bool(_step(full, Policy.BAND_SLACK, false, 0.0, 0.1).get("complete", false)),
		"A later pressure mistake should not erase a lesson already demonstrated before save.")

	mastery.free()
	unlock.free()
	return report


static func _state() -> Dictionary:
	return {
		"pull_armed": false,
		"pull_done": false,
		"hold_seconds": 0.0,
		"hold_done": false,
		"yield_armed": false,
		"yield_done": false,
	}


static func _step(
	state: Dictionary,
	band: StringName,
	player_reeling: bool,
	tension_bias: float,
	delta: float
) -> Dictionary:
	return Policy.advance_read(
		band,
		player_reeling,
		tension_bias,
		delta,
		bool(state.get("pull_armed", false)),
		bool(state.get("pull_done", false)),
		float(state.get("hold_seconds", 0.0)),
		bool(state.get("hold_done", false)),
		bool(state.get("yield_armed", false)),
		bool(state.get("yield_done", false))
	)


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
