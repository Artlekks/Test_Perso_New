extends RefCounted
class_name FishingMasterDeepwaterVeteranQA

const Policy = preload(
    "res://scripts/mastery/fishing_master_deepwater_veteran_policy.gd"
)
const DeepWaterResource: FishingMasteryTechniqueDefinition = preload(
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
        mastery_catalog.ensure_technique(DeepWaterResource)

    var definition := (
        mastery_catalog.get_technique(&"deep_water_control")
        if mastery_catalog != null
        else null
    )
    _record(report, "Deep-Water Control exists for the lesson",
        definition != null,
        "The master encounter must teach the canonical technique resource.")
    _record(report, "Deep-Water Veteran is the canonical teacher",
        definition != null and definition.teacher_id == &"master_deepwater_veteran",
        "The encounter must preserve the authored teacher identity.")
    _record(report, "Deep-Water Control exposes its capability",
        definition != null and definition.has_capability(&"deep_water_control"),
        "Completing the lesson must expose the existing runtime capability.")
    _record(report, "Line Feel is a prerequisite",
        _has_prerequisite(definition, &"line_feel"),
        "The deep lesson must build on pressure-reading skill.")
    _record(report, "Read the Depth is a prerequisite",
        _has_prerequisite(definition, &"read_depth"),
        "The deep lesson must build on depth-reading skill.")

    var unlock := FishingUnlockState.new()
    unlock.reset_unlocks(false)
    var mastery := FishingMasteryService.new()
    mastery.configure(mastery_catalog, unlock)

    var blocked := mastery.can_learn(&"deep_water_control", &"master_deepwater_veteran")
    _record(report, "Deep-Water Control is blocked before prerequisites",
        str(blocked.get("reason", "")) == "missing_prerequisite",
        "The master must not bypass Line Feel / Read the Depth progression.")

    var wrong_teacher := mastery.learn_technique(
        &"deep_water_control",
        &"not_the_deepwater_veteran",
        false
    )
    _record(report, "Wrong master cannot teach Deep-Water Control",
        str(wrong_teacher.get("reason", "")) == "wrong_teacher",
        "Master encounters must respect the canonical teacher id.")

    var line_feel = mastery_catalog.get_technique(&"line_feel") if mastery_catalog != null else null
    var read_depth = mastery_catalog.get_technique(&"read_depth") if mastery_catalog != null else null
    if line_feel != null:
        mastery.learn_technique(&"line_feel", line_feel.teacher_id, false)
    if read_depth != null:
        mastery.learn_technique(&"read_depth", read_depth.teacher_id, false)
    var ready := mastery.can_learn(&"deep_water_control", &"master_deepwater_veteran")
    _record(report, "Prerequisites make Deep-Water Control learnable",
        bool(ready.get("can_learn", false)),
        "The lesson should become available after both earlier masters are complete.")
    var learned := mastery.learn_technique(
        &"deep_water_control",
        &"master_deepwater_veteran",
        false
    )
    _record(report, "Deep-Water Veteran can teach Deep-Water Control",
        bool(learned.get("success", false)),
        "A completed lesson must persist the canonical technique.")
    _record(report, "Learned lesson exposes Deep-Water Control",
        mastery.has_capability(&"deep_water_control"),
        "The live fight should see the capability immediately after learning.")

    var dive := {
        "intent_id": &"dive",
        "thrashing": false,
    }
    _record(report, "Releasing K during DIVE counts as the first beat",
        Policy.is_initial_yield(dive, false),
        "The lesson should require yielding to the initial dive.")
    _record(report, "Holding K through DIVE does not count as yield",
        not Policy.is_initial_yield(dive, true),
        "The first beat must remain distinct from the high-rod recovery.")
    var run_intent := {"intent_id": &"run", "thrashing": false}
    _record(report, "Releasing K during a non-dive does not count",
        not Policy.is_initial_yield(run_intent, false),
        "The lesson must be tied to the actual DIVE behavior.")
    var thrash_dive := {"intent_id": &"dive", "thrashing": true}
    _record(report, "Thrash is not accepted as a clean dive read",
        not Policy.is_initial_yield(thrash_dive, false),
        "THRASH already has its own response and must stay separate.")

    var load_snapshot := _load_snapshot(0.72, 3.1, 5.0, 0.68, 0.11)
    _record(report, "Real deep DIVE load qualifies for the lesson",
        Policy.is_qualifying_load(load_snapshot),
        "The second beat should start only from a real deep-water load.")
    var no_load := load_snapshot.duplicate(true)
    no_load["load_impulse"] = 0.0
    _record(report, "Zero-load event cannot start the second beat",
        not Policy.is_qualifying_load(no_load),
        "The lesson must react to actual pressure from below.")
    var shallow := load_snapshot.duplicate(true)
    shallow["total_depth_m"] = 1.8
    _record(report, "Shallow water does not qualify",
        not Policy.is_qualifying_load(shallow),
        "Deep-Water Control should stay a genuinely deep-water lesson.")
    var low_ratio := load_snapshot.duplicate(true)
    low_ratio["depth_ratio"] = 0.35
    _record(report, "Low depth commitment does not qualify",
        not Policy.is_qualifying_load(low_ratio),
        "The lesson should not trigger from a superficial downward twitch.")
    var wrong_intent := load_snapshot.duplicate(true)
    wrong_intent["intent_id"] = &"rise"
    _record(report, "Non-dive load snapshot is rejected",
        not Policy.is_qualifying_load(wrong_intent),
        "The lesson must stay attached to the authored deep DIVE event.")

    var mild := _load_snapshot(0.55, 2.0, 4.0, 0.55, 0.08)
    var hard := _load_snapshot(0.92, 4.5, 7.0, 0.82, 0.15)
    var mild_window := Policy.get_response_window_seconds(mild)
    var hard_window := Policy.get_response_window_seconds(hard)
    _record(report, "Lesson response window stays inside deep-control bounds",
        mild_window >= 0.46 and mild_window <= 0.72
        and hard_window >= 0.46 and hard_window <= 0.72,
        "The master should teach the same reaction cadence as the real technique.")
    _record(report, "Harder deep load gives a tighter response window",
        hard_window < mild_window,
        "Powerful deep fish should preserve the authored tighter timing.")

    _record(report, "K plus high rod matches the recovery response",
        Policy.is_recovery_response_matching(true, 0.5),
        "The second beat should teach K + S / positive rod bias.")
    _record(report, "K without high rod does not match",
        not Policy.is_recovery_response_matching(true, 0.0),
        "Reeling alone must not teach Deep-Water Control.")
    _record(report, "High rod without K does not match",
        not Policy.is_recovery_response_matching(false, 0.5),
        "The recovery requires contact as well as rod position.")
    _record(report, "Bow input does not match deep recovery",
        not Policy.is_recovery_response_matching(true, -0.5),
        "The deep recovery must stay distinct from yielding/bowing responses.")

    var partial := Policy.advance_match_time(0.0, true, 0.5, 0.08)
    _record(report, "Short K plus S hold remains incomplete",
        not Policy.is_recovery_complete(partial),
        "A single input flick should not complete the lesson.")
    var interrupted := Policy.advance_match_time(partial, true, 0.0, 0.04)
    _record(report, "Breaking K plus S resets response hold",
        is_zero_approx(interrupted),
        "The second-beat response must be continuous.")
    var complete := Policy.advance_match_time(partial, true, 0.5, 0.08)
    _record(report, "Continuous K plus S completes the response hold",
        Policy.is_recovery_complete(complete),
        "The lesson should use the same 0.16-second hold as runtime control.")
    _record(report, "Lesson hold requirement matches Deep-Water Control",
        is_equal_approx(Policy.get_hold_required_seconds(), 0.16),
        "Teacher timing must stay aligned with the already-passed mechanic.")

    mastery.free()
    unlock.free()
    return report


static func _load_snapshot(
    intensity: float,
    current_depth_m: float,
    total_depth_m: float,
    depth_ratio: float,
    load_impulse: float
) -> Dictionary:
    return {
        "intent_id": &"dive",
        "intensity": intensity,
        "current_depth_m": current_depth_m,
        "total_depth_m": total_depth_m,
        "depth_ratio": depth_ratio,
        "load_impulse": load_impulse,
    }


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
