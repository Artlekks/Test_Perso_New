extends Node
class_name FishingProgress

const CatchScoring = preload(
	"res://scripts/fishing_catch_scoring.gd"
)
const CatchEvaluator = preload(
	"res://scripts/fishing_catch_evaluator.gd"
)
const DefaultProgressionCatalog: FishingProgressionCatalog = preload(
	"res://data/bof4/progression/all_progression.tres"
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

const SAVE_VERSION: int = 5
const SAVE_PATH: String = "user://fishing_progress.json"

var fishing_points: int = 0
var total_catches: int = 0
var species_records: Dictionary = {}

var progression_catalog: FishingProgressionCatalog = (
	DefaultProgressionCatalog
)

var _initialized: bool = false


func _ready() -> void:
	initialize()


func configure_progression_catalog(
	new_catalog: FishingProgressionCatalog
) -> void:
	if (
		new_catalog == null
		or not new_catalog.is_valid_catalog()
	):
		return

	progression_catalog = new_catalog

	if _initialized:
		_recalculate_fishing_points()
		changed.emit()


func initialize() -> void:
	if _initialized:
		return

	_initialized = true
	load_from_disk()


func record_catch(
	fish: FishInstance,
	catch_context: Dictionary = {}
) -> Dictionary:
	var snapshot: Dictionary = (
		CatchEvaluator.create_snapshot(
			fish,
			catch_context
		)
	)

	return record_catch_snapshot(snapshot)


func record_catch_snapshot(
	snapshot: Dictionary
) -> Dictionary:
	if snapshot.is_empty():
		return {}

	var species_key: String = str(
		snapshot.get("species_id", "")
	).strip_edges().to_lower()

	if species_key.is_empty():
		push_warning(
			"FishingProgress: Catch snapshot has no stable species ID."
		)
		return {}

	var fish_name: String = str(
		snapshot.get("fish_name", "")
	)
	var size: float = float(
		snapshot.get("size", 0.0)
	)
	var points: int = maxi(
		int(snapshot.get("points", 0)),
		0
	)
	var is_king: bool = bool(
		snapshot.get("is_king", false)
	)
	var size_band: String = str(
		snapshot.get("size_band", "normal")
	)
	var score_tier: int = maxi(
		int(snapshot.get("score_tier", 0)),
		0
	)

	var context: Dictionary = _sanitize_catch_context(
		snapshot.get("catch_context", {})
		as Dictionary
	)

	var record: Dictionary = species_records.get(
		species_key,
		_create_empty_record_from_snapshot(snapshot)
	).duplicate(true)

	var previous_caught_count: int = int(
		record.get("caught_count", 0)
	)
	var previous_best_size: float = float(
		record.get("best_size", 0.0)
	)
	var previous_best_points: int = int(
		record.get("best_points", 0)
	)
	var previous_best_points_size: float = float(
		record.get("best_points_size", 0.0)
	)
	var previous_king_caught: bool = bool(
		record.get("king_caught", false)
	)
	var previous_fishing_points: int = fishing_points
	var previous_rank_index: int = get_rank_index(
		previous_fishing_points
	)
	var discovery_result: Dictionary = (
		_record_context_discovery(
			record,
			context
		)
	)

	record["fish_name"] = fish_name
	record["caught_count"] = (
		int(record.get("caught_count", 0))
		+ 1
	)

	if size > previous_best_size:
		record["best_size"] = size
		record["best_size_points"] = points
		record["best_size_score_tier"] = score_tier
		_copy_context_to_record(
			record,
			"best_size",
			context
		)

	var improves_points: bool = (
		points > previous_best_points
	)
	var improves_equal_point_specimen: bool = (
		points == previous_best_points
		and size > previous_best_points_size
	)

	if (
		improves_points
		or improves_equal_point_specimen
	):
		record["best_points"] = points
		record["best_points_size"] = size
		record["best_points_score_tier"] = score_tier
		_copy_context_to_record(
			record,
			"best_points",
			context
		)

	record["last_catch_size"] = size
	record["last_catch_points"] = points
	record["last_catch_is_king"] = is_king
	record["last_catch_size_band"] = size_band
	record["last_catch_score_tier"] = score_tier
	record["last_catch_size_ratio_to_king"] = float(
		snapshot.get(
			"size_ratio_to_king",
			0.0
		)
	)
	_copy_context_to_record(
		record,
		"last_catch",
		context
	)

	if is_king:
		record["king_caught"] = true
		record["king_count"] = (
			int(record.get("king_count", 0))
			+ 1
		)

	species_records[species_key] = record
	total_catches += 1
	_recalculate_fishing_points()

	var current_rank_index: int = get_rank_index(
		fishing_points
	)
	var current_rank_name: String = get_rank_name(
		fishing_points
	)

	var result: Dictionary = {
		"species_key": species_key,
		"record": record.duplicate(true),
		"catch_snapshot": snapshot.duplicate(true),
		"new_species": previous_caught_count <= 0,
		"new_spot_discovery": bool(
			discovery_result.get("new_spot", false)
		),
		"new_lure_discovery": bool(
			discovery_result.get("new_lure", false)
		),
		"new_best_size": size > previous_best_size,
		"new_best_points": improves_points,
		"best_points_record_changed": (
			improves_points
			or improves_equal_point_specimen
		),
		"first_king": (
			is_king
			and not previous_king_caught
		),
		"previous_best_size": previous_best_size,
		"previous_best_points": previous_best_points,
		"fishing_points_before": previous_fishing_points,
		"fishing_points": fishing_points,
		"fishing_points_gained": maxi(
			fishing_points
			- previous_fishing_points,
			0
		),
		"rank_before": get_rank_name(
			previous_fishing_points
		),
		"rank_name": current_rank_name,
		"rank_index": current_rank_index,
		"rank_up": (
			current_rank_index
			> previous_rank_index
		),
		"next_rank_points": get_next_rank_threshold(
			fishing_points
		),
		"catch_context": context.duplicate(true),
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
			"fish_name": fish_name,
			"size": size,
			"points": points,
			"is_king": is_king,
			"size_band": size_band,
			"score_tier": score_tier,
			"spot_id": str(
				context.get("spot_id", "")
			),
			"spot_name": str(
				context.get("spot_name", "")
			),
			"lure_id": str(
				context.get("lure_id", "")
			),
			"lure_name": str(
				context.get("lure_name", "")
			),
		}
	)

	return result


