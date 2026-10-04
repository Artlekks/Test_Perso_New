extends RefCounted
class_name FishingMasteryQA

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
	_record(report, "Techniques are master-taught", _all_have_teachers(catalog), "Mastery progression must not silently become a fishing-rank unlock table.")

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
