extends Node
class_name FishingInventory

signal changed
signal fish_count_changed(species_id: String, count: int)
signal fish_specimen_added(species_id: String, specimen: FishingFishSpecimen)
signal fish_specimen_removed(species_id: String, specimen: FishingFishSpecimen)
signal lure_count_changed(lure_id: StringName, count: int)
signal rod_count_changed(rod_id: StringName, count: int)

const SAVE_VERSION: int = 2
const SAVE_PATH: String = "user://fishing_inventory.json"

# Backend defaults only. These are the current starter loadout and are kept
# here rather than inferred from the active scene so QA/test scenes cannot
# accidentally grant special equipment permanently.
const STARTER_LURE_ID: StringName = &"straight"
const STARTER_ROD_ID: StringName = &"wooden_rod"

# species id -> Array[FishingFishSpecimen]
var fish_specimens: Dictionary = {}
var lure_counts: Dictionary = {}
var rod_counts: Dictionary = {}

var _initialized: bool = false
var _progress_migrated: bool = false
var _bound_progress: FishingProgress = null
var _dirty: bool = false
var _next_specimen_id: int = 1


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
		var old_callback := Callable(self, "_on_progress_catch_specimen_recorded")
		if _bound_progress.catch_specimen_recorded.is_connected(old_callback):
			_bound_progress.catch_specimen_recorded.disconnect(old_callback)

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
	else:
		# Pass 1 saved only species counts. Version-2 loading preserves those
		# counts as legacy specimens; use the permanent record to enrich the one
		# specimen whose historical best values are actually known.
		_enrich_legacy_specimens_from_progress(_bound_progress)

	commit_changes()

	var callback := Callable(self, "_on_progress_catch_specimen_recorded")
	if not _bound_progress.catch_specimen_recorded.is_connected(callback):
		_bound_progress.catch_specimen_recorded.connect(callback)


# -----------------------------------------------------------------------------
# Fish specimens
# -----------------------------------------------------------------------------

func get_fish_count(species_id: String) -> int:
	var key := _normalize_id(species_id)
	var specimens := _get_specimen_array(key)
	return specimens.size()


