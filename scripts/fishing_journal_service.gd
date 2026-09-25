extends Node
class_name FishingJournalService

signal changed

var _progress: FishingProgress = null
var _inventory: FishingInventory = null
var _catalog: FishingJournalCatalog = null

var _fish_by_id: Dictionary = {}
var _spots_by_id: Dictionary = {}
var _locations_by_species: Dictionary = {}
var _ordered_species_ids: PackedStringArray = PackedStringArray()


func configure(
	progress: FishingProgress,
	inventory: FishingInventory,
	catalog: FishingJournalCatalog
) -> void:
	_disconnect_sources()

	_progress = progress
	_inventory = inventory
	_catalog = catalog
	_rebuild_static_index()
	_connect_sources()
	changed.emit()


func get_summary() -> Dictionary:
	var discovered_count := 0
	var king_species_count := 0

	for species_id in _ordered_species_ids:
		var record := _get_record(str(species_id))
		if int(record.get("caught_count", 0)) > 0:
			discovered_count += 1
		if bool(record.get("king_caught", false)):
			king_species_count += 1

	var total_species := _ordered_species_ids.size()
	var owned_fish_total := 0

	if is_instance_valid(_inventory):
		for value in _inventory.get_all_fish_counts().values():
			owned_fish_total += maxi(int(value), 0)

	var points := 0
	var total_catches := 0
	var rank_name := ""
	var rank_index := 0

	if is_instance_valid(_progress):
		points = _progress.get_fishing_points()
		total_catches = _progress.get_total_catches()
		if _progress.has_method("get_rank_name"):
			rank_name = _progress.get_rank_name()
		if _progress.has_method("get_rank_index"):
			rank_index = _progress.get_rank_index()

	return {
		"total_species": total_species,
		"discovered_species": discovered_count,
		"undiscovered_species": maxi(total_species - discovered_count, 0),
		"completion_ratio": (
			float(discovered_count) / float(total_species)
			if total_species > 0
			else 0.0
		),
		"king_species": king_species_count,
		"owned_fish_total": owned_fish_total,
		"total_catches": total_catches,
		"fishing_points": points,
		"rank_name": rank_name,
		"rank_index": rank_index,
	}


