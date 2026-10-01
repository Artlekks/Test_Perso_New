extends RefCounted
class_name TripleTriadAcquisitionService

signal bundle_claimed(result: Dictionary)
signal unlock_changed(unlocked: bool)

const SAVE_PATH := "user://triple_triad_acquisition_state.cfg"
const SAVE_VERSION := 1

var _catalog: Resource = null
var _collection = null
var _tracker = null
var _registry: Resource = null
var _claimed: Dictionary = {}
var _card_game_unlocked: bool = false


func initialize(
	catalog: Resource,
	collection,
	tracker,
	registry: Resource
) -> void:
	_catalog = catalog
	_collection = collection
	_tracker = tracker
	_registry = registry
	_claimed.clear()
	_card_game_unlocked = false

	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)
	var had_save: bool = load_error == OK
	if had_save:
		_load_from_config(config)
	elif load_error != ERR_FILE_NOT_FOUND:
		push_warning(
			"TripleTriadAcquisitionService: state could not be loaded (%s)."
			% error_string(load_error)
		)

	if not had_save:
		_migrate_legacy_collection()
	_sanitize_claimed_ids()
	_save()


func claim_bundle(
	bundle_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"reason": "",
		"bundle_id": String(bundle_id),
		"display_name": "",
		"source_type": "",
		"source_context": String(source_context),
		"unlocked_card_game": false,
		"cards": [],
		"new_unique_cards": 0,
		"granted_cards": 0,
	}
	if _registry == null or not _registry.has_method("get_bundle"):
		result["reason"] = "registry_unavailable"
		return result
	if _collection == null:
		result["reason"] = "collection_unavailable"
		return result

	var bundle = _registry.call("get_bundle", bundle_id)
	if bundle == null:
		result["reason"] = "unknown_bundle"
		return result
	result["display_name"] = str(bundle.get("display_name"))
	result["source_type"] = String(bundle.get("source_type"))

	if bool(bundle.get("one_shot")) and has_claimed_bundle(bundle_id):
		result["reason"] = "already_claimed"
		return result

	var card_results: Array = []
	var granted_cards: int = 0
	var new_unique_cards: int = 0
	var raw_ids = bundle.get("card_ids")
	if not (raw_ids is PackedStringArray or raw_ids is Array):
		result["reason"] = "invalid_bundle"
		return result

	for raw_id in raw_ids:
		var card_id := StringName(str(raw_id))
		var card = null
		if _catalog != null and _catalog.has_method("get_card_by_id"):
			card = _catalog.call("get_card_by_id", card_id)
		if card == null:
			continue
		var before: int = 0
		if _collection.has_method("get_quantity_by_id"):
			before = int(_collection.call("get_quantity_by_id", card_id))
		var after: int = int(_collection.call("acquire_card", card, 1, false))
		if after > before:
			granted_cards += 1
			if before <= 0:
				new_unique_cards += 1
			if _tracker != null and _tracker.has_method("record_acquisition"):
				_tracker.call(
					"record_acquisition",
					card,
					StringName(str(bundle.get("source_type"))),
					source_context,
					1
				)
		card_results.append({
			"card_id": String(card_id),
			"display_name": str(card.get("display_name")),
			"quantity_before": before,
			"quantity_after": after,
		})

	if _collection.has_method("save_state"):
		_collection.call("save_state")

	_claimed[String(bundle_id)] = true
	var was_unlocked: bool = _card_game_unlocked
	if bool(bundle.get("unlocks_card_game")):
		_card_game_unlocked = true
	_save()

	result["success"] = true
	result["reason"] = "ok"
	result["cards"] = card_results
	result["granted_cards"] = granted_cards
	result["new_unique_cards"] = new_unique_cards
	result["unlocked_card_game"] = not was_unlocked and _card_game_unlocked
	bundle_claimed.emit(result.duplicate(true))
	if not was_unlocked and _card_game_unlocked:
		unlock_changed.emit(true)
	return result