func has_fish(species_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return get_fish_count(species_id) >= amount


func get_fish_specimens(species_id: String) -> Array[FishingFishSpecimen]:
	var key := _normalize_id(species_id)
	var result: Array[FishingFishSpecimen] = []
	for value in _get_specimen_array(key):
		var specimen := value as FishingFishSpecimen
		if specimen != null:
			result.append(specimen.duplicate_specimen())
	return result


func get_all_fish_specimens() -> Dictionary:
	var result: Dictionary = {}
	for raw_key in fish_specimens.keys():
		var key := str(raw_key)
		var copies: Array[Dictionary] = []
		for value in _get_specimen_array(key):
			var specimen := value as FishingFishSpecimen
			if specimen != null:
				copies.append(specimen.to_dictionary())
		result[key] = copies
	return result


func get_fish_specimen(species_id: String, specimen_id: int) -> FishingFishSpecimen:
	var key := _normalize_id(species_id)
	for value in _get_specimen_array(key):
		var specimen := value as FishingFishSpecimen
		if specimen != null and specimen.specimen_id == specimen_id:
			return specimen.duplicate_specimen()
	return null


func add_fish_specimen(
	species_id: String,
	fish_name: String,
	size: float,
	points: int,
	is_king: bool,
	persist: bool = true,
	legacy: bool = false
) -> FishingFishSpecimen:
	var key := _normalize_id(species_id)
	if key.is_empty():
		return null

	var specimen := FishingFishSpecimen.new()
	specimen.specimen_id = _allocate_specimen_id()
	specimen.species_id = key
	specimen.fish_name = fish_name
	specimen.size = maxf(size, 0.0)
	specimen.points = maxi(points, 0)
	specimen.is_king = is_king
	specimen.legacy = legacy

	var specimens := _get_or_create_specimen_array(key)
	specimens.append(specimen)
	fish_specimens[key] = specimens

	_dirty = true
	fish_specimen_added.emit(key, specimen.duplicate_specimen())
	fish_count_changed.emit(key, specimens.size())
	changed.emit()

	if persist:
		commit_changes()

	return specimen.duplicate_specimen()


# Compatibility / debug helper. New real catches should use add_fish_specimen().
func add_fish(species_id: String, amount: int = 1, persist: bool = true) -> int:
	var key := _normalize_id(species_id)
	if key.is_empty() or amount <= 0:
		return get_fish_count(key)

	for _index in range(amount):
		_add_legacy_placeholder(key, "")

	_emit_species_count_changed(key)
	if persist:
		commit_changes()

	return get_fish_count(key)


func remove_fish_specimen(
	species_id: String,
	specimen_id: int,
	persist: bool = true
) -> bool:
	var key := _normalize_id(species_id)
	var specimens := _get_specimen_array(key)

	for index in range(specimens.size()):
		var specimen := specimens[index] as FishingFishSpecimen
		if specimen == null or specimen.specimen_id != specimen_id:
			continue

		var removed := specimen.duplicate_specimen()
		specimens.remove_at(index)
		_store_or_erase_specimen_array(key, specimens)
		_dirty = true
		fish_specimen_removed.emit(key, removed)
		fish_count_changed.emit(key, specimens.size())
		changed.emit()

		if persist:
			commit_changes()
		return true

	return false


# Compatibility helper used by count-based recipes. It deliberately consumes
# the least valuable-looking physical specimens first: legacy/unknown fish,
# then normal fish from smallest to largest, while Kings are preserved last.
func remove_fish(species_id: String, amount: int = 1, persist: bool = true) -> bool:
	var key := _normalize_id(species_id)
	if key.is_empty() or amount <= 0:
		return amount <= 0

	var selected := _select_auto_consume_specimens(key, amount)
	if selected.size() < amount:
		return false

	var selected_by_species: Dictionary = {}
	selected_by_species[key] = selected
	_remove_specimen_ids_transactional(selected_by_species)
	if persist:
		commit_changes()
	return true


func can_afford_fish_costs(
	species_ids: PackedStringArray,
	counts: PackedInt32Array
) -> bool:
	return bool(plan_fish_costs(species_ids, counts).get("can_afford", false))


func plan_fish_costs(
	species_ids: PackedStringArray,
	counts: PackedInt32Array
) -> Dictionary:
	var plan := {
		"can_afford": false,
		"missing_fish": {},
		"selected_specimens": {},
	}

	if species_ids.size() != counts.size():
		plan["missing_fish"] = {"__invalid_recipe__": 1}
		return plan

	# Aggregate duplicate species entries first so one physical specimen can
	# never accidentally satisfy two lines of the same recipe.
	var required_by_species: Dictionary = {}
	for index in range(species_ids.size()):
		var key := _normalize_id(str(species_ids[index]))
		var amount := maxi(int(counts[index]), 0)
		if key.is_empty() or amount <= 0:
			continue
		required_by_species[key] = int(required_by_species.get(key, 0)) + amount

	var selected_by_species: Dictionary = {}
	var missing: Dictionary = {}

	for raw_key in required_by_species.keys():
		var key := str(raw_key)
		var required := int(required_by_species[raw_key])
		var selected := _select_auto_consume_specimens(key, required)
		selected_by_species[key] = selected
		if selected.size() < required:
			missing[key] = required - selected.size()

	plan["selected_specimens"] = selected_by_species
	plan["missing_fish"] = missing
	plan["can_afford"] = missing.is_empty()
	return plan


func consume_fish_costs(
	species_ids: PackedStringArray,
	counts: PackedInt32Array,
	persist: bool = true
) -> Dictionary:
	var plan := plan_fish_costs(species_ids, counts)
	var result := {
		"success": false,
		"missing_fish": plan.get("missing_fish", {}),
		"consumed_specimens": {},
	}

	if not bool(plan.get("can_afford", false)):
		return result

	var selected: Dictionary = plan.get("selected_specimens", {})
	result["consumed_specimens"] = _remove_specimen_ids_transactional(selected)
	result["success"] = true

	if persist:
		commit_changes()

	return result


func try_consume_fish_costs(
	species_ids: PackedStringArray,
	counts: PackedInt32Array,
	persist: bool = true
) -> bool:
	return bool(
		consume_fish_costs(species_ids, counts, persist).get("success", false)
	)


func get_missing_fish_costs(
	species_ids: PackedStringArray,
	counts: PackedInt32Array
) -> Dictionary:
	var missing = plan_fish_costs(species_ids, counts).get("missing_fish", {})
	if missing is Dictionary:
		return (missing as Dictionary).duplicate(true)
	return {}


func get_all_fish_counts() -> Dictionary:
	var result: Dictionary = {}
	for raw_key in fish_specimens.keys():
		var key := str(raw_key)
		var count := get_fish_count(key)
		if count > 0:
			result[key] = count
	return result


func get_smallest_owned_specimen(species_id: String) -> FishingFishSpecimen:
	var selected := _select_auto_consume_specimens(_normalize_id(species_id), 1)
	if selected.is_empty():
		return null
	return get_fish_specimen(species_id, int(selected[0]))


func get_largest_owned_specimen(species_id: String) -> FishingFishSpecimen:
	var specimens := get_fish_specimens(species_id)
	if specimens.is_empty():
		return null

	specimens.sort_custom(Callable(self, "_sort_largest_specimen_first"))
	return specimens[0]


# -----------------------------------------------------------------------------
# Tackle stacks
# -----------------------------------------------------------------------------

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


# -----------------------------------------------------------------------------
# Persistence / migration
# -----------------------------------------------------------------------------

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
		"next_specimen_id": _next_specimen_id,
		"fish_specimens": _serialize_specimen_dictionary(),
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
	lure_counts = _sanitize_count_dictionary(data.get("lure_counts", {}))
	rod_counts = _sanitize_count_dictionary(data.get("rod_counts", {}))

	if version >= 2:
		fish_specimens = _sanitize_specimen_dictionary(data.get("fish_specimens", {}))
		_next_specimen_id = maxi(int(data.get("next_specimen_id", 1)), 1)
		_repair_next_specimen_id()
	else:
		# Version 1 stored only species counts. Preserve the exact physical count
		# without inventing historical sizes.
		var old_counts := _sanitize_count_dictionary(data.get("fish_counts", {}))
		for raw_key in old_counts.keys():
			var key := str(raw_key)
			for _index in range(int(old_counts[raw_key])):
				_add_legacy_placeholder(key, "")
		_dirty = true

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


func _on_progress_catch_specimen_recorded(
	species_id: String,
	catch_data: Dictionary
) -> void:
	add_fish_specimen(
		species_id,
		str(catch_data.get("fish_name", "")),
		float(catch_data.get("size", 0.0)),
		int(catch_data.get("points", 0)),
		bool(catch_data.get("is_king", false)),
		true,
		false
	)


func _migrate_existing_catches(progress: FishingProgress) -> void:
	if progress == null:
		return

	for raw_id in progress.get_all_records().keys():
		var species_id := _normalize_id(str(raw_id))
		var record := progress.get_species_record_by_key(species_id)
		var caught_count := maxi(int(record.get("caught_count", 0)), 0)
		if caught_count <= 0:
			continue

		for _index in range(caught_count):
			_add_legacy_placeholder(species_id, str(record.get("fish_name", "")))

	_enrich_legacy_specimens_from_progress(progress)


func _enrich_legacy_specimens_from_progress(progress: FishingProgress) -> void:
	if progress == null:
		return

	for raw_id in fish_specimens.keys():
		var species_id := str(raw_id)
		var record := progress.get_species_record_by_key(species_id)
		if record.is_empty():
			continue

		var specimens := _get_specimen_array(species_id)
		if specimens.is_empty():
			continue

		var best_size := maxf(float(record.get("best_size", 0.0)), 0.0)
		var best_points := maxi(int(record.get("best_points", 0)), 0)
		var king_caught := bool(record.get("king_caught", false))
		var fish_name := str(record.get("fish_name", ""))

		var candidate: FishingFishSpecimen = null
		for value in specimens:
			var specimen := value as FishingFishSpecimen
			if specimen == null or not specimen.legacy:
				continue
			if candidate == null or specimen.size > candidate.size:
				candidate = specimen

		if candidate == null:
			continue

		var changed_candidate := false
		if candidate.fish_name.is_empty() and not fish_name.is_empty():
			candidate.fish_name = fish_name
			changed_candidate = true
		if best_size > candidate.size:
			candidate.size = best_size
			changed_candidate = true
		if best_points > candidate.points:
			candidate.points = best_points
			changed_candidate = true
		if king_caught and not candidate.is_king:
			candidate.is_king = true
			changed_candidate = true

		if changed_candidate:
			_dirty = true


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


# -----------------------------------------------------------------------------
# Internal specimen helpers
# -----------------------------------------------------------------------------

func _allocate_specimen_id() -> int:
	var result := maxi(_next_specimen_id, 1)
	_next_specimen_id = result + 1
	return result


func _add_legacy_placeholder(species_id: String, fish_name: String) -> FishingFishSpecimen:
	var key := _normalize_id(species_id)
	if key.is_empty():
		return null

	var specimen := FishingFishSpecimen.new()
	specimen.specimen_id = _allocate_specimen_id()
	specimen.species_id = key
	specimen.fish_name = fish_name
	specimen.legacy = true

	var specimens := _get_or_create_specimen_array(key)
	specimens.append(specimen)
	fish_specimens[key] = specimens
	_dirty = true
	return specimen


func _get_specimen_array(species_id: String) -> Array:
	var key := _normalize_id(species_id)
	var value = fish_specimens.get(key, [])
	if value is Array:
		return value as Array
	return []


func _get_or_create_specimen_array(species_id: String) -> Array:
	var key := _normalize_id(species_id)
	var specimens := _get_specimen_array(key)
	if not fish_specimens.has(key):
		fish_specimens[key] = specimens
	return specimens


func _store_or_erase_specimen_array(species_id: String, specimens: Array) -> void:
	var key := _normalize_id(species_id)
	if specimens.is_empty():
		fish_specimens.erase(key)
	else:
		fish_specimens[key] = specimens


func _select_auto_consume_specimens(species_id: String, amount: int) -> PackedInt32Array:
	var key := _normalize_id(species_id)
	var copies: Array[FishingFishSpecimen] = []

	for value in _get_specimen_array(key):
		var specimen := value as FishingFishSpecimen
		if specimen != null:
			copies.append(specimen)

	copies.sort_custom(Callable(self, "_sort_auto_consume_specimen_first"))

	var result := PackedInt32Array()
	for index in range(mini(amount, copies.size())):
		result.append(copies[index].specimen_id)
	return result


func _sort_auto_consume_specimen_first(
	a: FishingFishSpecimen,
	b: FishingFishSpecimen
) -> bool:
	# Preserve King specimens unless a future recipe explicitly asks for one.
	if a.is_king != b.is_king:
		return not a.is_king and b.is_king
	# Unknown legacy specimens are safest to spend first.
	if a.legacy != b.legacy:
		return a.legacy and not b.legacy
	if not is_equal_approx(a.size, b.size):
		return a.size < b.size
	if a.points != b.points:
		return a.points < b.points
	return a.specimen_id < b.specimen_id


func _sort_largest_specimen_first(
	a: FishingFishSpecimen,
	b: FishingFishSpecimen
) -> bool:
	if a.is_king != b.is_king:
		return a.is_king and not b.is_king
	if not is_equal_approx(a.size, b.size):
		return a.size > b.size
	return a.specimen_id > b.specimen_id


func _remove_specimen_ids_transactional(selected_by_species: Dictionary) -> Dictionary:
	var removed_by_species: Dictionary = {}
	var changed_species: Dictionary = {}

	for raw_key in selected_by_species.keys():
		var key := _normalize_id(str(raw_key))
		var raw_ids = selected_by_species[raw_key]
		var ids: Dictionary = {}

		if raw_ids is PackedInt32Array:
			for specimen_id in raw_ids:
				ids[int(specimen_id)] = true
		elif raw_ids is Array:
			for specimen_id in raw_ids:
				ids[int(specimen_id)] = true

		var specimens := _get_specimen_array(key)
		var kept: Array = []
		var removed: Array[Dictionary] = []

		for value in specimens:
			var specimen := value as FishingFishSpecimen
			if specimen != null and ids.has(specimen.specimen_id):
				removed.append(specimen.to_dictionary())
				fish_specimen_removed.emit(key, specimen.duplicate_specimen())
			else:
				kept.append(value)

		_store_or_erase_specimen_array(key, kept)
		removed_by_species[key] = removed
		changed_species[key] = kept.size()

	if changed_species.is_empty():
		return removed_by_species

	_dirty = true
	for key in changed_species.keys():
		fish_count_changed.emit(str(key), int(changed_species[key]))
	changed.emit()
	return removed_by_species


func _emit_species_count_changed(species_id: String) -> void:
	var key := _normalize_id(species_id)
	_dirty = true
	fish_count_changed.emit(key, get_fish_count(key))
	changed.emit()


func _serialize_specimen_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for raw_key in fish_specimens.keys():
		var key := str(raw_key)
		var serialized: Array[Dictionary] = []
		for value in _get_specimen_array(key):
			var specimen := value as FishingFishSpecimen
			if specimen != null:
				serialized.append(specimen.to_dictionary())
		if not serialized.is_empty():
			result[key] = serialized
	return result


func _sanitize_specimen_dictionary(value) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		return result

	for raw_key in (value as Dictionary).keys():
		var key := _normalize_id(str(raw_key))
		var raw_list = (value as Dictionary)[raw_key]
		if key.is_empty() or not (raw_list is Array):
			continue

		var specimens: Array = []
		for raw_specimen in raw_list:
			if not (raw_specimen is Dictionary):
				continue
			var data: Dictionary = (raw_specimen as Dictionary).duplicate(true)
			data["species_id"] = key
			var specimen := FishingFishSpecimen.from_dictionary(data)
			if specimen.specimen_id <= 0:
				specimen.specimen_id = _allocate_specimen_id()
			specimens.append(specimen)

		if not specimens.is_empty():
			result[key] = specimens

	return result


func _repair_next_specimen_id() -> void:
	var highest := 0
	for raw_key in fish_specimens.keys():
		for value in _get_specimen_array(str(raw_key)):
			var specimen := value as FishingFishSpecimen
			if specimen != null:
				highest = maxi(highest, specimen.specimen_id)
	_next_specimen_id = maxi(maxi(_next_specimen_id, highest + 1), 1)


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
	fish_specimens.clear()
	lure_counts.clear()
	rod_counts.clear()
	_progress_migrated = false
	_dirty = false
	_next_specimen_id = 1
