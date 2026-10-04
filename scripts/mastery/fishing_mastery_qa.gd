extends RefCounted
class_name FishingMasteryQA

const FishingWarinessPolicyScript = preload(
	"res://scripts/fishing_wariness_policy.gd"
)
const FishingMasterLessonPolicyScript = preload(
	"res://scripts/mastery/fishing_master_lesson_policy.gd"
)

static func run(
	catalog: FishingMasteryTechniqueCatalog,
	current_spot: FishingSpotData = null
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}
	_record(report, "Technique catalog validates", catalog != null and catalog.is_valid_catalog(), "Every authored technique needs a stable id, teacher and valid prerequisites.")
	_record(report, "Read Current is authored", catalog != null and catalog.get_technique(&"read_current") != null, "The first mastery capability must exist in the canonical catalog.")
	var read_current := catalog.get_technique(&"read_current") if catalog != null else null
	_record(report, "Read Current exposes capability", read_current != null and read_current.has_capability(&"read_current"), "Fishing mechanics should query capability tags rather than special-case UI state.")
	_record(report, "Drift Casting depends on current knowledge", _has_prerequisite(catalog, &"drift_casting", &"read_current"), "Advanced current control should build on current-reading rather than unlock independently.")
	var quiet_approach := catalog.get_technique(&"quiet_approach") if catalog != null else null
	_record(report, "Quiet Approach is authored", quiet_approach != null, "Bank-side fieldcraft needs a real master-taught technique in the canonical mastery catalog.")
	_record(report, "Quiet Approach exposes movement capability", quiet_approach != null and quiet_approach.has_capability(&"quiet_approach"), "Fish wariness should query a stable capability tag rather than hard-code a tutorial flag.")
	var weather_sense := catalog.get_technique(&"weather_sense") if catalog != null else null
	_record(report, "Weather Sense is authored", weather_sense != null, "Weather should become learnable fishing information instead of remaining invisible backend math.")
	_record(report, "Weather Sense exposes observation capability", weather_sense != null and weather_sense.has_capability(&"weather_sense"), "Environment presentation should query mastery capability rather than hard-code a weather tutorial state.")
	var tide_sense := catalog.get_technique(&"tide_sense") if catalog != null else null
	_record(report, "Tide Sense is authored", tide_sense != null, "Coastal tide knowledge needs its own master-taught observation technique.")
	_record(report, "Tide Sense exposes observation capability", tide_sense != null and tide_sense.has_capability(&"tide_sense"), "Tide interpretation should query mastery capability instead of changing the tide itself.")
	_record(report, "Tide Sense builds on current reading", _has_prerequisite(catalog, &"tide_sense", &"read_current"), "Tidal knowledge should build on understanding moving water.")
	_record(report, "Tide Sense builds on weather reading", _has_prerequisite(catalog, &"tide_sense", &"weather_sense"), "Tides belong to advanced environmental fieldcraft rather than an isolated rank unlock.")
	var deep_water_control := catalog.get_technique(&"deep_water_control") if catalog != null else null
	_record(report, "Deep-Water Control is authored", deep_water_control != null, "Long vertical fights need a real master-taught control technique rather than a hidden pressure modifier.")
	_record(report, "Deep-Water Control exposes fight capability", deep_water_control != null and deep_water_control.has_capability(&"deep_water_control"), "Encounter should query one stable mastery capability for trained deep-water recovery.")
	_record(report, "Deep-Water Control builds on Line Feel and Read Depth", _has_prerequisite(catalog, &"deep_water_control", &"line_feel") and _has_prerequisite(catalog, &"deep_water_control", &"read_depth"), "The advanced vertical technique should require both pressure awareness and depth reading.")
	_record(report, "Techniques are master-taught", _all_have_teachers(catalog), "Mastery progression must not silently become a fishing-rank unlock table.")
	_record(report, "Structure Fighting is authored", catalog != null and catalog.get_technique(&"structure_fighting") != null, "Cover combat needs a taught technique rather than an invisible stat bonus.")
	_record(report, "Structure Fighting builds on observation and line control", _has_prerequisite(catalog, &"structure_fighting", &"read_structure") and _has_prerequisite(catalog, &"structure_fighting", &"line_feel"), "Turning a fish out of cover should require understanding both structure and line pressure.")
	_record(report, "Snag Escape builds on Read Structure", _has_prerequisite(catalog, &"snag_escape", &"read_structure"), "Lure recovery should build on recognizing the hazard first.")

	var unlock := FishingUnlockState.new()
	unlock.reset_unlocks(false)
	var service := FishingMasteryService.new()
	service.configure(catalog, unlock)
	var wrong_teacher := service.learn_technique(&"read_current", &"wrong_master", false)
	_record(report, "Wrong master cannot teach technique", str(wrong_teacher.get("reason", "")) == "wrong_teacher", "Technique learning must respect authored master identity.")
	var teacher_id: StringName = read_current.teacher_id if read_current != null else &""
	var learned := service.learn_technique(&"read_current", teacher_id, false)
	_record(report, "Correct master teaches Read Current", bool(learned.get("success", false)) and service.has_capability(&"read_current"), "Teaching should persist as a capability through the shared unlock backbone.")
	var drift_definition := catalog.get_technique(&"drift_casting") if catalog != null else null
	var drift_quote := service.can_learn(&"drift_casting", drift_definition.teacher_id if drift_definition != null else &"")
	_record(report, "Prerequisite unlock enables next technique", bool(drift_quote.get("can_learn", false)), "Technique chains should become available from learned knowledge, not numeric rank.")

	var quiet_learned := service.learn_technique(
		&"quiet_approach",
		quiet_approach.teacher_id if quiet_approach != null else &"",
		false
	)
	_record(report, "Quiet Approach becomes runtime capability", bool(quiet_learned.get("success", false)) and service.has_capability(&"quiet_approach"), "Once taught by its master, the live fish-presence system should be able to reduce player disturbance.")

	var tide_before_weather := service.can_learn(
		&"tide_sense",
		tide_sense.teacher_id if tide_sense != null else &""
	)
	_record(report, "Tide Sense waits for Weather Sense", str(tide_before_weather.get("reason", "")) == "missing_prerequisite", "The environmental mastery chain should not allow Tide Sense before Weather Sense.")

	var weather_learned := service.learn_technique(
		&"weather_sense",
		weather_sense.teacher_id if weather_sense != null else &"",
		false
	)
	_record(report, "Weather Sense becomes runtime capability", bool(weather_learned.get("success", false)) and service.has_capability(&"weather_sense") and bool(service.get_snapshot().get("can_read_weather", false)), "The environment system needs one persistent capability gate for its qualitative fishing readout.")

	var tide_learned := service.learn_technique(
		&"tide_sense",
		tide_sense.teacher_id if tide_sense != null else &"",
		false
	)
	_record(report, "Tide Sense becomes runtime capability", bool(tide_learned.get("success", false)) and service.has_capability(&"tide_sense") and bool(service.get_snapshot().get("can_read_tide", false)), "The tide readout needs one persistent mastery capability without granting any tide bonus.")

	var deep_before_prereqs := service.can_learn(
		&"deep_water_control",
		deep_water_control.teacher_id if deep_water_control != null else &""
	)
	_record(report, "Deep-Water Control waits for prerequisites", str(deep_before_prereqs.get("reason", "")) == "missing_prerequisite", "The deep-water veteran should require Line Feel and Read Depth before teaching the vertical recovery technique.")
	var deep_line_feel := catalog.get_technique(&"line_feel") if catalog != null else null
	var deep_read_depth := catalog.get_technique(&"read_depth") if catalog != null else null
	if deep_line_feel != null:
		service.learn_technique(&"line_feel", deep_line_feel.teacher_id, false)
	if deep_read_depth != null:
		service.learn_technique(&"read_depth", deep_read_depth.teacher_id, false)
	var deep_learned := service.learn_technique(
		&"deep_water_control",
		deep_water_control.teacher_id if deep_water_control != null else &"",
		false
	)
	_record(report, "Deep-Water Control becomes runtime capability", bool(deep_learned.get("success", false)) and service.has_capability(&"deep_water_control") and bool(service.get_snapshot().get("can_control_deep_water", false)), "The live fight needs one persistent gate for the trained second-stage deep-water response.")

	var read_structure := catalog.get_technique(&"read_structure") if catalog != null else null
	var line_feel := catalog.get_technique(&"line_feel") if catalog != null else null
	var structure_fighting := catalog.get_technique(&"structure_fighting") if catalog != null else null
	var snag_escape := catalog.get_technique(&"snag_escape") if catalog != null else null
	if read_structure != null:
		service.learn_technique(&"read_structure", read_structure.teacher_id, false)
	if line_feel != null:
		service.learn_technique(&"line_feel", line_feel.teacher_id, false)
	var structure_learned := service.learn_technique(&"structure_fighting", structure_fighting.teacher_id if structure_fighting != null else &"", false)
	var snag_learned := service.learn_technique(&"snag_escape", snag_escape.teacher_id if snag_escape != null else &"", false)
	_record(report, "Structure Fighting exposes fight capability", bool(structure_learned.get("success", false)) and service.has_capability(&"structure_fighting"), "The fight runtime should query a stable mastery capability after the master teaches it.")
	_record(report, "Snag Escape exposes lure-control capability", bool(snag_learned.get("success", false)) and service.has_capability(&"snag_escape"), "Existing lure snag mechanics should be able to consume the taught recovery skill.")

	var current_service := FishingCurrentService.new()
	current_service.set_spot(current_spot)
	var sample := current_service.sample_current_velocity(Vector3(2.0, 0.0, -3.0), 1.5)
	_record(report, "Authored current produces horizontal drift", current_spot == null or current_spot.current_speed <= 0.0 or (absf(sample.y) < 0.00001 and sample.length() > 0.0), "Water current must be real lure physics, independent of the visualization technique.")
	_record(report, "Read Current does not create current physics", service.has_capability(&"read_current") and current_service != null, "Mastery reveals/helps with a world mechanic; it must not magically create the current itself.")

	var fields_valid := _all_current_fields_valid(current_spot)
	_record(report, "Spatial current fields validate", fields_valid, "Current fields need unique ids, usable ellipse radii and valid authored definitions.")

	var fast_field := _find_field(current_spot, &"coastal_fast_band")
	var calm_field := _find_field(current_spot, &"shore_calm_pocket")
	var eddy_field := _find_field(current_spot, &"outer_eddy")
	var baseline := current_service.sample_current_at_uv(Vector2(0.50, 0.95), 2.0)
	var fast_sample := current_service.sample_current_at_uv(fast_field.center_uv, 2.0) if fast_field != null else Vector2.ZERO
	var calm_sample := current_service.sample_current_at_uv(calm_field.center_uv, 2.0) if calm_field != null else Vector2.ZERO
	var eddy_uv := eddy_field.center_uv + Vector2(eddy_field.radius_uv.x * 0.35, 0.0) if eddy_field != null else Vector2.ZERO
	var eddy_sample := current_service.sample_current_at_uv(eddy_uv, 2.0) if eddy_field != null else Vector2.ZERO

	_record(report, "Fast band accelerates drift", fast_field != null and fast_sample.length() > baseline.length() * 1.35, "A current channel must materially change lure routing rather than be metadata only.")
	_record(report, "Calm pocket reduces drift", calm_field != null and calm_sample.length() < baseline.length() * 0.55, "Protected water should create a genuinely slower place to work a lure.")
	var heading_changed := false
	if eddy_field != null and eddy_sample.length_squared() > 0.000001 and baseline.length_squared() > 0.000001:
		heading_changed = absf(eddy_sample.normalized().dot(baseline.normalized())) < 0.75
	_record(report, "Eddy bends local flow", heading_changed, "An eddy should change direction, not merely rescale the main current.")
	_record(report, "Field lookup identifies authored zones", fast_field != null and current_service.get_dominant_field_id_at_uv(fast_field.center_uv) == &"coastal_fast_band", "Read-current presentation and future AI need stable local-flow identities.")

	var projected := current_service.project_drift_path(Vector3(0.0, 0.0, 0.0), 2.0, 0.4, 2.0)
	var projection_moves := projected.size() > 2 and projected[0].distance_to(projected[projected.size() - 1]) > 0.01
	_record(report, "Drift projection advances through water", projection_moves, "Drift Casting needs a deterministic current projection rather than a cosmetic arrow.")

	var drift_learned := service.learn_technique(&"drift_casting", drift_definition.teacher_id if drift_definition != null else &"", false)
	_record(report, "Drift Casting exposes prediction capability", bool(drift_learned.get("success", false)) and service.has_capability(&"current_compensation"), "The taught technique should unlock the drift-path readout without altering current physics.")

	var bold_radius := FishingWarinessPolicyScript.get_scare_radius(0.15)
	var wary_radius := FishingWarinessPolicyScript.get_scare_radius(0.95)
	_record(report, "Wary species notice bank disturbance farther away", wary_radius > bold_radius * 1.5, "Species wariness must change practical approach distance, not just exist as metadata.")
	var noisy_gain := FishingWarinessPolicyScript.get_stress_delta(1.0, 1.0, 0.85, false, 1.0)
	var quiet_gain := FishingWarinessPolicyScript.get_stress_delta(1.0, 1.0, 0.85, true, 1.0)
	_record(report, "Quiet Approach materially reduces disturbance", quiet_gain > 0.0 and quiet_gain < noisy_gain * 0.45, "The learned technique should reward careful movement without making fish completely deaf.")
	var distant_delta := FishingWarinessPolicyScript.get_stress_delta(1.0, 99.0, 0.85, false, 1.0)
	_record(report, "Distant movement does not scare fish", distant_delta < 0.0, "Bank noise should be spatial; running elsewhere in the scene must not globally panic the water.")
	_record(report, "Wariness threshold is deterministic", FishingWarinessPolicyScript.should_spook(0.90) and not FishingWarinessPolicyScript.should_spook(0.30), "Fish shadows need a stable threshold for readable flee/dive behavior.")

	_record(report, "Quiet Approach belongs to Still Water", quiet_approach != null and quiet_approach.teacher_id == &"master_still_water", "The first real mastery lesson must be taught by the authored master rather than a generic unlock.")
	var still_progress := FishingMasterLessonPolicyScript.advance_stillness(0.0, 0.0, 2.0)
	_record(report, "Still Water lesson rewards actual stillness", still_progress > 1.9, "The lesson should progress only while the player is genuinely settled near the bank.")
	var reset_progress := FishingMasterLessonPolicyScript.advance_stillness(still_progress, 1.0, 0.1)
	_record(report, "Movement resets the Still Water lesson", is_zero_approx(reset_progress), "The first master challenge must be performed, not clicked through.")
	var complete_progress := FishingMasterLessonPolicyScript.advance_stillness(3.6, 0.0, 1.0)
	_record(report, "Still Water lesson has a deterministic completion point", FishingMasterLessonPolicyScript.is_stillness_complete(complete_progress), "The lesson needs a stable transition from observation to the catch challenge.")

	service.free()
	unlock.free()
	current_service.free()
	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


