extends RefCounted
class_name FishingMasterSurfaceAnglerQA

const Policy = preload(
	"res://scripts/mastery/fishing_master_surface_angler_policy.gd"
)
const SurfacePolicy = preload(
	"res://scripts/fishing_surface_control_policy.gd"
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

	var definition = mastery_catalog.get_technique(&"surface_control") if mastery_catalog != null else null
	_record(report, "Surface Control exists in mastery catalog",
		definition != null,
		"The master lesson requires the canonical surface_control technique.")
	if definition != null:
		_record(report, "Surface Angler is the canonical teacher",
			StringName(str(definition.teacher_id)) == &"master_surface_angler",
			"The encounter must not invent a second teacher id.")
		_record(report, "Surface Control requires Line Feel",
			_has_prerequisite(definition, &"line_feel"),
			"The fight-teaching order should remain Line Feel -> Surface Control.")

	var unlock = UnlockStateScript.new()
	unlock.initialize()
	var mastery = MasteryServiceScript.new()
	mastery.configure(mastery_catalog, unlock)

	var blocked := mastery.can_learn(&"surface_control", &"master_surface_angler")
	_record(report, "Surface Control is blocked before Line Feel",
		not bool(blocked.get("can_learn", false)),
		"The Surface Angler lesson should preserve its prerequisite gate.")
	var line_feel = mastery_catalog.get_technique(&"line_feel") if mastery_catalog != null else null
	if line_feel != null:
		mastery.learn_technique(&"line_feel", line_feel.teacher_id, false)
	var ready := mastery.can_learn(&"surface_control", &"master_surface_angler")
	_record(report, "Line Feel makes Surface Control learnable",
		bool(ready.get("can_learn", false)),
		"Completing Line Fighter should unlock the Surface Angler lesson.")
	var learned := mastery.learn_technique(&"surface_control", &"master_surface_angler", false)
	_record(report, "Surface Angler can teach Surface Control",
		bool(learned.get("success", false)),
		"A successful lesson must persist the canonical mastery.")
	_record(report, "Learned lesson exposes Surface Control capability",
		mastery.has_capability(&"surface_control"),
		"The existing fight system should see the capability immediately.")

	var surge := _intent(&"surge_away", 0.72, 0.0, false)
	var side_right := _intent(&"side_run", 0.70, 0.8, false)
	var rise := _intent(&"rise", 0.65, 0.0, false)
	var erratic := _intent(&"erratic", 0.75, 0.0, false)
	var thrash := _intent(&"run", 0.80, 0.0, true)
	var weak := _intent(&"rise", 0.20, 0.0, false)
	var dive := _intent(&"dive", 0.80, 0.0, false)

	_record(report, "Surface surge teaches low-rod ease",
		Policy.get_expected_response(surge) == SurfacePolicy.RESPONSE_LOW_EASE,
		"Surging surface fish should teach release K + W.")
	_record(report, "Surface side run teaches low-rod counter",
		Policy.get_expected_response(side_right) == SurfacePolicy.RESPONSE_LOW_COUNTER,
		"Side runs should preserve counter-steering while the rod stays low.")
	_record(report, "Surface rise teaches low-rod reel",
		Policy.get_expected_response(rise) == SurfacePolicy.RESPONSE_LOW_REEL,
		"A non-aerial rise should keep contact with K + W.")
	_record(report, "Surface erratic teaches low-rod steady",
		Policy.get_expected_response(erratic) == SurfacePolicy.RESPONSE_LOW_STEADY,
		"Erratic surface movement should use neutral steering with K + W.")
	_record(report, "Surface thrash teaches low-rod ease",
		Policy.get_expected_response(thrash) == SurfacePolicy.RESPONSE_LOW_EASE,
		"Thrash should teach release K + W, matching runtime Surface Control.")
	_record(report, "Dive is not a Surface Control lesson event",
		Policy.get_expected_response(dive) == SurfacePolicy.RESPONSE_NONE,
		"Deep-Water Control must remain a separate mastery.")

	var surface := _surface_snapshot(0.30, 3.0, 0.045, true)
	_record(report, "Real near-surface surge qualifies",
		Policy.is_qualifying_event(surface, surge),
		"The lesson should listen to a real surface-instability event.")
	_record(report, "Real near-surface side run qualifies",
		Policy.is_qualifying_event(surface, side_right),
		"Directional surface behavior should be teachable.")
	_record(report, "Weak intent does not qualify",
		not Policy.is_qualifying_event(surface, weak),
		"Tiny surface twitches should not open a mastery response window.")
	var deep := _surface_snapshot(2.2, 3.0, 0.045, false)
	_record(report, "Deep-water event does not qualify",
		not Policy.is_qualifying_event(deep, surge),
		"Surface Angler must stay restricted to the top layer.")
	var no_impulse := _surface_snapshot(0.30, 3.0, 0.0, true)
	_record(report, "Zero-instability event does not qualify",
		not Policy.is_qualifying_event(no_impulse, surge),
		"The lesson should come from a real surface load, not a synthetic prompt.")

	var mild_window := Policy.get_response_window_seconds(_intent(&"rise", 0.45, 0.0, false))
	var hard_window := Policy.get_response_window_seconds(_intent(&"rise", 0.95, 0.0, false))
	_record(report, "Lesson window stays inside Surface Control bounds",
		mild_window >= 0.42 and mild_window <= 0.68 and hard_window >= 0.42 and hard_window <= 0.68,
		"Teacher timing must match the already-passed mechanic.")
	_record(report, "Harder surface burst gives tighter timing",
		hard_window < mild_window,
		"Violent surface behavior should preserve authored difficulty.")

	_record(report, "Surge accepts release K plus low rod",
		Policy.is_response_matching(SurfacePolicy.RESPONSE_LOW_EASE, surge, false, 0.0, -0.5),
		"The lesson should accept the canonical low-rod ease response.")
	_record(report, "Surge rejects upright rod",
		not Policy.is_response_matching(SurfacePolicy.RESPONSE_LOW_EASE, surge, false, 0.0, 0.0),
		"W / low rod is the defining addition taught by Surface Control.")
	_record(report, "Right side run accepts K plus W plus left counter",
		Policy.is_response_matching(SurfacePolicy.RESPONSE_LOW_COUNTER, side_right, true, -0.8, -0.5),
		"Counter-steering must oppose the fish while maintaining low rod.")
	_record(report, "Right side run rejects same-direction steering",
		not Policy.is_response_matching(SurfacePolicy.RESPONSE_LOW_COUNTER, side_right, true, 0.8, -0.5),
		"Following a side run with the steering input is not a counter.")
	_record(report, "Rise accepts K plus low rod",
		Policy.is_response_matching(SurfacePolicy.RESPONSE_LOW_REEL, rise, true, 0.0, -0.5),
		"The lesson should preserve contact on a non-aerial rise.")
	_record(report, "Rise rejects releasing K",
		not Policy.is_response_matching(SurfacePolicy.RESPONSE_LOW_REEL, rise, false, 0.0, -0.5),
		"Surface rise is not the same response as a surge or thrash.")
	_record(report, "Erratic accepts neutral K plus low rod",
		Policy.is_response_matching(SurfacePolicy.RESPONSE_LOW_STEADY, erratic, true, 0.0, -0.5),
		"Erratic fish should be steadied rather than chased side to side.")
	_record(report, "Erratic rejects strong steering",
		not Policy.is_response_matching(SurfacePolicy.RESPONSE_LOW_STEADY, erratic, true, 0.8, -0.5),
		"Neutral steering is part of the authored response.")

	var partial := Policy.advance_match_time(0.0, true, 0.07)
	_record(report, "Short correct hold remains incomplete",
		not Policy.is_response_complete(partial),
		"A single input flick should not teach the mastery.")
	var interrupted := Policy.advance_match_time(partial, false, 0.02)
	_record(report, "Breaking the response resets the hold",
		is_zero_approx(interrupted),
		"The teaching response must be continuous.")
	var complete := Policy.advance_match_time(partial, true, 0.07)
	_record(report, "Continuous response completes the hold",
		Policy.is_response_complete(complete),
		"The lesson should use the same 0.14-second hold as runtime control.")
	_record(report, "Lesson hold matches Surface Control",
		is_equal_approx(Policy.get_hold_required_seconds(), 0.14),
		"Teacher cadence must stay aligned with the existing mechanic.")

	mastery.free()
	unlock.free()
	return report


static func _intent(
	intent_id: StringName,
	intensity: float,
	lateral: float,
	thrashing: bool
) -> Dictionary:
	return {
		"intent_id": intent_id,
		"label": str(intent_id).to_upper(),
		"intensity": intensity,
		"pressure": 0.65,
		"lateral": lateral,
		"thrashing": thrashing,
	}


static func _surface_snapshot(
	current_depth_m: float,
	total_depth_m: float,
	instability_impulse: float,
	near_surface: bool
) -> Dictionary:
	return {
		"current_depth_m": current_depth_m,
		"total_depth_m": total_depth_m,
		"instability_impulse": instability_impulse,
		"near_surface": near_surface,
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
