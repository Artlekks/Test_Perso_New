extends Node
class_name FishingProgress

const CatchScoring = preload(
	"res://scripts/fishing_catch_scoring.gd"
)

signal changed
signal catch_recorded(
	species_key: String,
	record: Dictionary,
	fishing_points: int
)
signal catch_specimen_recorded(
	species_key: String,
	specimen_data: Dictionary
)

const SAVE_VERSION: int = 4
const MAX_FISHING_POINTS: int = 9999
const SAVE_PATH: String = "user://fishing_progress.json"

# Breath of Fire IV fishing-level thresholds. At an exact threshold the new
# rank begins (e.g. 200 points = Beginner+).
const RANK_TABLE: Array[Dictionary] = [
	{"min_points": 0, "name": "Beginner"},
	{"min_points": 200, "name": "Beginner+"},
	{"min_points": 500, "name": "Beginner++"},
	{"min_points": 1000, "name": "Rodman"},
	{"min_points": 2000, "name": "Rodman+"},
	{"min_points": 4000, "name": "Rodman++"},
	{"min_points": 5000, "name": "Rodmaster"},
	{"min_points": 7000, "name": "Rodmaster+"},
	{"min_points": 9000, "name": "Rodmaster++"},
	{"min_points": 9500, "name": "The Fish"},
]

var fishing_points: int = 0
var total_catches: int = 0
var species_records: Dictionary = {}

var _initialized: bool = false


func _ready() -> void:
	initialize()


func initialize() -> void:
	if _initialized:
		return

	_initialized = true
	load_from_disk()


func record_catch(
	fish: FishInstance,
	catch_context: Dictionary = {}
) -> Dictionary:
	if fish == null or fish.species == null:
		return {}

	var species_key := get_species_key(fish.species)

	if species_key.is_empty():
		push_warning(
			"FishingProgress: Could not build a stable species key."
		)
		return {}

	var record: Dictionary = species_records.get(
		species_key,
		_create_empty_record(fish.species)
	).duplicate(true)

	var previous_caught_count := int(
		record.get("caught_count", 0)
	)
	var previous_best_size := float(
		record.get("best_size", 0.0)
	)
	var previous_best_points := int(
		record.get("best_points", 0)
	)
	var previous_best_points_size := float(
		record.get("best_points_size", 0.0)
	)
	var previous_king_caught := bool(
		record.get("king_caught", false)
	)
	var previous_fishing_points := fishing_points
	var previous_rank_index := get_rank_index(previous_fishing_points)
	var context := _sanitize_catch_context(catch_context)
	var discovery_result: Dictionary = _record_context_discovery(
		record,
		context
	)

	record["fish_name"] = fish.species.fish_name
	record["caught_count"] = int(
		record.get("caught_count", 0)
	) + 1

	if fish.size > previous_best_size:
		record["best_size"] = fish.size
		record["best_size_points"] = fish.points
		_copy_context_to_record(record, "best_size", context)

	var improves_points: bool = fish.points > previous_best_points
	var improves_equal_point_specimen: bool = (
		fish.points == previous_best_points
		and fish.size > previous_best_points_size
	)

	if improves_points or improves_equal_point_specimen:
		record["best_points"] = fish.points
		record["best_points_size"] = fish.size
		_copy_context_to_record(record, "best_points", context)

	record["last_catch_size"] = fish.size
	record["last_catch_points"] = fish.points
	record["last_catch_is_king"] = fish.is_king
	_copy_context_to_record(record, "last_catch", context)

	if fish.is_king:
		record["king_caught"] = true
		record["king_count"] = int(
			record.get("king_count", 0)
		) + 1

	species_records[species_key] = record
	total_catches += 1
	_recalculate_fishing_points()
	var current_rank_index := get_rank_index(fishing_points)
	var current_rank_name := get_rank_name(fishing_points)

	var result := {
		"species_key": species_key,
		"record": record.duplicate(true),
		"new_species": (
			previous_caught_count <= 0
		),
		"new_spot_discovery": bool(
			discovery_result.get("new_spot", false)
		),
		"new_lure_discovery": bool(
			discovery_result.get("new_lure", false)
		),
		"new_best_size": (
			fish.size > previous_best_size
		),
		"new_best_points": improves_points,
		"best_points_record_changed": (
			improves_points or improves_equal_point_specimen
		),
		"first_king": (
			fish.is_king
			and not previous_king_caught
		),
		"previous_best_size": previous_best_size,
		"previous_best_points": previous_best_points,
		"fishing_points_before": previous_fishing_points,
		"fishing_points": fishing_points,
		"fishing_points_gained": maxi(
			fishing_points - previous_fishing_points,
			0
		),
		"rank_before": get_rank_name(previous_fishing_points),
		"rank_name": current_rank_name,
		"rank_index": current_rank_index,
		"rank_up": current_rank_index > previous_rank_index,
		"next_rank_points": get_next_rank_threshold(fishing_points),
		"catch_context": context.duplicate(true)
	}

	save_to_disk()
	changed.emit()
	catch_recorded.emit(
		species_key,
		record.duplicate(true),
		fishing_points
	)
	catch_specimen_recorded.emit(
		species_key,
		{
			"fish_name": fish.species.fish_name,
			"size": fish.size,
			"points": fish.points,
			"is_king": fish.is_king,
			"spot_id": str(context.get("spot_id", "")),
			"spot_name": str(context.get("spot_name", "")),
			"lure_id": str(context.get("lure_id", "")),
			"lure_name": str(context.get("lure_name", "")),
		}
	)

	return result


