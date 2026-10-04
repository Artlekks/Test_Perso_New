extends RefCounted
class_name FishingDeepWaterControlQA

const DeepWaterPolicy = preload(
	"res://scripts/fishing_deep_water_control_policy.gd"
)
const DeepWaterTechniqueResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/deep_water_control.tres"
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
		mastery_catalog.ensure_technique(DeepWaterTechniqueResource)

	var dive := {
		"intent_id": &"dive",
		"label": "DIVE",
		"intensity": 0.82,
		"duration": 1.0,
		"depth": -0.88,
		"pressure": 0.80,
		"thrashing": false,
	}
	var mild_dive := dive.duplicate(true)
	mild_dive["intensity"] = 0.56
	mild_dive["depth"] = -0.60
	mild_dive["pressure"] = 0.55

	_record(
		report,
		"Strong dive qualifies in deep water",
		DeepWaterPolicy.should_start(dive, 1.8, 5.0, 0.0),
		"A committed DIVE in deep water should create the delayed vertical-load event."
	)
	_record(
		report,
		"Non-dive intent does not qualify",
		not DeepWaterPolicy.should_start({"intent_id": &"rise", "intensity": 1.0, "depth": 1.0}, 2.0, 5.0, 0.0),
		"Deep-Water Control must not hijack RISE or generic fight intents."
	)
	var thrash_dive := dive.duplicate(true)
	thrash_dive["thrashing"] = true
	_record(
		report,
		"Thrash does not masquerade as deep dive",
		not DeepWaterPolicy.should_start(thrash_dive, 2.0, 5.0, 0.0),
		"THRASH already has its own response and must stay distinct from deep-water load."
	)
	_record(
		report,
		"Shallow water blocks deep-water event",
		not DeepWaterPolicy.should_start(dive, 1.0, 1.8, 0.0),
		"The mechanic should not appear in ordinary shallow fights."
	)
	var weak_dive := dive.duplicate(true)
	weak_dive["intensity"] = 0.30
	_record(
		report,
		"Weak dive stays ordinary",
		not DeepWaterPolicy.should_start(weak_dive, 2.0, 5.0, 0.0),
		"Small vertical movement should remain Reading-the-Run only."
	)
	_record(
		report,
		"Cooldown prevents deep-load spam",
		not DeepWaterPolicy.should_start(dive, 2.0, 5.0, 0.5),
		"Repeated dive intents need spacing so the mechanic stays readable."
	)

	var physical_ratio := DeepWaterPolicy.get_bait_depth_ratio(2.5, 5.0)
	_record(
		report,
		"Physical depth ratio is normalized",
		is_equal_approx(physical_ratio, 0.5),
		"Deep-water logic should consume the existing bait/total-depth measurements deterministically."
	)
	var effective_ratio := DeepWaterPolicy.get_effective_depth_ratio(0.2, 5.0, dive)
	_record(
		report,
		"Dive commitment can lead physical bait depth",
		effective_ratio > 0.60,
		"A hooked fish can commit downward before the bait node has fully caught up to its target depth."
	)

	var mild_delay := DeepWaterPolicy.get_follow_delay_seconds(mild_dive)
	var hard_delay := DeepWaterPolicy.get_follow_delay_seconds(dive)
	_record(
		report,
		"Follow delay remains readable",
		mild_delay >= DeepWaterPolicy.FOLLOW_DELAY_MIN_SECONDS and mild_delay <= DeepWaterPolicy.FOLLOW_DELAY_MAX_SECONDS and hard_delay >= DeepWaterPolicy.FOLLOW_DELAY_MIN_SECONDS and hard_delay <= DeepWaterPolicy.FOLLOW_DELAY_MAX_SECONDS,
		"The delayed load must stay inside the authored reaction cadence."
	)
	_record(
		report,
		"Hard dives load sooner",
		hard_delay < mild_delay,
		"A powerful fish should make the second beat arrive sooner rather than only changing a hidden number."
	)

	var mild_window := DeepWaterPolicy.get_recovery_window_seconds(mild_dive)
	var hard_window := DeepWaterPolicy.get_recovery_window_seconds(dive)
	_record(
		report,
		"Recovery window remains bounded",
		mild_window >= DeepWaterPolicy.RECOVERY_WINDOW_MIN_SECONDS and mild_window <= DeepWaterPolicy.RECOVERY_WINDOW_MAX_SECONDS and hard_window >= DeepWaterPolicy.RECOVERY_WINDOW_MIN_SECONDS and hard_window <= DeepWaterPolicy.RECOVERY_WINDOW_MAX_SECONDS,
		"The second input beat needs a stable human-scale response window."
	)
	_record(
		report,
		"Hard dives tighten recovery window",
		hard_window < mild_window,
		"Deep-water difficulty should be visible in timing as well as pressure."
	)

	var mild_load := DeepWaterPolicy.get_delayed_load_impulse(mild_dive, 1.5, 4.0)
	var hard_load := DeepWaterPolicy.get_delayed_load_impulse(dive, 3.5, 7.0)
	_record(
		report,
		"Deep load stays inside safe tuning ceiling",
		mild_load >= DeepWaterPolicy.LOAD_IMPULSE_MIN and hard_load <= DeepWaterPolicy.LOAD_IMPULSE_MAX,
		"Deep-water pressure should matter without becoming an arbitrary instant line break."
	)
	_record(
		report,
		"Harder deeper dive produces more load",
		hard_load > mild_load,
		"Depth and fish commitment should materially change the vertical fight."
	)

	_record(
		report,
		"K plus S is the recovery input",
		DeepWaterPolicy.is_recovery_response_matching(true, 0.75),
		"The taught second beat should use the existing high-rod fight input rather than inventing another button."
	)
	_record(
		report,
		"Released K cannot complete recovery",
		not DeepWaterPolicy.is_recovery_response_matching(false, 0.75),
		"The recovery beat should require regaining line contact after the initial give."
	)
	_record(
		report,
		"Low rod cannot complete recovery",
		not DeepWaterPolicy.is_recovery_response_matching(true, -0.75),
		"Bow-low belongs to giving line; deep recovery is the opposite second beat."
	)

	var match_time := DeepWaterPolicy.advance_match_time(0.0, true, 0.10)
	match_time = DeepWaterPolicy.advance_match_time(match_time, true, 0.10)
	_record(
		report,
		"Held recovery completes deterministically",
		DeepWaterPolicy.is_recovery_complete(match_time),
		"A short stable K+S hold should complete the technique."
	)
	var reset_match := DeepWaterPolicy.advance_match_time(0.10, false, 0.02)
	_record(
		report,
		"Broken recovery input resets hold",
		is_zero_approx(reset_match),
		"The technique should reward deliberate control rather than a one-frame tap."
	)

	var relief := DeepWaterPolicy.get_success_relief_impulse(hard_load, dive)
	_record(
		report,
		"Success relieves but does not erase deep load",
		relief < 0.0 and absf(relief) < hard_load,
		"Mastery should control a deep dive, not make deep water mechanically identical to shallow water."
	)
	var stamina_bonus := DeepWaterPolicy.get_stamina_bonus_ratio(dive)
	_record(
		report,
		"Successful recovery grants modest stamina edge",
		stamina_bonus >= DeepWaterPolicy.STAMINA_BONUS_MIN and stamina_bonus <= DeepWaterPolicy.STAMINA_BONUS_MAX,
		"Reading the vertical fight should help without replacing Pump & Reel or normal fatigue."
	)

	var deep_tech := mastery_catalog.get_technique(&"deep_water_control") if mastery_catalog != null else null
	_record(
		report,
		"Deep-Water Control is master-authored",
		deep_tech != null and deep_tech.teacher_id == &"master_deepwater_veteran" and deep_tech.has_capability(&"deep_water_control"),
		"The mechanic must remain part of the fishing-mastery spine rather than a hidden rank bonus."
	)
	_record(
		report,
		"Deep-Water Control requires Line Feel and Read Depth",
		_has_prerequisite(deep_tech, &"line_feel") and _has_prerequisite(deep_tech, &"read_depth"),
		"The advanced vertical technique should build on pressure awareness and depth reading."
	)

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var mastery := FishingMasteryService.new()
	mastery.configure(mastery_catalog, unlock)
	var blocked := mastery.can_learn(
		&"deep_water_control",
		deep_tech.teacher_id if deep_tech != null else &""
	)
	_record(
		report,
		"Deep-Water Control waits for prerequisites",
		str(blocked.get("reason", "")) == "missing_prerequisite",
		"The deep-water veteran should not teach the advanced technique before Line Feel and Read Depth."
	)

	for prereq_id in [&"line_feel", &"read_depth"]:
		var prereq = mastery_catalog.get_technique(prereq_id) if mastery_catalog != null else null
		if prereq != null:
			mastery.learn_technique(prereq_id, prereq.teacher_id, false)
	var learned := mastery.learn_technique(
		&"deep_water_control",
		deep_tech.teacher_id if deep_tech != null else &"",
		false
	)
	_record(
		report,
		"Deep-Water Control becomes runtime capability",
		bool(learned.get("success", false)) and mastery.has_capability(&"deep_water_control") and bool(mastery.get_snapshot().get("can_control_deep_water", false)),
		"Encounter needs one stable mastery capability gate for the second-stage recovery input."
	)

	var locked_snapshot := DeepWaterPolicy.build_snapshot(
		true,
		DeepWaterPolicy.PHASE_RECOVER,
		0.0,
		0.5,
		0.0,
		DeepWaterPolicy.RESULT_RECOVERING,
		0,
		dive,
		false,
		2.0,
		5.0,
		hard_load,
		0.0
	)
	var learned_snapshot := DeepWaterPolicy.build_snapshot(
		true,
		DeepWaterPolicy.PHASE_RECOVER,
		0.0,
		0.5,
		0.0,
		DeepWaterPolicy.RESULT_RECOVERING,
		0,
		dive,
		true,
		2.0,
		5.0,
		hard_load,
		0.0
	)
	_record(
		report,
		"Mastery reveals the second-beat response",
		locked_snapshot.get("expected_response", &"") == DeepWaterPolicy.RESPONSE_NONE and learned_snapshot.get("expected_response", &"") == DeepWaterPolicy.RESPONSE_HIGH_ROD,
		"The world load exists for everyone, while the taught technique exposes the trained recovery response."
	)

	mastery.free()
	unlock.free()
	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


static func _has_prerequisite(
	technique: FishingMasteryTechniqueDefinition,
	prerequisite_id: StringName
) -> bool:
	if technique == null:
		return false
	for raw_id in technique.prerequisite_ids:
		if str(raw_id) == str(prerequisite_id):
			return true
	return false


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
