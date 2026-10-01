extends RefCounted
class_name TripleTriadWorldAcquisitionCatalog

const DATA_PATH := "res://data/triple_triad/acquisition/world_acquisition_map.json"
const SCHEMA_VERSION := 1

var _card_catalog: Resource = null
var _opponent_registry: Resource = null
var _acquisition_registry: Resource = null
var _sources: Array = []
var _source_by_key: Dictionary = {}
var _sources_by_card: Dictionary = {}
var _direct_claim_types: Dictionary = {}
var _load_errors: PackedStringArray = PackedStringArray()


func initialize(
	card_catalog: Resource,
	opponent_registry: Resource,
	acquisition_registry: Resource
) -> void:
	_card_catalog = card_catalog
	_opponent_registry = opponent_registry
	_acquisition_registry = acquisition_registry
	_load_data()


func get_all_source_snapshots() -> Array:
	return _sources.duplicate(true)


func get_source_snapshot(source_type: StringName, source_id: StringName) -> Dictionary:
	var key: String = _source_key(source_type, source_id)
	if not _source_by_key.has(key):
		return {}
	var snapshot: Dictionary = _source_by_key[key]
	return snapshot.duplicate(true)


func get_sources_for_card(card_id: StringName) -> Array:
	var key: String = String(card_id)
	if not _sources_by_card.has(key):
		return []
	var result: Array = []
	for source_key in _sources_by_card[key]:
		if _source_by_key.has(source_key):
			var snapshot: Dictionary = _source_by_key[source_key]
			result.append(snapshot.duplicate(true))
	return result


func get_cards_for_source(
	source_type: StringName,
	source_id: StringName,
	player_rank: int = 10
) -> Array:
	var source: Dictionary = get_source_snapshot(source_type, source_id)
	if source.is_empty():
		return []
	if maxi(1, player_rank) < int(source.get("min_duel_rank", 1)):
		return []
	var result: Array = []
	for raw_id in source.get("card_ids", PackedStringArray()):
		var card = null
		if _card_catalog != null and _card_catalog.has_method("get_card_by_id"):
			card = _card_catalog.call("get_card_by_id", StringName(str(raw_id)))
		if card != null:
			result.append(card)
	return result


func can_direct_claim_source(source_type: StringName) -> bool:
	return bool(_direct_claim_types.get(String(source_type), false))


func validate_claim(
	source_type: StringName,
	source_id: StringName,
	card_id: StringName,
	player_rank: int
) -> Dictionary:
	var source: Dictionary = get_source_snapshot(source_type, source_id)
	if source.is_empty():
		return {"valid": false, "reason": "unknown_source"}
	if not can_direct_claim_source(source_type):
		return {"valid": false, "reason": "source_owned_by_other_system"}
	if maxi(1, player_rank) < int(source.get("min_duel_rank", 1)):
		return {
			"valid": false,
			"reason": "duel_rank_too_low",
			"required_duel_rank": int(source.get("min_duel_rank", 1)),
		}
	var wanted: String = String(card_id)
	var found: bool = false
	for raw_id in source.get("card_ids", PackedStringArray()):
		if str(raw_id) == wanted:
			found = true
			break
	if not found:
		return {"valid": false, "reason": "card_not_in_source"}
	return {"valid": true, "reason": "ok", "source": source}


func validate_map() -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	for load_error in _load_errors:
		errors.append(load_error)

	var catalog_ids: Dictionary = {}
	if _card_catalog != null and _card_catalog.has_method("get_total_source_count"):
		for index in range(int(_card_catalog.call("get_total_source_count"))):
			var card = _card_catalog.call("get_card", index)
			if card != null:
				catalog_ids[String(card.card_id)] = true

	for source in _sources:
		var source_type: String = str(source.get("source_type", ""))
		var source_id: String = str(source.get("source_id", ""))
		var source_key: String = _source_key(StringName(source_type), StringName(source_id))
		if source_type.is_empty() or source_id.is_empty():
			errors.append("acquisition source has an empty type/id")
			continue
		var seen_cards: Dictionary = {}
		for raw_id in source.get("card_ids", PackedStringArray()):
			var card_id: String = str(raw_id)
			if seen_cards.has(card_id):
				errors.append("%s duplicates card %s" % [source_key, card_id])
			continue
			seen_cards[card_id] = true
			if not catalog_ids.has(card_id):
				errors.append("%s references unknown card %s" % [source_key, card_id])

		if source_type == "starter_bundle":
			_validate_bundle_contract(source, errors)
		elif source_type == "opponent_win":
			_validate_opponent_contract(source, errors)

	for card_id in catalog_ids.keys():
		if not _sources_by_card.has(card_id):
			errors.append("card %s has no acquisition source" % card_id)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"card_count": catalog_ids.size(),
		"covered_card_count": _sources_by_card.size(),
		"source_count": _sources.size(),
		"source_type_counts": _source_type_counts(),
	}