func get_fishing_points() -> int:
	return fishing_points


func get_rank_index(points: int = -1) -> int:
	var value := fishing_points if points < 0 else clampi(points, 0, MAX_FISHING_POINTS)
	var rank_index := 0

	for index in range(RANK_TABLE.size()):
		if value < int(RANK_TABLE[index]["min_points"]):
			break
		rank_index = index

	return rank_index


func get_rank_name(points: int = -1) -> String:
	if RANK_TABLE.is_empty():
		return ""

	return str(RANK_TABLE[get_rank_index(points)]["name"])


func get_next_rank_threshold(points: int = -1) -> int:
	var value := fishing_points if points < 0 else clampi(points, 0, MAX_FISHING_POINTS)
	var current_index := get_rank_index(value)

	if current_index >= RANK_TABLE.size() - 1:
		return MAX_FISHING_POINTS

	return int(RANK_TABLE[current_index + 1]["min_points"])


func get_rank_progress(points: int = -1) -> Dictionary:
	var value: int = (
		fishing_points
		if points < 0
		else clampi(points, 0, MAX_FISHING_POINTS)
	)
	var index: int = get_rank_index(value)
	var current_min: int = int(RANK_TABLE[index]["min_points"])
	var next_threshold: int = get_next_rank_threshold(value)
	var is_max_rank: bool = index >= RANK_TABLE.size() - 1

	# The final rank still has useful progress from 9500 -> perfect 9999.
	# For every other rank, progress ends at the next rank threshold.
	var span_end: int = (
		MAX_FISHING_POINTS
		if is_max_rank
		else next_threshold
	)
	var span_size: int = maxi(span_end - current_min, 1)
	var points_into_rank: int = clampi(
		value - current_min,
		0,
		span_size
	)
	var points_to_next: int = maxi(span_end - value, 0)
	var progress_ratio: float = clampf(
		float(points_into_rank) / float(span_size),
		0.0,
		1.0
	)

	return {
		"index": index,
		"name": str(RANK_TABLE[index]["name"]),
		"points": value,
		"current_min": current_min,
		"next_threshold": next_threshold,
		"is_max_rank": is_max_rank,
		"points_into_rank": points_into_rank,
		"rank_span_points": span_size,
		"points_to_next": points_to_next,
		"progress_ratio": progress_ratio,
		"max_fishing_points": MAX_FISHING_POINTS,
	}


func get_max_fishing_points() -> int:
	return MAX_FISHING_POINTS


func get_total_catches() -> int:
	return total_catches


