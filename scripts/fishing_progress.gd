extends Node
class_name FishingProgress

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

const SAVE_VERSION: int = 1
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


func record_catch(fish: FishInstance) -> Dictionary:
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
	var previous_king_caught := bool(
		record.get("king_caught", false)
	)
	var previous_fishing_points := fishing_points
	var previous_rank_index := get_rank_index(previous_fishing_points)

	record["fish_name"] = fish.species.fish_name
	record["caught_count"] = int(
		record.get("caught_count", 0)
	) + 1

	if fish.size > previous_best_size:
		record["best_size"] = fish.size

	if fish.points > previous_best_points:
		record["best_points"] = fish.points

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
		"new_best_size": (
			fish.size > previous_best_size
		),
		"new_best_points": (
			fish.points > previous_best_points
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
		"next_rank_points": get_next_rank_threshold(fishing_points)
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
	var value := fishing_points if points < 0 else clampi(points, 0, MAX_FISHING_POINTS)
	var index := get_rank_index(value)
	var current_min := int(RANK_TABLE[index]["min_points"])
	var next_threshold := get_next_rank_threshold(value)

	return {
		"index": index,
		"name": str(RANK_TABLE[index]["name"]),
		"points": value,
		"current_min": current_min,
		"next_threshold": next_threshold,
		"is_max_rank": index >= RANK_TABLE.size() - 1,
	}


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

	total_catches = maxi(
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

	# Fishing points are always derived from best species records.
	# Never trust a stale/corrupted cached total from disk.
	_recalculate_fishing_points()

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
		"best_points": 0,
		"king_caught": false,
		"king_count": 0
	}


func _sanitize_record(
	record: Dictionary
) -> Dictionary:
	return {
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
		"best_size": maxf(
			float(
				record.get(
					"best_size",
					0.0
				)
			),
			0.0
		),
		"best_points": maxi(
			int(
				record.get(
					"best_points",
					0
				)
			),
			0
		),
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
		)
	}


func _reset_runtime_state() -> void:
	fishing_points = 0
	total_catches = 0
	species_records.clear()
