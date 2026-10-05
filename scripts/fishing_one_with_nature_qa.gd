extends RefCounted
class_name FishingOneWithNatureQA

const Policy = preload("res://scripts/fishing_one_with_nature_policy.gd")
const ReadFishSignResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/read_fish_sign.tres"
)
const TechniqueResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/one_with_nature.tres"
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
		mastery_catalog.ensure_technique(ReadFishSignResource)
		mastery_catalog.ensure_technique(TechniqueResource)

	var definition := (
		mastery_catalog.get_technique(&"one_with_nature")
		if mastery_catalog != null
		else null
	)
	_record(
		report,
		"One With Nature registers incrementally",
		definition != null,
		"The capstone should append without replacing the canonical mastery catalog."
	)
	_record(
		report,
		"One With Nature exposes one stable capability",
		definition != null and definition.has_capability(&"one_with_nature"),
		"Ambient fish should query one capability rather than a tutorial-specific flag."
	)
	_record(
		report,
		"One With Nature keeps a future master identity",
		definition != null and definition.teacher_id == &"master_nature_guide",
		"The capstone remains master-taught instead of becoming a hidden rank reward."
	)
	_record(
		report,
		"One With Nature requires Quiet Approach",
		_has_prerequisite(definition, &"quiet_approach"),
		"The capstone should build on bank-side stillness."
	)
	_record(
		report,
		"One With Nature requires Read Fish Sign",
		_has_prerequisite(definition, &"read_fish_sign"),
		"The capstone should build on observing fish rather than bypassing observation."
	)

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var mastery := FishingMasteryService.new()
	mastery.configure(mastery_catalog, unlock)

	var blocked := mastery.learn_technique(
		&"one_with_nature",
		definition.teacher_id if definition != null else &"",
		false
	)
	_record(
		report,
		"Capstone is blocked before prerequisites",
		str(blocked.get("reason", "")) == "missing_prerequisite",
		"One With Nature must not be teachable before its fieldcraft foundation."
	)

	var quiet := mastery_catalog.get_technique(&"quiet_approach") if mastery_catalog != null else null
	var sign_definition := mastery_catalog.get_technique(&"read_fish_sign") if mastery_catalog != null else null
	if quiet != null:
		mastery.learn_technique(&"quiet_approach", quiet.teacher_id, false)
	if sign_definition != null:
		mastery.learn_technique(&"read_fish_sign", sign_definition.teacher_id, false)
	var learned := mastery.learn_technique(
		&"one_with_nature",
		definition.teacher_id if definition != null else &"",
		false
	)
	_record(
		report,
		"Prerequisites allow the capstone to be learned",
		bool(learned.get("success", false))
		and mastery.has_capability(&"one_with_nature"),
		"The shared mastery service should expose the learned capstone capability."
	)
	_record(
		report,
		"Mastery snapshot reports attunement capability",
		bool(mastery.get_snapshot().get("can_be_one_with_nature", false)),
		"Runtime systems need one stable snapshot field for the capstone."
	)

	var settle := Policy.advance_settle_time(0.0, 0.0, 2.0, true)
	_record(
		report,
		"Stillness builds attunement progress",
		settle > 1.99 and settle < Policy.SETTLE_SECONDS,
		"The player should have to genuinely settle rather than gain the bonus instantly."
	)
	settle = Policy.advance_settle_time(settle, 0.02, 2.0, true)
	_record(
		report,
		"Sustained quiet completes attunement",
		Policy.is_attuned(true, settle),
		"Low residual movement should still allow a fully settled stance."
	)
	var broken := Policy.advance_settle_time(settle, 0.40, 0.1, true)
	_record(
		report,
		"Movement breaks attunement immediately",
		is_zero_approx(broken),
		"One With Nature must reward actual fieldcraft, not become a permanent passive buff."
	)
	var unavailable := Policy.advance_settle_time(0.0, 0.0, 10.0, false)
	_record(
		report,
		"Unlearned capstone cannot accumulate attunement",
		is_zero_approx(unavailable),
		"Runtime stillness must stay gated by the learned mastery."
	)

	var wary_natural := Policy.get_approach_multiplier(0.92, 1.25, true)
	var bold_natural := Policy.get_approach_multiplier(0.20, 1.25, true)
	var wary_poor := Policy.get_approach_multiplier(0.92, 0.70, true)
	var wary_unsettled := Policy.get_approach_multiplier(0.92, 1.25, false)
	_record(
		report,
		"Attuned natural presentation helps wary fish approach",
		wary_natural > 1.10 and wary_natural <= Policy.MAX_APPROACH_MULTIPLIER,
		"The capstone should make a meaningful but bounded difference to sensitive fish."
	)
	_record(
		report,
		"Bold fish receive little or no extra approach help",
		bold_natural < wary_natural and bold_natural <= 1.01,
		"One With Nature should solve wariness, not globally inflate every visible fish."
	)
	_record(
		report,
		"Poor lure presentation receives no capstone bonus",
		is_equal_approx(wary_poor, 1.0),
		"Stillness alone must not excuse an unnatural retrieve."
	)
	_record(
		report,
		"Unsettled player receives no capstone bonus",
		is_equal_approx(wary_unsettled, 1.0),
		"The reward must disappear as soon as the player stops being settled."
	)

	var wary_stress := Policy.get_positive_stress_multiplier(0.92, true)
	var bold_stress := Policy.get_positive_stress_multiplier(0.20, true)
	var normal_stress := Policy.get_positive_stress_multiplier(0.92, false)
	_record(
		report,
		"Attunement softens residual stress for wary fish",
		wary_stress < 0.80 and wary_stress >= 1.0 - Policy.MAX_STRESS_REDUCTION,
		"Tiny bank noise after settling should matter less to highly sensitive fish without making them deaf."
	)
	_record(
		report,
		"Bold fish keep normal stress behavior",
		bold_stress >= 0.99,
		"The capstone should not flatten species wariness differences."
	)
	_record(
		report,
		"No attunement means no stress reduction",
		is_equal_approx(normal_stress, 1.0),
		"Before the player settles, existing wariness remains authoritative."
	)

	var snapshot := Policy.build_snapshot(true, Policy.SETTLE_SECONDS, 0.01)
	_record(
		report,
		"Attunement snapshot is player-facing and deterministic",
		bool(snapshot.get("available", false))
		and bool(snapshot.get("attuned", false))
		and is_equal_approx(float(snapshot.get("settle_ratio", 0.0)), 1.0),
		"Future UI and master lessons need one compact runtime readout."
	)
	_record(
		report,
		"Snapshot does not expose forbidden reward knobs",
		not snapshot.has("spawn_multiplier")
		and not snapshot.has("king_chance")
		and not snapshot.has("specimen_multiplier"),
		"One With Nature must not become a hidden rarity or specimen-quality buff."
	)

	_record(
		report,
		"Approach bonus stays below seventeen percent",
		Policy.MAX_APPROACH_MULTIPLIER <= 1.16,
		"The capstone should reward mastery without invalidating lure choice or fish personality."
	)
	_record(
		report,
		"Stress reduction stays below thirty percent",
		Policy.MAX_STRESS_REDUCTION <= 0.28,
		"Species wariness should remain meaningful even at mastery capstone."
	)

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