func get_species_record(species: FishData) -> Dictionary:
	if species == null:
		return {}

	var species_key := get_species_key(species)

	if species_key.is_empty():
		return {}

	if not species_records.has(species_key):
		return {}

	return (
		species_records[species_key]
		as Dictionary
	).duplicate(true)


func get_species_record_by_key(
	species_key: String
) -> Dictionary:
	if not species_records.has(species_key):
		return {}

	return (
		species_records[species_key]
		as Dictionary
	).duplicate(true)


func get_all_records() -> Dictionary:
	return species_records.duplicate(true)


func has_caught(species: FishData) -> bool:
	var record := get_species_record(species)

	return int(record.get("caught_count", 0)) > 0


func get_species_key(species: FishData) -> String:
	if species == null:
		return ""

	# We deliberately use the FishData resource filename as the persistent
	# identity in this first pass. This avoids rewriting all 30 FishData
	# resources while the database is still evolving.
	if not species.resource_path.is_empty():
		return (
			species.resource_path
			.get_file()
			.get_basename()
		)

	# Defensive fallback for dynamically-created FishData.
	return (
		species.fish_name
		.strip_edges()
		.to_lower()
		.replace(" ", "_")
		.replace("-", "_")
		.replace("'", "")
	)


func save_to_disk() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"fishing_points": fishing_points,
		"total_catches": total_catches,
		"species_records": species_records
	}

	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.WRITE
	)

	if file == null:
		push_warning(
			"FishingProgress: Could not open save file for writing."
		)
		return false

	file.store_string(
		JSON.stringify(
			payload,
			"\t"
		)
	)
	file.close()
	return true


func load_from_disk() -> bool:
	_reset_runtime_state()

	if not FileAccess.file_exists(SAVE_PATH):
		return true

	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.READ
	)

	if file == null:
		push_warning(
			"FishingProgress: Could not open save file for reading."
		)
		return false

	var raw_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(raw_text)

	if not (parsed is Dictionary):
		push_warning(
			"FishingProgress: Save file is invalid; starting with empty records."
		)
		return false

	var data: Dictionary = parsed
	var version := int(data.get("version", 0))

	if version > SAVE_VERSION:
		push_warning(
			"FishingProgress: Save version is newer than this build."
		)
		return false

	var saved_total_catches: int = maxi(
		int(data.get("total_catches", 0)),
		0
	)

	var loaded_records = data.get(
		"species_records",
		{}
	)

	if loaded_records is Dictionary:
		for key in loaded_records.keys():
			var raw_record = loaded_records[key]

			if not (raw_record is Dictionary):
				continue

			species_records[str(key)] = (
				_sanitize_record(
					raw_record as Dictionary
				)
			)

	# Lifetime total and fishing score are both derived from the sanitized
	# per-species records. Never trust stale cached totals from disk.
	_recalculate_total_catches()
	_recalculate_fishing_points()

	# Keep a larger legacy total only if an older build recorded catches that
	# could not be represented in species_records. Normal modern saves should
	# always match the derived value exactly.
	total_catches = maxi(total_catches, saved_total_catches)

	changed.emit()
	return true


func reset_all_progress(delete_save: bool = true) -> void:
	_reset_runtime_state()

	if delete_save and FileAccess.file_exists(SAVE_PATH):
		var absolute_path := ProjectSettings.globalize_path(
			SAVE_PATH
		)
		DirAccess.remove_absolute(absolute_path)

	changed.emit()


func reset_species_progress_by_key(
	species_key: String,
	persist: bool = true
) -> bool:
	var key: String = species_key.strip_edges().to_lower()
	if key.is_empty() or not species_records.has(key):
		return false

	species_records.erase(key)
	_recalculate_total_catches()
	_recalculate_fishing_points()

	if persist:
		save_to_disk()

	changed.emit()
	return true


func _recalculate_total_catches() -> void:
	var total: int = 0

	for raw_record in species_records.values():
		if not (raw_record is Dictionary):
			continue
		total += maxi(int((raw_record as Dictionary).get("caught_count", 0)), 0)

	total_catches = maxi(total, 0)