func get_fishing_points() -> int:
	return fishing_points


func get_rank_index(points: int = -1) -> int:
	var value: int = (
		fishing_points
		if points < 0
		else points
	)

	return progression_catalog.get_rank_index(value)


func get_rank_name(points: int = -1) -> String:
	var value: int = (
		fishing_points
		if points < 0
		else points
	)

	return progression_catalog.get_rank_name(value)


func get_rank_id(points: int = -1) -> StringName:
	var value: int = (
		fishing_points
		if points < 0
		else points
	)

	return progression_catalog.get_rank_id(value)


func get_next_rank_threshold(points: int = -1) -> int:
	var value: int = (
		fishing_points
		if points < 0
		else points
	)

	return progression_catalog.get_next_rank_threshold(
		value
	)


func get_rank_progress(points: int = -1) -> Dictionary:
	var value: int = (
		fishing_points
		if points < 0
		else points
	)

	return progression_catalog.get_rank_progress(
		value
	)


func get_progression_snapshot() -> Dictionary:
	var snapshot: Dictionary = get_rank_progress()
	snapshot["total_catches"] = total_catches
	return snapshot


func get_max_fishing_points() -> int:
	return progression_catalog.max_fishing_points


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

	# Pass 2: persistence identity now lives explicitly in FishData instead of
	# being inferred from a filename/display name. All current IDs intentionally
	# match the legacy resource filenames, so existing saves remain compatible.
	var stable_id: String = species.get_stable_species_id()
	if not stable_id.is_empty():
		return stable_id

	return ""


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
			var best_size_score: Dictionary = (
				CatchScoring.evaluate(
					fish,
					best_size
				)
			)
			record["best_size_points"] = int(
				best_size_score.get(
					"points",
					0
				)
			)
			record["best_size_score_tier"] = int(
				best_size_score.get(
					"score_tier",
					0
				)
			)

		if best_points_size <= 0.0 and best_size > 0.0:
			best_points_size = best_size
			record["best_points_size"] = best_points_size
			_copy_record_context(record, "best_size", "best_points")

		var best_points_score: int = 0
		var best_points_score_tier: int = 0

		if best_points_size > 0.0:
			var best_points_details: Dictionary = (
				CatchScoring.evaluate(
					fish,
					best_points_size
				)
			)
			best_points_score = int(
				best_points_details.get(
					"points",
					0
				)
			)
			best_points_score_tier = int(
				best_points_details.get(
					"score_tier",
					0
				)
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
			record["best_points_score_tier"] = int(
				record.get(
					"best_size_score_tier",
					0
				)
			)
			_copy_record_context(record, "best_size", "best_points")
		else:
			record["best_points"] = best_points_score
			record["best_points_score_tier"] = best_points_score_tier

		if last_size > 0.0:
			var last_score: Dictionary = CatchScoring.evaluate(
				fish,
				last_size
			)
			record["last_catch_is_king"] = bool(
				last_score.get("is_king", false)
			)
			record["last_catch_points"] = int(
				last_score.get("points", 0)
			)
			record["last_catch_size_band"] = str(
				last_score.get(
					"size_band",
					&"normal"
				)
			)
			record["last_catch_score_tier"] = int(
				last_score.get(
					"score_tier",
					0
				)
			)
			record["last_catch_size_ratio_to_king"] = float(
				last_score.get(
					"size_ratio_to_king",
					0.0
				)
			)

		if (
			best_size > 0.0
			and CatchScoring.is_king_size(
				fish,
				best_size
			)
		):
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
		get_max_fishing_points()
	)