func grant_card(
	card_id: StringName,
	source_type: StringName,
	source_context: StringName = &"",
	amount: int = 1
) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"reason": "",
		"card_id": String(card_id),
		"source_type": String(source_type),
		"source_context": String(source_context),
		"amount_requested": maxi(1, amount),
		"quantity_before": 0,
		"quantity_after": 0,
	}
	if _collection == null:
		result["reason"] = "collection_unavailable"
		return result
	if _catalog == null or not _catalog.has_method("get_card_by_id"):
		result["reason"] = "catalog_unavailable"
		return result
	var card = _catalog.call("get_card_by_id", card_id)
	if card == null:
		result["reason"] = "unknown_card"
		return result
	var before: int = 0
	if _collection.has_method("get_quantity_by_id"):
		before = int(_collection.call("get_quantity_by_id", card_id))
	var after: int = before
	for _index in range(maxi(1, amount)):
		after = int(_collection.call("acquire_card", card, 1, false))
	if _collection.has_method("save_state"):
		_collection.call("save_state")
	if after > before and _tracker != null and _tracker.has_method("record_acquisition"):
		_tracker.call(
			"record_acquisition",
			card,
			source_type,
			source_context,
			after - before
		)
	result["success"] = after > before
	result["reason"] = "ok" if after > before else "not_granted"
	result["quantity_before"] = before
	result["quantity_after"] = after
	result["granted"] = maxi(0, after - before)
	result["display_name"] = str(card.get("display_name"))
	return result


func is_card_game_unlocked() -> bool:
	return _card_game_unlocked


func has_claimed_bundle(bundle_id: StringName) -> bool:
	return bool(_claimed.get(String(bundle_id), false))


func get_snapshot() -> Dictionary:
	var claimed_ids := PackedStringArray()
	for raw_id in _claimed.keys():
		if bool(_claimed[raw_id]):
			claimed_ids.append(str(raw_id))
	claimed_ids.sort()

	var available_ids := PackedStringArray()
	if _registry != null and _registry.has_method("get_all_bundles"):
		for bundle in _registry.call("get_all_bundles"):
			if bundle == null:
				continue
			var bundle_id := StringName(str(bundle.get("bundle_id")))
			if bool(bundle.get("one_shot")) and has_claimed_bundle(bundle_id):
				continue
			available_ids.append(String(bundle_id))
	return {
		"card_game_unlocked": _card_game_unlocked,
		"claimed_bundle_ids": claimed_ids,
		"available_bundle_ids": available_ids,
	}


func save_state() -> Error:
	return _save()


func _migrate_legacy_collection() -> void:
	var owned_count: int = 0
	if _collection != null and _collection.has_method("unique_owned_count"):
		owned_count = int(_collection.call("unique_owned_count"))
	if owned_count <= 0:
		return

	_card_game_unlocked = owned_count > 0
	if _registry == null or not _registry.has_method("get_all_bundles"):
		return
	for bundle in _registry.call("get_all_bundles"):
		if bundle == null:
			continue
		if bool(bundle.get("migration_claim_if_collection_nonempty")):
			_claimed[String(bundle.get("bundle_id"))] = true


func _sanitize_claimed_ids() -> void:
	if _registry == null or not _registry.has_method("get_bundle"):
		return
	var invalid: Array[String] = []
	for raw_id in _claimed.keys():
		var key: String = str(raw_id)
		if _registry.call("get_bundle", StringName(key)) == null:
			invalid.append(key)
	for key in invalid:
		_claimed.erase(key)


func _load_from_config(config: ConfigFile) -> void:
	_card_game_unlocked = bool(
		config.get_value("meta", "card_game_unlocked", false)
	)
	if config.has_section("claimed"):
		for raw_key in config.get_section_keys("claimed"):
			if bool(config.get_value("claimed", raw_key, false)):
				_claimed[str(raw_key)] = true


func _save() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("meta", "card_game_unlocked", _card_game_unlocked)
	for raw_id in _claimed.keys():
		if bool(_claimed[raw_id]):
			config.set_value("claimed", str(raw_id), true)
	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadAcquisitionService: state save failed (%s)."
			% error_string(save_error)
		)
	return save_error