func reconcile_records_with_catalog(species_by_id: Dictionary) -> bool:
	# Migration/integrity pass run once the journal has access to FishData.
	# This upgrades old fractional sizes and old linear scores to the current
	# whole-centimeter / BOF4-style tiered scoring without UI involvement.
	var changed_any: bool = false

	for raw_key in species_records.keys():
		var key: String = str(raw_key)
		var fish: FishData = species_by_id.get(key) as FishData
		if fish == null:
			continue

		var old_record: Dictionary = (species_records[key] as Dictionary).duplicate(true)
		var record: Dictionary = _sanitize_record(old_record)

		var best_size: float = float(roundi(float(record.get("best_size", 0.0))))
		var best_points_size: float = float(roundi(float(record.get("best_points_size", 0.0))))
		var last_size: float = float(roundi(float(record.get("last_catch_size", 0.0))))

		record["best_size"] = best_size
		record["best_points_size"] = best_points_size
		record["last_catch_size"] = last_size

		if best_size > 0.0:
			var best_size_is_king: bool = best_size >= fish.king_size
			record["best_size_points"] = CatchScoring.calculate_points(
				fish,
				best_size,
				best_size_is_king
			)

		if best_points_size <= 0.0 and best_size > 0.0:
			best_points_size = best_size
			record["best_points_size"] = best_points_size
			_copy_record_context(record, "best_size", "best_points")

		var best_points_score: int = 0
		if best_points_size > 0.0:
			best_points_score = CatchScoring.calculate_points(
				fish,
				best_points_size,
				best_points_size >= fish.king_size
			)

		var best_size_score: int = int(record.get("best_size_points", 0))
		if (
			best_size_score > best_points_score
			or (
				best_size_score == best_points_score
				and best_size > best_points_size
			)
		):
			record["best_points"] = best_size_score
			record["best_points_size"] = best_size
			_copy_record_context(record, "best_size", "best_points")
		else:
			record["best_points"] = best_points_score

		if last_size > 0.0:
			var last_is_king: bool = last_size >= fish.king_size
			record["last_catch_is_king"] = last_is_king
			record["last_catch_points"] = CatchScoring.calculate_points(
				fish,
				last_size,
				last_is_king
			)

		if best_size >= fish.king_size and best_size > 0.0:
			record["king_caught"] = true
			record["king_count"] = maxi(int(record.get("king_count", 0)), 1)

		if record != old_record:
			species_records[key] = record
			changed_any = true

	if changed_any:
		_recalculate_total_catches()
		_recalculate_fishing_points()
		save_to_disk()
		changed.emit()

	return changed_any


func _copy_record_context(
	record: Dictionary,
	from_prefix: String,
	to_prefix: String
) -> void:
	for suffix in ["spot_id", "spot_name", "lure_id", "lure_name"]:
		record[to_prefix + "_" + suffix] = str(
			record.get(from_prefix + "_" + suffix, "")
		)


func _recalculate_fishing_points() -> void:
	var total := 0

	for raw_record in species_records.values():
		if not (raw_record is Dictionary):
			continue

		total += maxi(
			int(
				(raw_record as Dictionary).get(
					"best_points",
					0
				)
			),
			0
		)

	fishing_points = mini(
		total,
		MAX_FISHING_POINTS
	)


func _create_empty_record(
	species: FishData
) -> Dictionary:
	return {
		"fish_name": (
			species.fish_name
			if species != null
			else ""
		),
		"caught_count": 0,
		"best_size": 0.0,
		"best_size_points": 0,
		"best_size_spot_id": "",
		"best_size_spot_name": "",
		"best_size_lure_id": "",
		"best_size_lure_name": "",
		"best_points": 0,
		"best_points_size": 0.0,
		"best_points_spot_id": "",
		"best_points_spot_name": "",
		"best_points_lure_id": "",
		"best_points_lure_name": "",
		"last_catch_size": 0.0,
		"last_catch_points": 0,
		"last_catch_is_king": false,
		"last_catch_spot_id": "",
		"last_catch_spot_name": "",
		"last_catch_lure_id": "",
		"last_catch_lure_name": "",
		"king_caught": false,
		"king_count": 0,
		"known_spots": [],
		"successful_lures": []
	}


