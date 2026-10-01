extends Node
class_name BeachGatheringInventory

signal changed(snapshot: Dictionary)
signal material_changed(material_id: StringName, count: int)

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://beach_gathering_inventory.json"

var _counts: Dictionary = {}
var _initialized: bool = false


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	load_from_disk()


func get_count(material_id: StringName) -> int:
	return maxi(0, int(_counts.get(String(material_id), 0)))


func has(material_id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return get_count(material_id) >= amount


func grant(
	material_id: StringName,
	amount: int = 1,
	persist: bool = true
) -> int:
	var clean_id: String = String(material_id).strip_edges()
	if clean_id.is_empty() or amount <= 0:
		return get_count(material_id)

	var next_count: int = get_count(material_id) + amount
	_counts[clean_id] = next_count
	material_changed.emit(StringName(clean_id), next_count)
	changed.emit(get_snapshot())
	if persist:
		save_to_disk()
	return next_count


func remove(
	material_id: StringName,
	amount: int = 1,
	persist: bool = true
) -> bool:
	var clean_id: String = String(material_id).strip_edges()
	if clean_id.is_empty() or amount <= 0:
		return amount <= 0

	var current: int = get_count(StringName(clean_id))
	if current < amount:
		return false

	var next_count: int = current - amount
	if next_count <= 0:
		_counts.erase(clean_id)
	else:
		_counts[clean_id] = next_count

	material_changed.emit(StringName(clean_id), next_count)
	changed.emit(get_snapshot())
	if persist:
		save_to_disk()
	return true


func can_afford(costs: Dictionary) -> bool:
	for raw_id in costs.keys():
		var material_id := StringName(str(raw_id))
		var required: int = maxi(0, int(costs[raw_id]))
		if get_count(material_id) < required:
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
		var material_id := StringName(str(raw_id))
		var required: int = maxi(0, int(costs[raw_id]))
		var available: int = get_count(material_id)
		if available < required:
			missing[String(material_id)] = required - available

	if not missing.is_empty():
		result["missing"] = missing
		return result

	for raw_id in costs.keys():
		var material_id := StringName(str(raw_id))
		var required: int = maxi(0, int(costs[raw_id]))
		if required <= 0:
			continue
		remove(material_id, required, false)
		result["consumed"][String(material_id)] = required

	result["success"] = true
	if persist:
		save_to_disk()
	return result


func get_snapshot() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"counts": _counts.duplicate(true),
	}


func reset_all(persist: bool = true) -> void:
	_counts.clear()
	changed.emit(get_snapshot())
	if persist:
		save_to_disk()


func save_to_disk() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("BeachGatheringInventory: could not open save for writing.")
		return false
	file.store_string(
		JSON.stringify(
			{
				"version": SAVE_VERSION,
				"counts": _counts,
			},
			"\t"
		)
	)
	file.close()
	return true


func load_from_disk() -> bool:
	_counts.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return true

	var parsed = JSON.parse_string(
		FileAccess.get_file_as_string(SAVE_PATH)
	)
	if not (parsed is Dictionary):
		push_warning("BeachGatheringInventory: save is invalid; using empty inventory.")
		return false

	var data: Dictionary = parsed
	var raw_counts = data.get("counts", {})
	if raw_counts is Dictionary:
		for raw_id in raw_counts.keys():
			var clean_id: String = str(raw_id).strip_edges()
			var amount: int = maxi(0, int(raw_counts[raw_id]))
			if not clean_id.is_empty() and amount > 0:
				_counts[clean_id] = amount
	return true
