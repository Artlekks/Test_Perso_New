extends Node
class_name FishingMasteryService

signal technique_learned(technique_id: StringName)
signal mastery_changed(snapshot: Dictionary)

const FLAG_PREFIX := "mastery.technique."

var _catalog: FishingMasteryTechniqueCatalog = null
var _unlock_state: FishingUnlockState = null


func configure(
	catalog: FishingMasteryTechniqueCatalog,
	unlock_state: FishingUnlockState
) -> void:
	_catalog = catalog
	_unlock_state = unlock_state


func has_technique(technique_id: StringName) -> bool:
	if _catalog == null or _catalog.get_technique(technique_id) == null:
		return false
	if _unlock_state == null:
		return false
	return _unlock_state.has_flag(_flag_id(technique_id))


func can_learn(
	technique_id: StringName,
	teacher_id: StringName
) -> Dictionary:
	if _catalog == null:
		return {"can_learn": false, "reason": "catalog_unavailable"}
	var technique := _catalog.get_technique(technique_id)
	if technique == null:
		return {"can_learn": false, "reason": "unknown_technique"}
	if has_technique(technique_id):
		return {"can_learn": false, "reason": "already_known"}
	if teacher_id == &"" or teacher_id != technique.teacher_id:
		return {
			"can_learn": false,
			"reason": "wrong_teacher",
			"required_teacher_id": str(technique.teacher_id),
		}
	for raw_prereq in technique.prerequisite_ids:
		var prereq := StringName(str(raw_prereq))
		if not has_technique(prereq):
			return {
				"can_learn": false,
				"reason": "missing_prerequisite",
				"missing_technique_id": str(prereq),
			}
	return {
		"can_learn": true,
		"reason": "ok",
		"technique_id": str(technique.technique_id),
		"teacher_id": str(technique.teacher_id),
	}


func learn_technique(
	technique_id: StringName,
	teacher_id: StringName,
	persist: bool = true
) -> Dictionary:
	var quote := can_learn(technique_id, teacher_id)
	if not bool(quote.get("can_learn", false)):
		return quote
	if _unlock_state == null:
		return {"can_learn": false, "reason": "unlock_state_unavailable"}
	if not _unlock_state.grant_flag(_flag_id(technique_id), persist):
		return {"can_learn": false, "reason": "grant_failed"}
	technique_learned.emit(technique_id)
	mastery_changed.emit(get_snapshot())
	return {
		"can_learn": true,
		"success": true,
		"reason": "learned",
		"technique_id": str(technique_id),
	}


func has_capability(capability: StringName) -> bool:
	if _catalog == null:
		return false
	for technique in _catalog.get_by_capability(capability):
		if has_technique(technique.technique_id):
			return true
	return false


func get_known_technique_ids() -> PackedStringArray:
	var result := PackedStringArray()
	if _catalog == null:
		return result
	for technique in _catalog.techniques:
		if technique != null and has_technique(technique.technique_id):
			result.append(str(technique.technique_id))
	result.sort()
	return result


func get_snapshot() -> Dictionary:
	var known := get_known_technique_ids()
	return {
		"known_count": known.size(),
		"total_count": _catalog.techniques.size() if _catalog != null else 0,
		"known_technique_ids": known,
		"can_read_current": has_capability(&"read_current"),
		"can_move_quietly": has_capability(&"quiet_approach"),
		"can_compensate_drift": has_capability(&"current_compensation"),
		"can_read_weather": has_capability(&"weather_sense"),
		"can_read_tide": has_capability(&"tide_sense"),
		"can_read_fish_sign": has_capability(&"read_fish_sign"),
		"can_be_one_with_nature": has_capability(&"one_with_nature"),
		"can_control_deep_water": has_capability(&"deep_water_control"),
		"can_control_surface": has_capability(&"surface_control"),
		"can_land_fish": has_capability(&"landing_technique"),
	}


func get_catalog() -> FishingMasteryTechniqueCatalog:
	return _catalog


func _flag_id(technique_id: StringName) -> StringName:
	return StringName(FLAG_PREFIX + str(technique_id).strip_edges().to_lower())
