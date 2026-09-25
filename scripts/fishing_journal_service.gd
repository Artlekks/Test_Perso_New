extends Node
class_name FishingJournalService

const CatchScoring = preload(
	"res://scripts/fishing_catch_scoring.gd"
)

enum DiscoveryState {
	UNKNOWN,
	CAUGHT,
	KING
}

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
	_validate_catalog_score_total()

	if is_instance_valid(_progress):
		_progress.reconcile_records_with_catalog(_fish_by_id)

	_connect_sources()
	changed.emit()


func get_summary() -> Dictionary:
	var discovered_count: int = 0
	var king_species_count: int = 0
	var max_score_species_count: int = 0

	for species_id in _ordered_species_ids:
		var key: String = str(species_id)
		var record: Dictionary = _get_record(key)
		var fish: FishData = _fish_by_id.get(key) as FishData
		var caught_count: int = int(record.get("caught_count", 0))

		if caught_count > 0:
			discovered_count += 1

		if bool(record.get("king_caught", false)):
			king_species_count += 1

		if (
			_has_catch_count(caught_count)
			and fish != null
			and int(record.get("best_points", 0)) >= maxi(fish.max_points, 0)
		):
			max_score_species_count += 1

	var total_species: int = _ordered_species_ids.size()
	var owned_fish_total: int = 0

	if is_instance_valid(_inventory):
		for value in _inventory.get_all_fish_counts().values():
			owned_fish_total += maxi(int(value), 0)

	var points: int = 0
	var total_catches: int = 0
	var rank_name: String = ""
	var rank_index: int = 0
	var rank_progress: Dictionary = {}

	if is_instance_valid(_progress):
		points = _progress.get_fishing_points()
		total_catches = _progress.get_total_catches()
		rank_name = _progress.get_rank_name()
		rank_index = _progress.get_rank_index()
		rank_progress = _progress.get_rank_progress()

	var max_points_total: int = _get_catalog_max_points()
	var points_remaining: int = maxi(max_points_total - points, 0)
	var score_completion_ratio: float = (
		clampf(float(points) / float(max_points_total), 0.0, 1.0)
		if max_points_total > 0
		else 0.0
	)

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
		"max_score_species": max_score_species_count,
		"owned_fish_total": owned_fish_total,
		"total_catches": total_catches,
		"fishing_points": points,
		"max_fishing_points": max_points_total,
		"points_remaining": points_remaining,
		"score_completion_ratio": score_completion_ratio,
		"perfect_score": max_points_total > 0 and points >= max_points_total,
		"rank_name": rank_name,
		"rank_index": rank_index,
		"rank_progress": rank_progress,
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
	var discovery_state: int = _get_discovery_state(record)
	var reveal_details := discovered or reveal_undiscovered_details
	var current_owned_count := 0

	if is_instance_valid(_inventory):
		current_owned_count = _inventory.get_fish_count(key)

	var entry := {
		"species_id": key,
		"source_index": _get_source_index(fish),
		"discovered": discovered,
		"discovery_state": discovery_state,
		"discovery_label": _get_discovery_label(discovery_state),
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
		"known_spots": _copy_dictionary_array(record.get("known_spots", [])),
		"successful_lures": _copy_dictionary_array(record.get("successful_lures", [])),
		"locations": [],
		"habitat_types": PackedStringArray(),
	}

	if not reveal_details:
		return entry

	var best_points: int = maxi(int(record.get("best_points", 0)), 0)
	var max_points: int = maxi(fish.max_points, 0)
	var best_size: float = maxf(float(record.get("best_size", 0.0)), 0.0)
	var king_size: float = maxf(fish.king_size, 0.0)

	entry["points_remaining"] = maxi(max_points - best_points, 0)
	entry["score_completion_ratio"] = (
		clampf(float(best_points) / float(max_points), 0.0, 1.0)
		if max_points > 0
		else 0.0
	)
	entry["is_max_score"] = max_points > 0 and best_points >= max_points
	entry["size_to_king_ratio"] = (
		clampf(best_size / king_size, 0.0, 1.0)
		if king_size > 0.0
		else 0.0
	)
	entry["cm_to_king"] = maxf(king_size - best_size, 0.0)

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
	entry["known_spot_ids"] = _extract_ids(
		entry["known_spots"],
		"spot_id"
	)
	entry["successful_lure_ids"] = _extract_ids(
		entry["successful_lures"],
		"lure_id"
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
		"discovered": bool(entry.get("discovered", false)),
		"discovery_state": int(entry.get("discovery_state", DiscoveryState.UNKNOWN)),
		"discovery_label": str(entry.get("discovery_label", "UNKNOWN")),
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
		"known_spots": _copy_dictionary_array(entry.get("known_spots", [])),
		"successful_lures": _copy_dictionary_array(entry.get("successful_lures", [])),
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


func get_progression_snapshot() -> Dictionary:
	var summary: Dictionary = get_summary()
	var rank_progress: Dictionary = summary.get("rank_progress", {})

	return {
		"fishing_points": int(summary.get("fishing_points", 0)),
		"max_fishing_points": int(summary.get("max_fishing_points", 0)),
		"points_remaining": int(summary.get("points_remaining", 0)),
		"score_completion_ratio": float(summary.get("score_completion_ratio", 0.0)),
		"perfect_score": bool(summary.get("perfect_score", false)),
		"rank_name": str(summary.get("rank_name", "")),
		"rank_index": int(summary.get("rank_index", 0)),
		"rank_progress": rank_progress.duplicate(true),
		"discovered_species": int(summary.get("discovered_species", 0)),
		"total_species": int(summary.get("total_species", 0)),
		"king_species": int(summary.get("king_species", 0)),
		"max_score_species": int(summary.get("max_score_species", 0)),
	}


func get_data_menu_snapshot(
	include_undiscovered: bool = true,
	reveal_undiscovered_details: bool = false
) -> Dictionary:
	# One backend payload for the future Data menu. Presentation/layout stays
	# completely outside this service.
	var species_entries: Array[Dictionary] = []

	for species_id in _ordered_species_ids:
		var entry: Dictionary = get_entry(
			str(species_id),
			reveal_undiscovered_details
		)
		if entry.is_empty():
			continue
		if (
			not include_undiscovered
			and not bool(entry.get("discovered", false))
		):
			continue
		species_entries.append(entry)

	return {
		"summary": get_summary(),
		"progression": get_progression_snapshot(),
		"species": species_entries,
		"spots": get_all_spot_snapshots(),
	}


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

	var species_ids: PackedStringArray = get_species_ids_for_spot(spot.spot_id)
	var discovered_species: int = 0
	var species_states: Array[Dictionary] = []
	var visited: bool = false

	for species_id in species_ids:
		var species_key: String = str(species_id)
		var record: Dictionary = _get_record(species_key)
		var discovered: bool = int(record.get("caught_count", 0)) > 0
		var known_here: bool = _record_knows_spot(record, str(spot.spot_id))
		var fish: FishData = _fish_by_id.get(species_key) as FishData
		var display_name: String = "????"

		if discovered:
			discovered_species += 1
			if fish != null:
				display_name = fish.fish_name

		if known_here:
			visited = true

		species_states.append({
			"species_id": species_key,
			"discovered": discovered,
			"caught_at_spot": known_here,
			"display_name": display_name,
		})

	var total_species: int = species_ids.size()

	return {
		"spot_id": str(spot.spot_id),
		"spot_name": spot.spot_name,
		"location_description": spot.location_description,
		"depth_notes": spot.depth_notes,
		"environment_type": _get_environment_type(str(spot.spot_id)),
		"visited": visited,
		"species_ids": species_ids,
		"species": species_states,
		"total_species": total_species,
		"discovered_species": discovered_species,
		"completion_ratio": (
			float(discovered_species) / float(total_species)
			if total_species > 0
			else 0.0
		),
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


func reset_all_fishing_data(
	delete_saves: bool = true,
	reset_inventory: bool = true
) -> void:
	if is_instance_valid(_progress):
		_progress.reset_all_progress(delete_saves)

	if reset_inventory and is_instance_valid(_inventory):
		_inventory.reset_inventory(delete_saves)

	changed.emit()


func reset_species_record(species_id: String) -> bool:
	if not is_instance_valid(_progress):
		return false

	var key: String = _normalize_id(species_id)
	var changed_record: bool = _progress.reset_species_progress_by_key(
		key,
		true
	)

	if changed_record and is_instance_valid(_inventory):
		var owned_count: int = _inventory.get_fish_count(key)
		if owned_count > 0:
			_inventory.remove_fish(key, owned_count, true)

	if changed_record:
		changed.emit()

	return changed_record


func debug_record_catch(
	species_id: String,
	size_cm: int,
	spot_id: String = "",
	spot_name: String = "",
	lure_id: String = "",
	lure_name: String = ""
) -> Dictionary:
	# Backend QA helper for menu testing. It uses the same permanent record path
	# as a real catch, so the UI can be populated without repeatedly fishing.
	if not is_instance_valid(_progress):
		return {}

	var key: String = _normalize_id(species_id)
	var fish: FishData = _fish_by_id.get(key) as FishData
	if fish == null:
		return {}

	var specimen := FishInstance.new()
	specimen.species = fish
	specimen.size = float(maxi(size_cm, 1))
	specimen.is_king = specimen.size >= fish.king_size
	specimen.points = CatchScoring.calculate_points(
		fish,
		specimen.size,
		specimen.is_king
	)

	if spot_name.is_empty() and not spot_id.is_empty():
		var spot: FishingSpotData = _spots_by_id.get(
			_normalize_id(spot_id)
		) as FishingSpotData
		if spot != null:
			spot_name = spot.spot_name

	return _progress.record_catch(
		specimen,
		{
			"spot_id": spot_id,
			"spot_name": spot_name,
			"lure_id": lure_id,
			"lure_name": lure_name,
		}
	)


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
	var record: Dictionary = _get_record(species_id)

	for raw_location in raw_locations:
		if not (raw_location is Dictionary):
			continue

		var location: Dictionary = (raw_location as Dictionary).duplicate(true)
		location["discovered"] = _record_knows_spot(
			record,
			str(location.get("spot_id", ""))
		)
		result.append(location)

	return result


func _get_discovery_state(record: Dictionary) -> int:
	if int(record.get("caught_count", 0)) <= 0:
		return DiscoveryState.UNKNOWN
	if bool(record.get("king_caught", false)):
		return DiscoveryState.KING
	return DiscoveryState.CAUGHT


func _get_discovery_label(state: int) -> String:
	match state:
		DiscoveryState.KING:
			return "KING"
		DiscoveryState.CAUGHT:
			return "CAUGHT"
		_:
			return "UNKNOWN"


func _copy_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (raw_value is Array):
		return result

	var source_values: Array = raw_value as Array
	for value in source_values:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


func _extract_ids(raw_value: Variant, id_key: String) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}

	if not (raw_value is Array):
		return result

	var source_values: Array = raw_value as Array
	for value in source_values:
		if not (value is Dictionary):
			continue
		var entry_id: String = str((value as Dictionary).get(id_key, ""))
		if entry_id.is_empty() or seen.has(entry_id):
			continue
		seen[entry_id] = true
		result.append(entry_id)

	return result


func _record_knows_spot(record: Dictionary, spot_id: String) -> bool:
	var normalized_spot: String = _normalize_id(spot_id)
	if normalized_spot.is_empty():
		return false

	var known_spots: Variant = record.get("known_spots", [])
	if not (known_spots is Array):
		return false

	var source_spots: Array = known_spots as Array
	for value in source_spots:
		if not (value is Dictionary):
			continue
		var known_id: String = _normalize_id(
			str((value as Dictionary).get("spot_id", ""))
		)
		if known_id == normalized_spot:
			return true

	return false


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


func _validate_catalog_score_total() -> void:
	if not is_instance_valid(_progress):
		return

	var catalog_total: int = _get_catalog_max_points()
	var expected_total: int = _progress.get_max_fishing_points()

	if catalog_total != expected_total:
		push_warning(
			"FishingJournalService: catalog max score is %d, expected %d."
			% [catalog_total, expected_total]
		)


func _get_catalog_max_points() -> int:
	var total: int = 0

	for species_id in _ordered_species_ids:
		var fish: FishData = _fish_by_id.get(str(species_id)) as FishData
		if fish == null:
			continue
		total += maxi(fish.max_points, 0)

	return total


func _has_catch_count(caught_count: int) -> bool:
	return caught_count > 0


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
