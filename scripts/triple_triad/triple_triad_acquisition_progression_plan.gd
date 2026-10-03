extends RefCounted
class_name TripleTriadAcquisitionProgressionPlan

const DATA_PATH := "res://data/triple_triad/acquisition/early_progression_plan_v1.json"
const SCHEMA_VERSION := 1

var _root: Dictionary = {}
var _stages: Array = []
var _load_errors := PackedStringArray()


func _init() -> void:
	_load_data()


func get_plan_id() -> StringName:
	return StringName(str(_root.get("plan_id", "")))


func get_all_stage_snapshots() -> Array:
	return _stages.duplicate(true)


func get_stage_snapshot(stage_id: StringName) -> Dictionary:
	for raw_stage in _stages:
		if not (raw_stage is Dictionary):
			continue
		var stage: Dictionary = raw_stage
		if str(stage.get("stage_id", "")) == String(stage_id):
			return stage.duplicate(true)
	return {}


func validate(
	world_catalog,
	card_catalog: Resource = null
) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	for load_error in _load_errors:
		errors.append(load_error)

	if world_catalog == null or not world_catalog.has_method("get_source_snapshot"):
		errors.append("world acquisition catalog unavailable")
		return _result(errors, warnings, [])

	var seen_stage_ids: Dictionary = {}
	var seen_primary_cards: Dictionary = {}
	var cumulative_sources: Array = []
	var stage_results: Array = []
	var previous_hour: int = -1

	for raw_stage in _stages:
		if not (raw_stage is Dictionary):
			errors.append("progression plan contains a non-Dictionary stage")
			continue
		var stage: Dictionary = raw_stage
		var stage_id: String = str(stage.get("stage_id", "")).strip_edges()
		var milestone_hour: int = int(stage.get("milestone_hour", -1))
		var rank_floor: int = maxi(1, int(stage.get("duel_rank_floor", 1)))
		var target_min: int = maxi(0, int(stage.get("target_owned_min", 0)))
		var target_max: int = maxi(0, int(stage.get("target_owned_max", 0)))
		var expected_pool: int = maxi(0, int(stage.get("expected_cumulative_pool", 0)))

		if stage_id.is_empty():
			errors.append("progression plan stage has empty stage_id")
			continue
		if seen_stage_ids.has(stage_id):
			errors.append("duplicate progression stage id: %s" % stage_id)
			continue
		seen_stage_ids[stage_id] = true
		if milestone_hour < previous_hour:
			errors.append("progression stage hours are not monotonic at %s" % stage_id)
		previous_hour = milestone_hour
		if target_max < target_min:
			errors.append("%s target_owned_max is below target_owned_min" % stage_id)

		var raw_new_sources = stage.get("new_sources", [])
		if not (raw_new_sources is Array):
			errors.append("%s new_sources must be an Array" % stage_id)
			continue
		for raw_ref in raw_new_sources:
			if not (raw_ref is Dictionary):
				errors.append("%s contains invalid source reference" % stage_id)
				continue
			var source_type := StringName(str(raw_ref.get("source_type", "")))
			var source_id := StringName(str(raw_ref.get("source_id", "")))
			var source: Dictionary = world_catalog.call(
				"get_source_snapshot",
				source_type,
				source_id
			)
			if source.is_empty():
				errors.append(
					"%s references unknown source %s:%s"
					% [stage_id, String(source_type), String(source_id)]
				)
				continue
			if int(source.get("min_duel_rank", 1)) > rank_floor:
				errors.append(
					"%s exposes %s:%s before its Duel Rank gate"
					% [stage_id, String(source_type), String(source_id)]
				)
			cumulative_sources.append({
				"source_type": String(source_type),
				"source_id": String(source_id),
			})

		var cumulative_cards: Dictionary = {}
		var route_duplicates := PackedStringArray()
		for raw_ref in cumulative_sources:
			var source: Dictionary = world_catalog.call(
				"get_source_snapshot",
				StringName(str(raw_ref.get("source_type", ""))),
				StringName(str(raw_ref.get("source_id", "")))
			)
			for raw_card_id in source.get("card_ids", PackedStringArray()):
				var card_id: String = str(raw_card_id)
				if cumulative_cards.has(card_id):
					if not route_duplicates.has(card_id):
						route_duplicates.append(card_id)
					continue
				cumulative_cards[card_id] = true

		if bool(_root.get("exclusive_primary_routes", false)):
			for card_id in route_duplicates:
				errors.append(
					"%s primary route duplicates card %s"
					% [stage_id, card_id]
				)

		if cumulative_cards.size() != expected_pool:
			errors.append(
				"%s cumulative pool is %d, expected %d"
				% [stage_id, cumulative_cards.size(), expected_pool]
			)
		if target_max > expected_pool:
			errors.append(
				"%s target ownership exceeds available pool" % stage_id
			)

		for card_id in cumulative_cards.keys():
			if card_catalog != null and card_catalog.has_method("get_card_by_id"):
				if card_catalog.call("get_card_by_id", StringName(card_id)) == null:
					errors.append("%s references unknown card %s" % [stage_id, card_id])
			if seen_primary_cards.has(card_id):
				continue
			seen_primary_cards[card_id] = stage_id

		stage_results.append({
			"stage_id": stage_id,
			"milestone_hour": milestone_hour,
			"duel_rank_floor": rank_floor,
			"target_owned_min": target_min,
			"target_owned_max": target_max,
			"cumulative_pool": cumulative_cards.size(),
			"source_count": cumulative_sources.size(),
		})

	return _result(errors, warnings, stage_results)


func _load_data() -> void:
	_root.clear()
	_stages.clear()
	_load_errors.clear()
	if not FileAccess.file_exists(DATA_PATH):
		_load_errors.append("early acquisition progression plan is missing")
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		_load_errors.append("early acquisition progression plan could not be opened")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_load_errors.append("early acquisition progression plan root must be a Dictionary")
		return
	_root = (parsed as Dictionary).duplicate(true)
	if int(_root.get("schema_version", 0)) != SCHEMA_VERSION:
		_load_errors.append("unsupported early acquisition progression schema")
		return
	var raw_stages = _root.get("stages", [])
	if not (raw_stages is Array):
		_load_errors.append("early acquisition progression stages must be an Array")
		return
	for raw_stage in raw_stages:
		if raw_stage is Dictionary:
			_stages.append((raw_stage as Dictionary).duplicate(true))
		else:
			_load_errors.append("early acquisition progression contains invalid stage")


func _result(
	errors: PackedStringArray,
	warnings: PackedStringArray,
	stages: Array
) -> Dictionary:
	return {
		"valid": errors.is_empty(),
		"plan_id": String(get_plan_id()),
		"errors": errors,
		"warnings": warnings,
		"stages": stages,
		"stage_count": stages.size(),
	}
