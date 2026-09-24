extends Node
class_name FishingInventory

signal changed
signal fish_count_changed(species_id: String, count: int)
signal lure_count_changed(lure_id: StringName, count: int)
signal rod_count_changed(rod_id: StringName, count: int)

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://fishing_inventory.json"

# Backend defaults only. These are the current starter loadout and are kept
# here rather than inferred from the active scene so QA/test scenes cannot
# accidentally grant special equipment permanently.
const STARTER_LURE_ID: StringName = &"straight"
const STARTER_ROD_ID: StringName = &"wooden_rod"

var fish_counts: Dictionary = {}
var lure_counts: Dictionary = {}
var rod_counts: Dictionary = {}

var _initialized: bool = false
var _progress_migrated: bool = false
var _bound_progress: FishingProgress = null
var _dirty: bool = false


func _ready() -> void:
	initialize()


func initialize() -> void:
	if _initialized:
		return

	_initialized = true
	load_from_disk()
	_seed_starter_tackle()


func bind_progress(progress: FishingProgress) -> void:
	initialize()

	if _bound_progress == progress:
		return

	if is_instance_valid(_bound_progress):
		var old_callback := Callable(self, "_on_progress_catch_recorded")
		if _bound_progress.catch_recorded.is_connected(old_callback):
			_bound_progress.catch_recorded.disconnect(old_callback)

	_bound_progress = progress

	if not is_instance_valid(_bound_progress):
		return

	# Inventory did not exist in earlier builds. On the first migration only,
	# treat lifetime catches as still physically owned because there was no
	# trading/consumption system that could have spent them yet.
	if not _progress_migrated:
		_migrate_existing_catches(_bound_progress)
		_progress_migrated = true
		_dirty = true
		commit_changes()

	var callback := Callable(self, "_on_progress_catch_recorded")
	if not _bound_progress.catch_recorded.is_connected(callback):
		_bound_progress.catch_recorded.connect(callback)


func get_fish_count(species_id: String) -> int:
	return maxi(int(fish_counts.get(_normalize_id(species_id), 0)), 0)