func _load_data() -> void:
	_sources.clear()
	_source_by_key.clear()
	_sources_by_card.clear()
	_direct_claim_types.clear()
	_load_errors.clear()

	if not FileAccess.file_exists(DATA_PATH):
		_load_errors.append("world acquisition map file is missing")
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		_load_errors.append("world acquisition map could not be opened")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_load_errors.append("world acquisition map root must be a Dictionary")
		return
	var root: Dictionary = parsed
	if int(root.get("schema_version", 0)) != SCHEMA_VERSION:
		_load_errors.append("unsupported world acquisition map schema")
		return

	var raw_direct = root.get("source_types_direct_claim", [])
	if raw_direct is Array:
		for raw_type in raw_direct:
			var type_name: String = str(raw_type).strip_edges()
			if not type_name.is_empty():
				_direct_claim_types[type_name] = true

	var raw_sources = root.get("sources", [])
	if not (raw_sources is Array):
		_load_errors.append("world acquisition map sources must be an Array")
		return
	for raw_source in raw_sources:
		if not (raw_source is Dictionary):
			_load_errors.append("world acquisition map contains a non-Dictionary source")
			continue
		var source: Dictionary = (raw_source as Dictionary).duplicate(true)
		var source_type: String = str(source.get("source_type", "")).strip_edges()
		var source_id: String = str(source.get("source_id", "")).strip_edges()
		var key: String = _source_key(StringName(source_type), StringName(source_id))
		if source_type.is_empty() or source_id.is_empty():
			_load_errors.append("world acquisition source has empty type/id")
			continue
		if _source_by_key.has(key):
			_load_errors.append("duplicate world acquisition source: %s" % key)
			continue
		var packed_ids := PackedStringArray()
		var raw_ids = source.get("card_ids", [])
		if raw_ids is Array:
			for raw_id in raw_ids:
				var card_id: String = str(raw_id).strip_edges()
				if not card_id.is_empty():
					packed_ids.append(card_id)
		source["card_ids"] = packed_ids
		source["min_duel_rank"] = maxi(1, int(source.get("min_duel_rank", 1)))
		_sources.append(source)
		_source_by_key[key] = source
		for card_id in packed_ids:
			if not _sources_by_card.has(card_id):
				_sources_by_card[card_id] = []
			var source_keys: Array = _sources_by_card[card_id]
			source_keys.append(key)
			_sources_by_card[card_id] = source_keys


func _validate_bundle_contract(source: Dictionary, errors: PackedStringArray) -> void:
	if _acquisition_registry == null or not _acquisition_registry.has_method("get_bundle"):
		errors.append("starter bundle source cannot validate acquisition registry")
		return
	var bundle_id := StringName(str(source.get("source_id", "")))
	var bundle = _acquisition_registry.call("get_bundle", bundle_id)
	if bundle == null:
		errors.append("starter source references unknown bundle %s" % String(bundle_id))
		return
	if not _same_string_set(source.get("card_ids", []), bundle.get("card_ids")):
		errors.append("starter source %s does not match bundle card_ids" % String(bundle_id))


func _validate_opponent_contract(source: Dictionary, errors: PackedStringArray) -> void:
	if _opponent_registry == null or not _opponent_registry.has_method("get_opponent"):
		errors.append("opponent source cannot validate opponent registry")
		return
	var opponent_id := StringName(str(source.get("source_id", "")))
	var profile = _opponent_registry.call("get_opponent", opponent_id)
	if profile == null:
		errors.append("opponent source references unknown opponent %s" % String(opponent_id))
		return
	if not _same_string_set(source.get("card_ids", []), profile.get("reward_card_ids")):
		errors.append("opponent source %s does not match reward_card_ids" % String(opponent_id))


func _same_string_set(a, b) -> bool:
	var left: Dictionary = {}
	var right: Dictionary = {}
	if a is PackedStringArray or a is Array:
		for raw_value in a:
			left[str(raw_value)] = true
	if b is PackedStringArray or b is Array:
		for raw_value in b:
			right[str(raw_value)] = true
	if left.size() != right.size():
		return false
	for key in left.keys():
		if not right.has(key):
			return false
	return true


func _source_type_counts() -> Dictionary:
	var counts: Dictionary = {}
	for source in _sources:
		var source_type: String = str(source.get("source_type", ""))
		counts[source_type] = int(counts.get(source_type, 0)) + 1
	return counts


func _source_key(source_type: StringName, source_id: StringName) -> String:
	return "%s:%s" % [String(source_type), String(source_id)]