func _create_empty_record(
	species: FishData
) -> Dictionary:
	return _create_empty_record_from_values(
		(
			species.fish_name
			if species != null
			else ""
		)
	)


func _create_empty_record_from_snapshot(
	snapshot: Dictionary
) -> Dictionary:
	return _create_empty_record_from_values(
		str(snapshot.get("fish_name", ""))
	)


func _create_empty_record_from_values(
	fish_name: String
) -> Dictionary:
	return {
		"fish_name": fish_name,
		"caught_count": 0,
		"best_size": 0.0,
		"best_size_points": 0,
		"best_size_score_tier": 0,
		"best_size_spot_id": "",
		"best_size_spot_name": "",
		"best_size_lure_id": "",
		"best_size_lure_name": "",
		"best_points": 0,
		"best_points_size": 0.0,
		"best_points_score_tier": 0,
		"best_points_spot_id": "",
		"best_points_spot_name": "",
		"best_points_lure_id": "",
		"best_points_lure_name": "",
		"last_catch_size": 0.0,
		"last_catch_points": 0,
		"last_catch_is_king": false,
		"last_catch_size_band": "",
		"last_catch_score_tier": 0,
		"last_catch_size_ratio_to_king": 0.0,
		"last_catch_spot_id": "",
		"last_catch_spot_name": "",
		"last_catch_lure_id": "",
		"last_catch_lure_name": "",
		"king_caught": false,
		"king_count": 0,
		"known_spots": [],
		"successful_lures": [],
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
		"best_size_score_tier": maxi(
			int(record.get("best_size_score_tier", 0)),
			0
		),
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
		"best_points_score_tier": maxi(
			int(record.get("best_points_score_tier", 0)),
			0
		),
		"best_points_spot_id": str(record.get("best_points_spot_id", "")),
		"best_points_spot_name": str(record.get("best_points_spot_name", "")),
		"best_points_lure_id": str(record.get("best_points_lure_id", "")),
		"best_points_lure_name": str(record.get("best_points_lure_name", "")),
		"last_catch_size": float(maxi(roundi(float(record.get("last_catch_size", 0.0))), 0)),
		"last_catch_points": maxi(int(record.get("last_catch_points", 0)), 0),
		"last_catch_is_king": bool(record.get("last_catch_is_king", false)),
		"last_catch_size_band": str(
			record.get("last_catch_size_band", "")
		),
		"last_catch_score_tier": maxi(
			int(record.get("last_catch_score_tier", 0)),
			0
		),
		"last_catch_size_ratio_to_king": maxf(
			float(
				record.get(
					"last_catch_size_ratio_to_king",
					0.0
				)
			),
			0.0
		),
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