func has_fish(species_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return get_fish_count(species_id) >= amount


func add_fish(species_id: String, amount: int = 1, persist: bool = true) -> int:
	var key := _normalize_id(species_id)
	if key.is_empty() or amount <= 0:
		return get_fish_count(key)

	var next_count := get_fish_count(key) + amount
	fish_counts[key] = next_count
	_dirty = true
	fish_count_changed.emit(key, next_count)
	changed.emit()

	if persist:
		commit_changes()

	return next_count


func remove_fish(species_id: String, amount: int = 1, persist: bool = true) -> bool:
	var key := _normalize_id(species_id)
	if key.is_empty() or amount <= 0:
		return amount <= 0

	var current := get_fish_count(key)
	if current < amount:
		return false

	var next_count := current - amount
	if next_count <= 0:
		fish_counts.erase(key)
	else:
		fish_counts[key] = next_count

	_dirty = true
	fish_count_changed.emit(key, next_count)
	changed.emit()

	if persist:
		commit_changes()

	return true


func can_afford_fish_costs(
	species_ids: PackedStringArray,
	counts: PackedInt32Array
) -> bool:
	if species_ids.size() != counts.size():
		return false

	for index in range(species_ids.size()):
		var amount := maxi(int(counts[index]), 0)
		if not has_fish(str(species_ids[index]), amount):
			return false

	return true


func try_consume_fish_costs(
	species_ids: PackedStringArray,
	counts: PackedInt32Array,
	persist: bool = true
) -> bool:
	if not can_afford_fish_costs(species_ids, counts):
		return false

	var changed_keys: Dictionary = {}

	# Validate first, then mutate as one in-memory transaction. No callbacks fire
	# until every cost has been applied, so trade observers cannot interrupt a
	# partially-consumed recipe.
	for index in range(species_ids.size()):
		var key := _normalize_id(str(species_ids[index]))
		var amount := maxi(int(counts[index]), 0)
		if amount <= 0:
			continue

		var next_count := get_fish_count(key) - amount
		if next_count <= 0:
			fish_counts.erase(key)
		else:
			fish_counts[key] = next_count
		changed_keys[key] = next_count

	if changed_keys.is_empty():
		return true

	_dirty = true
	for key in changed_keys.keys():
		fish_count_changed.emit(str(key), int(changed_keys[key]))
	changed.emit()

	if persist:
		commit_changes()

	return true


func get_missing_fish_costs(
	species_ids: PackedStringArray,
	counts: PackedInt32Array
) -> Dictionary:
	var missing: Dictionary = {}
	if species_ids.size() != counts.size():
		missing["__invalid_recipe__"] = 1
		return missing

	for index in range(species_ids.size()):
		var key := _normalize_id(str(species_ids[index]))
		var required := maxi(int(counts[index]), 0)
		var have := get_fish_count(key)
		if have < required:
			missing[key] = required - have

	return missing


func get_all_fish_counts() -> Dictionary:
	return fish_counts.duplicate(true)


func get_lure_count(lure_id: StringName) -> int:
	return maxi(int(lure_counts.get(str(lure_id), 0)), 0)


func owns_lure(lure_or_id) -> bool:
	return get_lure_count(_get_lure_id(lure_or_id)) > 0


func grant_lure(lure_or_id, amount: int = 1, persist: bool = true) -> int:
	var lure_id := _get_lure_id(lure_or_id)
	if lure_id == &"" or amount <= 0:
		return get_lure_count(lure_id)

	var key := str(lure_id)
	var next_count := get_lure_count(lure_id) + amount
	lure_counts[key] = next_count
	_dirty = true
	lure_count_changed.emit(lure_id, next_count)
	changed.emit()

	if persist:
		commit_changes()

	return next_count


func remove_lure(lure_or_id, amount: int = 1, persist: bool = true) -> bool:
	var lure_id := _get_lure_id(lure_or_id)
	if lure_id == &"" or amount <= 0:
		return amount <= 0

	var current := get_lure_count(lure_id)
	if current < amount:
		return false

	var key := str(lure_id)
	var next_count := current - amount
	if next_count <= 0:
		lure_counts.erase(key)
	else:
		lure_counts[key] = next_count

	_dirty = true
	lure_count_changed.emit(lure_id, next_count)
	changed.emit()

	if persist:
		commit_changes()

	return true


func get_rod_count(rod_id: StringName) -> int:
	return maxi(int(rod_counts.get(str(rod_id), 0)), 0)


func owns_rod(rod_or_id) -> bool:
	return get_rod_count(_get_rod_id(rod_or_id)) > 0


func grant_rod(rod_or_id, amount: int = 1, persist: bool = true) -> int:
	var rod_id := _get_rod_id(rod_or_id)
	if rod_id == &"" or amount <= 0:
		return get_rod_count(rod_id)

	var key := str(rod_id)
	var next_count := get_rod_count(rod_id) + amount
	rod_counts[key] = next_count
	_dirty = true
	rod_count_changed.emit(rod_id, next_count)
	changed.emit()

	if persist:
		commit_changes()

	return next_count


func remove_rod(rod_or_id, amount: int = 1, persist: bool = true) -> bool:
	var rod_id := _get_rod_id(rod_or_id)
	if rod_id == &"" or amount <= 0:
		return amount <= 0

	var current := get_rod_count(rod_id)
	if current < amount:
		return false

	var key := str(rod_id)
	var next_count := current - amount
	if next_count <= 0:
		rod_counts.erase(key)
	else:
		rod_counts[key] = next_count

	_dirty = true
	rod_count_changed.emit(rod_id, next_count)
	changed.emit()

	if persist:
		commit_changes()

	return true


func get_owned_lure_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for raw_id in lure_counts.keys():
		if int(lure_counts[raw_id]) > 0:
			ids.append(str(raw_id))
	ids.sort()
	return ids


func get_owned_rod_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for raw_id in rod_counts.keys():
		if int(rod_counts[raw_id]) > 0:
			ids.append(str(raw_id))
	ids.sort()
	return ids


func commit_changes() -> bool:
	if not _dirty:
		return true

	var saved := save_to_disk()
	if saved:
		_dirty = false
	return saved


func save_to_disk() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"progress_migrated": _progress_migrated,
		"fish_counts": fish_counts,
		"lure_counts": lure_counts,
		"rod_counts": rod_counts,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("FishingInventory: could not open save file for writing.")
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func load_from_disk() -> bool:
	_reset_runtime_state()

	if not FileAccess.file_exists(SAVE_PATH):
		return true

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("FishingInventory: could not open save file for reading.")
		return false

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if not (parsed is Dictionary):
		push_warning("FishingInventory: invalid save; starting with an empty inventory.")
		return false

	var data: Dictionary = parsed
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("FishingInventory: save version is newer than this build.")
		return false

	_progress_migrated = bool(data.get("progress_migrated", false))
	fish_counts = _sanitize_count_dictionary(data.get("fish_counts", {}))
	lure_counts = _sanitize_count_dictionary(data.get("lure_counts", {}))
	rod_counts = _sanitize_count_dictionary(data.get("rod_counts", {}))
	_dirty = false
	changed.emit()
	return true


func reset_inventory(delete_save: bool = true) -> void:
	_reset_runtime_state()
	# Resetting the physical inventory must not immediately recreate all lifetime
	# catches from FishingProgress. Migration is only for the one-time upgrade from
	# pre-inventory builds.
	_progress_migrated = true
	lure_counts[str(STARTER_LURE_ID)] = 1
	rod_counts[str(STARTER_ROD_ID)] = 1

	if delete_save and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	_dirty = true
	commit_changes()
	changed.emit()


func _on_progress_catch_recorded(
	species_id: String,
	_record: Dictionary,
	_fishing_points: int
) -> void:
	add_fish(species_id, 1, true)


func _migrate_existing_catches(progress: FishingProgress) -> void:
	if progress == null:
		return

	for raw_id in progress.get_all_records().keys():
		var species_id := _normalize_id(str(raw_id))
		var record := progress.get_species_record_by_key(species_id)
		var caught_count := maxi(int(record.get("caught_count", 0)), 0)
		if caught_count > 0:
			fish_counts[species_id] = maxi(
				get_fish_count(species_id),
				caught_count
			)


func _seed_starter_tackle() -> void:
	var changed_starter := false
	if get_lure_count(STARTER_LURE_ID) <= 0:
		lure_counts[str(STARTER_LURE_ID)] = 1
		changed_starter = true
	if get_rod_count(STARTER_ROD_ID) <= 0:
		rod_counts[str(STARTER_ROD_ID)] = 1
		changed_starter = true

	if changed_starter:
		_dirty = true
		commit_changes()


func _sanitize_count_dictionary(value) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		return result

	for raw_key in (value as Dictionary).keys():
		var key := _normalize_id(str(raw_key))
		var count := maxi(int((value as Dictionary)[raw_key]), 0)
		if not key.is_empty() and count > 0:
			result[key] = count

	return result


func _get_lure_id(lure_or_id) -> StringName:
	if lure_or_id == null:
		return &""
	if lure_or_id is BaitData:
		return (lure_or_id as BaitData).lure_id
	return StringName(_normalize_id(str(lure_or_id)))


func _get_rod_id(rod_or_id) -> StringName:
	if rod_or_id == null:
		return &""
	if rod_or_id is RodData:
		return (rod_or_id as RodData).rod_id
	return StringName(_normalize_id(str(rod_or_id)))


func _normalize_id(value: String) -> String:
	return value.strip_edges().to_lower().replace(" ", "_").replace("-", "_").replace("'", "")


func _reset_runtime_state() -> void:
	fish_counts.clear()
	lure_counts.clear()
	rod_counts.clear()
	_progress_migrated = false
	_dirty = false
