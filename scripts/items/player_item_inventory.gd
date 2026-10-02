extends Node
class_name PlayerItemInventory

signal changed(snapshot: Dictionary)
signal item_count_changed(item_id: StringName, count: int)

const SAVE_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://player_item_inventory.json"

var _counts: Dictionary = {}
var _metadata: Dictionary = {}
var _save_path: String = DEFAULT_SAVE_PATH
var _initialized: bool = false
var _dirty: bool = false


func configure(save_path: String = "") -> void:
	if not save_path.strip_edges().is_empty():
		_save_path = save_path.strip_edges()


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	load_from_disk()


func get_save_path() -> String:
	return _save_path


func get_count(item_id: StringName) -> int:
	return maxi(0, int(_counts.get(String(item_id), 0)))


func has(item_id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return get_count(item_id) >= amount


func grant(
	item_id: StringName,
	amount: int = 1,
	persist: bool = true
) -> int:
	var clean_id: String = String(item_id).strip_edges()
	if clean_id.is_empty() or amount <= 0:
		return get_count(item_id)
	var next_count: int = get_count(StringName(clean_id)) + amount
	_set_count_internal(StringName(clean_id), next_count)
	if persist:
		commit_changes()
	return next_count


func remove(
	item_id: StringName,
	amount: int = 1,
	persist: bool = true
) -> bool:
	var clean_id: String = String(item_id).strip_edges()
	if clean_id.is_empty() or amount <= 0:
		return amount <= 0
	var current: int = get_count(StringName(clean_id))
	if current < amount:
		return false
	_set_count_internal(StringName(clean_id), current - amount)
	if persist:
		commit_changes()
	return true


func ensure_minimum_count(
	item_id: StringName,
	minimum_count: int,
	persist: bool = true
) -> int:
	var target: int = maxi(0, minimum_count)
	var current: int = get_count(item_id)
	if current >= target:
		return current
	_set_count_internal(item_id, target)
	if persist:
		commit_changes()
	return target


func can_afford(costs: Dictionary) -> bool:
	for raw_id in costs.keys():
		var required: int = maxi(0, int(costs[raw_id]))
		if get_count(StringName(str(raw_id))) < required:
			return false
	return true


func consume_costs(
	costs: Dictionary,
	persist: bool = true
) -> Dictionary:
	var result := {
		"success": false,
		"missing": {},
		"consumed": {},
	}
	var missing: Dictionary = {}
	for raw_id in costs.keys():
		var item_id := StringName(str(raw_id))
		var required: int = maxi(0, int(costs[raw_id]))
		var available: int = get_count(item_id)
		if available < required:
			missing[String(item_id)] = required - available
	if not missing.is_empty():
		result["missing"] = missing
		return result

	for raw_id in costs.keys():
		var item_id := StringName(str(raw_id))
		var required: int = maxi(0, int(costs[raw_id]))
		if required <= 0:
			continue
		_set_count_internal(
			item_id,
			get_count(item_id) - required
		)
		result["consumed"][String(item_id)] = required

	result["success"] = true
	if persist and not commit_changes():
		result["success"] = false
		result["reason"] = "save_failed"
	return result


func get_all_counts() -> Dictionary:
	return _counts.duplicate(true)


func get_metadata(key: String, fallback = null):
	return _metadata.get(key, fallback)


func set_metadata(
	key: String,
	value,
	persist: bool = true
) -> void:
	var clean_key: String = key.strip_edges()
	if clean_key.is_empty():
		return
	_metadata[clean_key] = value
	_dirty = true
	if persist:
		commit_changes()


func get_snapshot() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"counts": _counts.duplicate(true),
		"metadata": _metadata.duplicate(true),
		"save_path": _save_path,
	}


func create_transaction_snapshot() -> Dictionary:
	return {
		"counts": _counts.duplicate(true),
		"metadata": _metadata.duplicate(true),
		"dirty": _dirty,
	}


func restore_transaction_snapshot(
	snapshot: Dictionary,
	persist: bool = false
) -> void:
	var raw_counts = snapshot.get("counts", {})
	var raw_metadata = snapshot.get("metadata", {})
	_counts = (
		(raw_counts as Dictionary).duplicate(true)
		if raw_counts is Dictionary
		else {}
	)
	_metadata = (
		(raw_metadata as Dictionary).duplicate(true)
		if raw_metadata is Dictionary
		else {}
	)
	_dirty = bool(snapshot.get("dirty", true))
	changed.emit(get_snapshot())
	if persist:
		commit_changes()


func reset_all(
	persist: bool = true,
	keep_metadata: bool = true
) -> void:
	var old_ids: Array = _counts.keys()
	_counts.clear()
	if not keep_metadata:
		_metadata.clear()
	_dirty = true
	for raw_id in old_ids:
		item_count_changed.emit(StringName(str(raw_id)), 0)
	changed.emit(get_snapshot())
	if persist:
		commit_changes()


func commit_changes() -> bool:
	if not _dirty:
		return true
	return save_to_disk()


func save_to_disk() -> bool:
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	if file == null:
		push_warning("PlayerItemInventory: could not open save for writing.")
		return false
	file.store_string(
		JSON.stringify(
			{
				"version": SAVE_VERSION,
				"counts": _counts,
				"metadata": _metadata,
			},
			"\t"
		)
	)
	file.close()
	_dirty = false
	return true


func load_from_disk() -> bool:
	_counts.clear()
	_metadata.clear()
	_dirty = false
	if not FileAccess.file_exists(_save_path):
		return true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	if not (parsed is Dictionary):
		push_warning("PlayerItemInventory: save is invalid; using empty inventory.")
		return false
	var data: Dictionary = parsed
	var raw_counts = data.get("counts", {})
	if raw_counts is Dictionary:
		for raw_id in raw_counts.keys():
			var clean_id: String = str(raw_id).strip_edges()
			var amount: int = maxi(0, int(raw_counts[raw_id]))
			if not clean_id.is_empty() and amount > 0:
				_counts[clean_id] = amount
	var raw_metadata = data.get("metadata", {})
	if raw_metadata is Dictionary:
		_metadata = (raw_metadata as Dictionary).duplicate(true)
	return true


func _set_count_internal(
	item_id: StringName,
	count: int
) -> void:
	var clean_id: String = String(item_id).strip_edges()
	if clean_id.is_empty():
		return
	var clean_count: int = maxi(0, count)
	if clean_count <= 0:
		_counts.erase(clean_id)
	else:
		_counts[clean_id] = clean_count
	_dirty = true
	item_count_changed.emit(StringName(clean_id), clean_count)
	changed.emit(get_snapshot())