func get_entries(
	include_undiscovered: bool = true,
	reveal_undiscovered_details: bool = false
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	for species_id in _ordered_species_ids:
		var entry := get_entry(
			str(species_id),
			reveal_undiscovered_details
		)
		if entry.is_empty():
			continue
		if not include_undiscovered and not bool(entry.get("discovered", false)):
			continue
		entries.append(entry)

	return entries


func get_entry(
	species_id: String,
	reveal_undiscovered_details: bool = false
) -> Dictionary:
	var key := _normalize_id(species_id)
	var fish := _fish_by_id.get(key) as FishData

	if fish == null:
		return {}

	var record := _get_record(key)
	var caught_count := maxi(int(record.get("caught_count", 0)), 0)
	var discovered := caught_count > 0
	var reveal_details := discovered or reveal_undiscovered_details
	var current_owned_count := 0

	if is_instance_valid(_inventory):
		current_owned_count = _inventory.get_fish_count(key)

	var entry := {
		"species_id": key,
		"source_index": _get_source_index(fish),
		"discovered": discovered,
		"display_name": fish.fish_name if reveal_details else "????",
		"portrait": fish.portrait if reveal_details else null,
		"shadow_visual_profile": fish.shadow_visual_profile,
		"shadow_visual_profile_name": _get_shadow_profile_name(
			fish.shadow_visual_profile
		),
		"caught_count": caught_count,
		"current_owned_count": current_owned_count,
		"best_size": float(record.get("best_size", 0.0)),
		"best_size_points": int(record.get("best_size_points", 0)),
		"best_size_spot_id": str(record.get("best_size_spot_id", "")),
		"best_size_spot_name": str(record.get("best_size_spot_name", "")),
		"best_size_lure_id": str(record.get("best_size_lure_id", "")),
		"best_size_lure_name": str(record.get("best_size_lure_name", "")),
		"best_points": int(record.get("best_points", 0)),
		"best_points_size": float(record.get("best_points_size", 0.0)),
		"best_points_spot_id": str(record.get("best_points_spot_id", "")),
		"best_points_spot_name": str(record.get("best_points_spot_name", "")),
		"best_points_lure_id": str(record.get("best_points_lure_id", "")),
		"best_points_lure_name": str(record.get("best_points_lure_name", "")),
		"last_catch_size": float(record.get("last_catch_size", 0.0)),
		"last_catch_points": int(record.get("last_catch_points", 0)),
		"last_catch_is_king": bool(record.get("last_catch_is_king", false)),
		"last_catch_spot_id": str(record.get("last_catch_spot_id", "")),
		"last_catch_spot_name": str(record.get("last_catch_spot_name", "")),
		"last_catch_lure_id": str(record.get("last_catch_lure_id", "")),
		"last_catch_lure_name": str(record.get("last_catch_lure_name", "")),
		"king_caught": bool(record.get("king_caught", false)),
		"king_count": maxi(int(record.get("king_count", 0)), 0),
		"locations": [],
		"habitat_types": PackedStringArray(),
	}

	if not reveal_details:
		return entry

	var locations := _get_location_snapshots(key)
	entry["locations"] = locations
	entry["habitat_types"] = _get_habitat_types(locations)
	entry["average_size"] = fish.average_size
	entry["king_size"] = fish.king_size
	entry["max_points"] = fish.max_points
	entry["preferred_depth_min"] = fish.preferred_depth_min
	entry["preferred_depth_max"] = fish.preferred_depth_max
	entry["preferred_lure_ids"] = _string_name_array_to_strings(
		fish.preferred_lure_ids
	)
	entry["preferred_lure_types"] = fish.preferred_lure_types.duplicate()
	entry["source_effect"] = str(fish.get_meta("source_effect", ""))
	entry["source_worth_zenny"] = int(fish.get_meta("source_worth_zenny", 0))
	entry["source_preferred_lures"] = str(
		fish.get_meta("source_preferred_lures", "")
	)
	entry["source_preferred_depth"] = str(
		fish.get_meta("source_preferred_depth", "")
	)

	return entry


func get_record_snapshot(species_id: String) -> Dictionary:
	# Stable backend-facing record payload for Data/menu screens. The UI does
	# not need to know FishingProgress' save schema.
	var entry: Dictionary = get_entry(species_id, false)
	if entry.is_empty() or not bool(entry.get("discovered", false)):
		return entry

	return {
		"species_id": str(entry.get("species_id", "")),
		"display_name": str(entry.get("display_name", "")),
		"portrait": entry.get("portrait", null),
		"caught_count": int(entry.get("caught_count", 0)),
		"best_size": float(entry.get("best_size", 0.0)),
		"best_size_points": int(entry.get("best_size_points", 0)),
		"best_size_spot_id": str(entry.get("best_size_spot_id", "")),
		"best_size_spot_name": str(entry.get("best_size_spot_name", "")),
		"best_size_lure_id": str(entry.get("best_size_lure_id", "")),
		"best_size_lure_name": str(entry.get("best_size_lure_name", "")),
		"best_points": int(entry.get("best_points", 0)),
		"best_points_size": float(entry.get("best_points_size", 0.0)),
		"best_points_spot_id": str(entry.get("best_points_spot_id", "")),
		"best_points_spot_name": str(entry.get("best_points_spot_name", "")),
		"best_points_lure_id": str(entry.get("best_points_lure_id", "")),
		"best_points_lure_name": str(entry.get("best_points_lure_name", "")),
		"king_caught": bool(entry.get("king_caught", false)),
		"king_count": int(entry.get("king_count", 0)),
		"average_size": float(entry.get("average_size", 0.0)),
		"king_size": float(entry.get("king_size", 0.0)),
		"max_points": int(entry.get("max_points", 0)),
	}


func get_record_snapshots(
	include_undiscovered: bool = true
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for species_id in _ordered_species_ids:
		var snapshot: Dictionary = get_record_snapshot(str(species_id))
		if snapshot.is_empty():
			continue
		if (
			not include_undiscovered
			and not bool(snapshot.get("discovered", true))
		):
			continue
		result.append(snapshot)

	return result


func get_entries_for_spot(
	spot_id: StringName,
	include_undiscovered: bool = true,
	reveal_undiscovered_details: bool = false
) -> Array[Dictionary]:
	var normalized_spot_id := _normalize_id(str(spot_id))
	var spot := _spots_by_id.get(normalized_spot_id) as FishingSpotData
	var result: Array[Dictionary] = []

	if spot == null:
		return result

	var seen: Dictionary = {}
	for spawn_entry in spot.get_fish_population():
		if spawn_entry == null or spawn_entry.fish == null:
			continue

		var species_id := _get_species_id(spawn_entry.fish)
		if species_id.is_empty() or seen.has(species_id):
			continue
		seen[species_id] = true

		var entry := get_entry(species_id, reveal_undiscovered_details)
		if entry.is_empty():
			continue
		if not include_undiscovered and not bool(entry.get("discovered", false)):
			continue
		result.append(entry)

	return result


func get_species_ids_for_spot(spot_id: StringName) -> PackedStringArray:
	var ids := PackedStringArray()
	var normalized_spot_id := _normalize_id(str(spot_id))
	var spot := _spots_by_id.get(normalized_spot_id) as FishingSpotData

	if spot == null:
		return ids

	var seen: Dictionary = {}
	for spawn_entry in spot.get_fish_population():
		if spawn_entry == null or spawn_entry.fish == null:
			continue
		var species_id := _get_species_id(spawn_entry.fish)
		if species_id.is_empty() or seen.has(species_id):
			continue
		seen[species_id] = true
		ids.append(species_id)

	return ids


func get_spot_snapshot(spot_id: StringName) -> Dictionary:
	var key := _normalize_id(str(spot_id))
	var spot := _spots_by_id.get(key) as FishingSpotData
	if spot == null:
		return {}

	return {
		"spot_id": str(spot.spot_id),
		"spot_name": spot.spot_name,
		"location_description": spot.location_description,
		"depth_notes": spot.depth_notes,
		"environment_type": _get_environment_type(str(spot.spot_id)),
		"species_ids": get_species_ids_for_spot(spot.spot_id),
	}


func get_all_spot_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _catalog == null:
		return result

	for spot in _catalog.spots:
		if spot == null:
			continue
		var snapshot := get_spot_snapshot(spot.spot_id)
		if not snapshot.is_empty():
			result.append(snapshot)
	return result


func is_discovered(species_id: String) -> bool:
	return int(_get_record(_normalize_id(species_id)).get("caught_count", 0)) > 0


func get_species_count() -> int:
	return _ordered_species_ids.size()


func _rebuild_static_index() -> void:
	_fish_by_id.clear()
	_spots_by_id.clear()
	_locations_by_species.clear()
	_ordered_species_ids = PackedStringArray()

	if _catalog == null:
		return

	for fish in _catalog.species:
		if fish == null:
			continue
		var species_id := _get_species_id(fish)
		if species_id.is_empty() or _fish_by_id.has(species_id):
			continue
		_fish_by_id[species_id] = fish
		_ordered_species_ids.append(species_id)

	for spot in _catalog.spots:
		if spot == null:
			continue

		var spot_key := _normalize_id(str(spot.spot_id))
		if not spot_key.is_empty():
			_spots_by_id[spot_key] = spot

		for spawn_entry in spot.get_fish_population():
			if spawn_entry == null or spawn_entry.fish == null:
				continue

			var species_id := _get_species_id(spawn_entry.fish)
			if species_id.is_empty():
				continue

			var locations: Array = _locations_by_species.get(species_id, [])
			var duplicate := false
			for location in locations:
				if str(location.get("spot_id", "")) == str(spot.spot_id):
					duplicate = true
					break

			if duplicate:
				continue

			locations.append({
				"spot_id": str(spot.spot_id),
				"spot_name": spot.spot_name,
				"location_description": spot.location_description,
				"environment_type": _get_environment_type(str(spot.spot_id)),
				"population_weight": float(spawn_entry.weight),
			})
			_locations_by_species[species_id] = locations


func _get_location_snapshots(species_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_locations: Array = _locations_by_species.get(species_id, [])
	for raw_location in raw_locations:
		if raw_location is Dictionary:
			result.append((raw_location as Dictionary).duplicate(true))
	return result


func _get_habitat_types(locations: Array[Dictionary]) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}

	for location in locations:
		var habitat := str(location.get("environment_type", ""))
		if habitat.is_empty() or seen.has(habitat):
			continue
		seen[habitat] = true
		result.append(habitat)

	return result


func _get_record(species_id: String) -> Dictionary:
	if not is_instance_valid(_progress):
		return {}
	return _progress.get_species_record_by_key(species_id)


func _get_species_id(fish: FishData) -> String:
	if fish == null:
		return ""

	if is_instance_valid(_progress):
		return _normalize_id(_progress.get_species_key(fish))

	if not fish.resource_path.is_empty():
		return _normalize_id(fish.resource_path.get_file().get_basename())

	return _normalize_id(fish.fish_name)


func _get_source_index(fish: FishData) -> int:
	if fish == null:
		return 0
	return int(fish.get_meta("source_index", 0))


func _get_shadow_profile_name(profile: int) -> String:
	match profile:
		FishData.ShadowVisualProfile.ROUND:
			return "ROUND"
		FishData.ShadowVisualProfile.WIDE:
			return "WIDE"
		FishData.ShadowVisualProfile.SQUID:
			return "SQUID"
		FishData.ShadowVisualProfile.JELLY:
			return "JELLY"
		_:
			return "LONG_FISH"


func _get_environment_type(spot_id: String) -> String:
	var key := _normalize_id(spot_id)
	if key.begins_with("river_"):
		return "RIVER"
	if key.begins_with("lake_"):
		return "LAKE"
	if key.begins_with("ocean_"):
		return "OCEAN"
	return "SPECIAL"


func _string_name_array_to_strings(values: Array[StringName]) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		result.append(str(value))
	return result


func _normalize_id(value: String) -> String:
	return (
		value.strip_edges()
		.to_lower()
		.replace(" ", "_")
		.replace("-", "_")
		.replace("'", "")
	)


func _connect_sources() -> void:
	if is_instance_valid(_progress):
		var progress_callback := Callable(self, "_on_source_changed")
		if not _progress.changed.is_connected(progress_callback):
			_progress.changed.connect(progress_callback)

	if is_instance_valid(_inventory):
		var inventory_callback := Callable(self, "_on_source_changed")
		if not _inventory.changed.is_connected(inventory_callback):
			_inventory.changed.connect(inventory_callback)


func _disconnect_sources() -> void:
	if is_instance_valid(_progress):
		var progress_callback := Callable(self, "_on_source_changed")
		if _progress.changed.is_connected(progress_callback):
			_progress.changed.disconnect(progress_callback)

	if is_instance_valid(_inventory):
		var inventory_callback := Callable(self, "_on_source_changed")
		if _inventory.changed.is_connected(inventory_callback):
			_inventory.changed.disconnect(inventory_callback)


func _on_source_changed() -> void:
	changed.emit()