func _sanitize_record(
	record: Dictionary
) -> Dictionary:
	var result: Dictionary = {
		"fish_name": str(
			record.get("fish_name", "")
		),
		"caught_count": maxi(
			int(
				record.get(
					"caught_count",
					0
				)
			),
			0
		),
		"best_size": float(maxi(roundi(float(record.get("best_size", 0.0))), 0)),
		"best_size_points": maxi(int(record.get("best_size_points", 0)), 0),
		"best_size_spot_id": str(record.get("best_size_spot_id", "")),
		"best_size_spot_name": str(record.get("best_size_spot_name", "")),
		"best_size_lure_id": str(record.get("best_size_lure_id", "")),
		"best_size_lure_name": str(record.get("best_size_lure_name", "")),
		"best_points": maxi(
			int(
				record.get(
					"best_points",
					0
				)
			),
			0
		),
		"best_points_size": float(maxi(roundi(float(record.get("best_points_size", 0.0))), 0)),
		"best_points_spot_id": str(record.get("best_points_spot_id", "")),
		"best_points_spot_name": str(record.get("best_points_spot_name", "")),
		"best_points_lure_id": str(record.get("best_points_lure_id", "")),
		"best_points_lure_name": str(record.get("best_points_lure_name", "")),
		"last_catch_size": float(maxi(roundi(float(record.get("last_catch_size", 0.0))), 0)),
		"last_catch_points": maxi(int(record.get("last_catch_points", 0)), 0),
		"last_catch_is_king": bool(record.get("last_catch_is_king", false)),
		"last_catch_spot_id": str(record.get("last_catch_spot_id", "")),
		"last_catch_spot_name": str(record.get("last_catch_spot_name", "")),
		"last_catch_lure_id": str(record.get("last_catch_lure_id", "")),
		"last_catch_lure_name": str(record.get("last_catch_lure_name", "")),
		"king_caught": bool(
			record.get(
				"king_caught",
				false
			)
		),
		"king_count": maxi(
			int(
				record.get(
					"king_count",
					0
				)
			),
			0
		),
		"known_spots": _sanitize_discovery_entries(
			record.get("known_spots", []),
			"spot_id",
			"spot_name"
		),
		"successful_lures": _sanitize_discovery_entries(
			record.get("successful_lures", []),
			"lure_id",
			"lure_name"
		)
	}

	if int(result["king_count"]) > 0:
		result["king_caught"] = true

	_backfill_discovery_from_record_context(result)
	return result


func _backfill_discovery_from_record_context(record: Dictionary) -> void:
	# Version-4 migration: older records already stored context for best/last
	# catches. Preserve that useful knowledge instead of starting discovery at
	# zero after upgrading the save format.
	for prefix in ["best_size", "best_points", "last_catch"]:
		_add_discovery_if_missing(
			record,
			"known_spots",
			"spot_id",
			"spot_name",
			str(record.get(prefix + "_spot_id", "")),
			str(record.get(prefix + "_spot_name", ""))
		)
		_add_discovery_if_missing(
			record,
			"successful_lures",
			"lure_id",
			"lure_name",
			str(record.get(prefix + "_lure_id", "")),
			str(record.get(prefix + "_lure_name", ""))
		)


func _add_discovery_if_missing(
	record: Dictionary,
	field_name: String,
	id_key: String,
	name_key: String,
	entry_id: String,
	entry_name: String
) -> void:
	entry_id = entry_id.strip_edges()
	entry_name = entry_name.strip_edges()
	if entry_id.is_empty():
		return

	var entries: Array[Dictionary] = _sanitize_discovery_entries(
		record.get(field_name, []),
		id_key,
		name_key
	)

	for index in range(entries.size()):
		var existing: Dictionary = entries[index]
		if str(existing.get(id_key, "")) != entry_id:
			continue
		if str(existing.get(name_key, "")).is_empty() and not entry_name.is_empty():
			existing[name_key] = entry_name
			entries[index] = existing
		record[field_name] = entries
		return

	var new_entry: Dictionary = {
		"catch_count": 1,
	}
	new_entry[id_key] = entry_id
	new_entry[name_key] = entry_name
	entries.append(new_entry)
	record[field_name] = entries