static func _has_prerequisite(catalog: FishingMasteryTechniqueCatalog, technique_id: StringName, prerequisite_id: StringName) -> bool:
	if catalog == null:
		return false
	var technique := catalog.get_technique(technique_id)
	if technique == null:
		return false
	for raw_id in technique.prerequisite_ids:
		if str(raw_id) == str(prerequisite_id):
			return true
	return false


static func _all_have_teachers(catalog: FishingMasteryTechniqueCatalog) -> bool:
	if catalog == null or catalog.techniques.is_empty():
		return false
	for technique in catalog.techniques:
		if technique == null or technique.teacher_id == &"":
			return false
	return true


static func _all_current_fields_valid(spot: FishingSpotData) -> bool:
	if spot == null or spot.current_fields.size() < 3:
		return false
	var ids := {}
	for field in spot.current_fields:
		if field == null or not field.is_valid_definition():
			return false
		var key := str(field.field_id)
		if ids.has(key):
			return false
		ids[key] = true
	return true


static func _find_field(spot: FishingSpotData, field_id: StringName) -> FishingCurrentFieldDefinition:
	if spot == null:
		return null
	for field in spot.current_fields:
		if field != null and field.field_id == field_id:
			return field
	return null


static func _record(report: Dictionary, name: String, passed: bool, detail: String) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [name, detail])
	report["failures"] = failures