func _sanitize_discovery_entries(
	raw_value: Variant,
	id_key: String,
	name_key: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var index_by_id: Dictionary = {}

	if not (raw_value is Array):
		return result

	var raw_entries: Array = raw_value as Array
	for raw_entry in raw_entries:
		if not (raw_entry is Dictionary):
			continue

		var source: Dictionary = raw_entry as Dictionary
		var entry_id: String = str(source.get(id_key, "")).strip_edges()
		if entry_id.is_empty():
			continue

		var entry_name: String = str(source.get(name_key, "")).strip_edges()
		var catch_count: int = maxi(int(source.get("catch_count", 1)), 1)

		if index_by_id.has(entry_id):
			var existing_index: int = int(index_by_id[entry_id])
			var existing: Dictionary = result[existing_index]
			existing["catch_count"] = int(existing.get("catch_count", 0)) + catch_count
			if str(existing.get(name_key, "")).is_empty() and not entry_name.is_empty():
				existing[name_key] = entry_name
			result[existing_index] = existing
			continue

		index_by_id[entry_id] = result.size()
		var sanitized_entry: Dictionary = {
			"catch_count": catch_count,
		}
		sanitized_entry[id_key] = entry_id
		sanitized_entry[name_key] = entry_name
		result.append(sanitized_entry)

	return result


func _record_context_discovery(
	record: Dictionary,
	context: Dictionary
) -> Dictionary:
	var new_spot: bool = _upsert_discovery_entry(
		record,
		"known_spots",
		"spot_id",
		"spot_name",
		str(context.get("spot_id", "")),
		str(context.get("spot_name", ""))
	)
	var new_lure: bool = _upsert_discovery_entry(
		record,
		"successful_lures",
		"lure_id",
		"lure_name",
		str(context.get("lure_id", "")),
		str(context.get("lure_name", ""))
	)

	return {
		"new_spot": new_spot,
		"new_lure": new_lure,
	}


func _upsert_discovery_entry(
	record: Dictionary,
	field_name: String,
	id_key: String,
	name_key: String,
	entry_id: String,
	entry_name: String
) -> bool:
	entry_id = entry_id.strip_edges()
	entry_name = entry_name.strip_edges()
	if entry_id.is_empty():
		return false

	var entries: Array[Dictionary] = _sanitize_discovery_entries(
		record.get(field_name, []),
		id_key,
		name_key
	)

	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		if str(entry.get(id_key, "")) != entry_id:
			continue

		entry["catch_count"] = maxi(int(entry.get("catch_count", 0)), 0) + 1
		if str(entry.get(name_key, "")).is_empty() and not entry_name.is_empty():
			entry[name_key] = entry_name
		entries[index] = entry
		record[field_name] = entries
		return false

	var new_entry: Dictionary = {
		"catch_count": 1,
	}
	new_entry[id_key] = entry_id
	new_entry[name_key] = entry_name
	entries.append(new_entry)
	record[field_name] = entries
	return true


func _sanitize_catch_context(context: Dictionary) -> Dictionary:
	return {
		"spot_id": str(context.get("spot_id", "")),
		"spot_name": str(context.get("spot_name", "")),
		"lure_id": str(context.get("lure_id", "")),
		"lure_name": str(context.get("lure_name", "")),
	}


func _copy_context_to_record(
	record: Dictionary,
	prefix: String,
	context: Dictionary
) -> void:
	record[prefix + "_spot_id"] = str(context.get("spot_id", ""))
	record[prefix + "_spot_name"] = str(context.get("spot_name", ""))
	record[prefix + "_lure_id"] = str(context.get("lure_id", ""))
	record[prefix + "_lure_name"] = str(context.get("lure_name", ""))


func _reset_runtime_state() -> void:
	fishing_points = 0
	total_catches = 0
	species_records.clear()
