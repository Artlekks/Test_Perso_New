extends RefCounted
class_name TripleTriadCampaignQAHarness

const StarterBundle = preload(
	"res://data/triple_triad/acquisition/bundles/salvaged_card_case.tres"
)

const WORLD_ACQUISITION_MAP_PATH := (
	"res://data/triple_triad/acquisition/world_acquisition_map.json"
)
const EARLY_PROGRESSION_PLAN_PATH := (
	"res://data/triple_triad/acquisition/early_progression_plan_v1.json"
)

const SCENARIO_FRESH: StringName = &"fresh"
const SCENARIO_STARTER: StringName = &"starter"
const SCENARIO_LEARN_LOOP: StringName = &"learn_loop"
const SCENARIO_FIVE_CARD_SAFETY: StringName = &"five_card_safety"
const SCENARIO_EARLY: StringName = &"early"
const SCENARIO_SPECIALIZATION: StringName = &"specialization"
const SCENARIO_MID: StringName = &"mid"
const SCENARIO_REGIONAL_READY: StringName = &"regional_ready"
const SCENARIO_MASTERS_READY: StringName = &"masters_ready"
const SCENARIO_COLLECTION_170: StringName = &"collection_170"
const SCENARIO_FULL: StringName = &"full"
const SCENARIO_SIX_CARD_RECOVERY: StringName = &"six_card_recovery"
const SCENARIO_VETERAN_REMATCH: StringName = &"veteran_rematch"
const SCENARIO_REGIONAL_RESUME: StringName = &"regional_resume"

const COLLECTION_PATH := "user://triple_triad_collection.cfg"
const OPPONENTS_PATH := "user://triple_triad_opponents.cfg"
const DECKS_PATH := "user://triple_triad_decks.cfg"
const PROGRESSION_PATH := "user://triple_triad_progression.cfg"
const TRANSFER_JOURNAL_PATH := "user://triple_triad_transfer_journal.cfg"
const MATCH_RESOLUTION_PATH := "user://triple_triad_match_resolution.cfg"
const ACQUISITION_HISTORY_PATH := "user://triple_triad_acquisition_history.cfg"
const ACQUISITION_STATE_PATH := "user://triple_triad_acquisition_state.cfg"
const ENCOUNTER_RECORDS_PATH := "user://triple_triad_encounter_records.cfg"
const WORLD_DELIVERY_PATH := "user://triple_triad_world_delivery.cfg"
const COMPETITIONS_PATH := "user://triple_triad_competitions.cfg"
const COMPLETION_PATH := "user://triple_triad_completion.cfg"
const MANIFEST_PATH := "user://triple_triad_save_manifest.cfg"
const QA_SNAPSHOT_PATH := "user://triple_triad_qa_snapshot_A.json"

const ALL_OPPONENT_IDS = [
	"pier_apprentice",
	"beach_trader",
	"dock_bruiser",
	"gearwright",
	"marsh_keeper",
	"highland_keeper",
	"lantern_gambler",
	"tide_oracle",
	"wandering_sage",
	"storm_captain",
	"ash_champion",
]

const REGIONAL_CIRCUIT_OPPONENTS = [
	"pier_apprentice",
	"beach_trader",
	"dock_bruiser",
	"gearwright",
	"marsh_keeper",
	"highland_keeper",
	"lantern_gambler",
	"tide_oracle",
]


func get_scenarios() -> Array:
	return [
		{
			"id": String(SCENARIO_FRESH),
			"name": "Fresh / Undiscovered",
			"summary": "0 cards, Rank 1, card game locked. Your next eligible Ocean 2 catch discovers the Saltworn Card Case.",
		},
		{
			"id": String(SCENARIO_STARTER),
			"name": "Starter / Just Unlocked",
			"summary": "5 starter cards, Rank 1, unlocked. Deck #1 rebuilds from the real Saltworn Card Case.",
		},
		{
			"id": String(SCENARIO_LEARN_LOOP),
			"name": "Hour 1 / Learn Loop",
			"summary": "Rank 1 with 8 reachable cards from the real 13-card first-hour pool; Beach Trader has been beaten once.",
		},
		{
			"id": String(SCENARIO_FIVE_CARD_SAFETY),
			"name": "Five-Card Safety",
			"summary": "Exactly 5 playable cards. Lose a match to verify the opponent cannot take a sixth card and strand you at four.",
		},
		{
			"id": String(SCENARIO_SIX_CARD_RECOVERY),
			"name": "Six-Card Loss / Recovery",
			"summary": "Exactly 6 reachable early cards: the five-card starter deck plus one earned card. Lose once, then rematch to test recovery.",
		},
		{
			"id": String(SCENARIO_VETERAN_REMATCH),
			"name": "Veteran Rematch Ready",
			"summary": "Rank 2 with six recorded wins against Dock Bruiser. His Stage-3 evolved deck/AI is immediately testable.",
		},
		{
			"id": String(SCENARIO_EARLY),
			"name": "Hour 4 / Connected Systems",
			"summary": "Rank 2 with 20 reachable cards from the real 24-card first-four-hour pool; Beach Trader, Pier Apprentice and Gearwright are cleared.",
		},
		{
			"id": String(SCENARIO_SPECIALIZATION),
			"name": "Hour 12 / Specialization",
			"summary": "Rank 2 with 35 reachable cards from the real 40-card first-twelve-hour pool; deeper coast salvage and the Rank-2 ladder are active.",
		},
		{
			"id": String(SCENARIO_MID),
			"name": "Mid Game",
			"summary": "Rank 3, 60 cards, early circuits partly cleared. Useful for acquisition and evolving-NPC testing.",
		},
		{
			"id": String(SCENARIO_REGIONAL_READY),
			"name": "Regional Championship Ready",
			"summary": "Rank 3 with all three regional circuits cleared. Regional Championship is ready to enter.",
		},
		{
			"id": String(SCENARIO_REGIONAL_RESUME),
			"name": "Regional Round 2 Resume",
			"summary": "A Regional Championship run is already active at round 2 with a locked five-card deck. Tests reload/resume continuity.",
		},
		{
			"id": String(SCENARIO_MASTERS_READY),
			"name": "Masters' Cup Ready",
			"summary": "Rank 5 with one Regional Championship clear. Masters' Cup is ready to enter.",
		},
		{
			"id": String(SCENARIO_COLLECTION_170),
			"name": "Collection 170 / 179",
			"summary": "Card Master state with exactly nine cards missing. Tests endgame collection cleanup and source diagnostics.",
		},
		{
			"id": String(SCENARIO_FULL),
			"name": "Full Completion",
			"summary": "Rank 6, 179 / 179 cards, all opponents beaten, Regional + Masters cleared.",
		},
	]


func apply_scenario(
	scenario_id: StringName,
	card_catalog: Resource
) -> Dictionary:
	if card_catalog == null:
		return {
			"success": false,
			"reason": "card_catalog_unavailable",
		}

	_clear_all_triple_triad_saves()

	match scenario_id:
		SCENARIO_FRESH:
			# No authored files are needed. New-save initialization is the test.
			pass
		SCENARIO_STARTER:
			_seed_collection(
				_primary_pool_for_stage(&"starter_deck", card_catalog),
				card_catalog
			)
			_seed_progression(1)
			_seed_acquisition_unlocked()
		SCENARIO_LEARN_LOOP:
			_seed_collection(
				_take_ids(
					_primary_pool_for_stage(&"learn_loop", card_catalog),
					8
				),
				card_catalog
			)
			_seed_progression(1)
			_seed_acquisition_unlocked()
			_seed_encounters(PackedStringArray(["beach_trader"]))
		SCENARIO_FIVE_CARD_SAFETY:
			_seed_collection(_starter_ids(), card_catalog)
			_seed_progression(1)
			_seed_acquisition_unlocked()
		SCENARIO_SIX_CARD_RECOVERY:
			var six_ids: PackedStringArray = _take_ids(
				_primary_pool_for_stage(&"learn_loop", card_catalog),
				6
			)
			_seed_collection(six_ids, card_catalog)
			_seed_progression(1)
			_seed_acquisition_unlocked()
			_seed_encounters(PackedStringArray(["beach_trader"]))
		SCENARIO_VETERAN_REMATCH:
			_seed_collection(
				_take_ids(
					_primary_pool_for_stage(&"specialization", card_catalog),
					32
				),
				card_catalog
			)
			_seed_progression(2)
			_seed_acquisition_unlocked()
			_seed_encounters_with_wins({
				"beach_trader": 1,
				"pier_apprentice": 1,
				"gearwright": 1,
				"dock_bruiser": 6,
			})
		SCENARIO_EARLY:
			_seed_collection(
				_take_ids(
					_primary_pool_for_stage(&"connected_systems", card_catalog),
					20
				),
				card_catalog
			)
			_seed_progression(2)
			_seed_acquisition_unlocked()
			_seed_encounters(PackedStringArray([
				"beach_trader",
				"pier_apprentice",
				"gearwright",
			]))
		SCENARIO_SPECIALIZATION:
			_seed_collection(
				_take_ids(
					_primary_pool_for_stage(&"specialization", card_catalog),
					35
				),
				card_catalog
			)
			_seed_progression(2)
			_seed_acquisition_unlocked()
			_seed_encounters(PackedStringArray([
				"beach_trader",
				"pier_apprentice",
				"gearwright",
				"dock_bruiser",
				"marsh_keeper",
			]))
		SCENARIO_MID:
			_seed_collection(_cards_for_rank(card_catalog, 3, 60), card_catalog)
			_seed_progression(3)
			_seed_acquisition_unlocked()
			_seed_encounters(PackedStringArray([
				"pier_apprentice",
				"beach_trader",
				"dock_bruiser",
				"gearwright",
				"marsh_keeper",
			]))
		SCENARIO_REGIONAL_READY:
			_seed_collection(_cards_for_rank(card_catalog, 3, 85), card_catalog)
			_seed_progression(3)
			_seed_acquisition_unlocked()
			_seed_encounters(REGIONAL_CIRCUIT_OPPONENTS)
		SCENARIO_REGIONAL_RESUME:
			_seed_collection(_cards_for_rank(card_catalog, 3, 85), card_catalog)
			_seed_progression(3)
			_seed_acquisition_unlocked()
			_seed_encounters(REGIONAL_CIRCUIT_OPPONENTS)
			_seed_active_regional_round_two()
		SCENARIO_MASTERS_READY:
			_seed_collection(_cards_for_rank(card_catalog, 5, 125), card_catalog)
			_seed_progression(5)
			_seed_acquisition_unlocked()
			_seed_encounters(REGIONAL_CIRCUIT_OPPONENTS)
			_seed_competitions(1, 0)
		SCENARIO_COLLECTION_170:
			_seed_collection(_cards_for_rank(card_catalog, 10, 170), card_catalog)
			_seed_progression(6)
			_seed_acquisition_unlocked()
			_seed_encounters(ALL_OPPONENT_IDS)
			_seed_competitions(1, 1)
		SCENARIO_FULL:
			_seed_collection(_all_card_ids(card_catalog), card_catalog)
			_seed_progression(6)
			_seed_acquisition_unlocked()
			_seed_encounters(ALL_OPPONENT_IDS)
			_seed_competitions(1, 1)
		_:
			return {
				"success": false,
				"reason": "unknown_scenario",
				"scenario_id": String(scenario_id),
			}

	return {
		"success": true,
		"scenario_id": String(scenario_id),
		"reload_required": true,
	}


func save_qa_snapshot() -> Dictionary:
	var files: Array = []
	for path in _managed_save_paths(true):
		if not FileAccess.file_exists(path):
			continue
		files.append({
			"path": path,
			"content": FileAccess.get_file_as_string(path),
		})

	var payload := {
		"version": 1,
		"created_unix": int(Time.get_unix_time_from_system()),
		"files": files,
	}
	var file := FileAccess.open(QA_SNAPSHOT_PATH, FileAccess.WRITE)
	if file == null:
		return {
			"success": false,
			"reason": "snapshot_open_failed",
		}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return {
		"success": true,
		"file_count": files.size(),
		"path": QA_SNAPSHOT_PATH,
		"created_unix": int(payload["created_unix"]),
	}


func restore_qa_snapshot() -> Dictionary:
	if not FileAccess.file_exists(QA_SNAPSHOT_PATH):
		return {
			"success": false,
			"reason": "snapshot_missing",
		}

	var parsed = JSON.parse_string(
		FileAccess.get_file_as_string(QA_SNAPSHOT_PATH)
	)
	if not (parsed is Dictionary):
		return {
			"success": false,
			"reason": "snapshot_invalid",
		}
	var payload: Dictionary = parsed
	var raw_files = payload.get("files", [])
	if not (raw_files is Array):
		return {
			"success": false,
			"reason": "snapshot_files_invalid",
		}

	_clear_all_triple_triad_saves()
	var restored: int = 0
	for raw_entry in raw_files:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var path: String = str(entry.get("path", ""))
		if not _is_managed_save_path(path):
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(str(entry.get("content", "")))
		file.close()
		restored += 1

	return {
		"success": true,
		"restored_files": restored,
		"created_unix": int(payload.get("created_unix", 0)),
		"reload_required": true,
	}


func delete_qa_snapshot() -> Dictionary:
	if FileAccess.file_exists(QA_SNAPSHOT_PATH):
		var delete_error: Error = DirAccess.remove_absolute(QA_SNAPSHOT_PATH)
		return {
			"success": delete_error == OK,
			"error": error_string(delete_error) if delete_error != OK else "",
		}
	return {
		"success": true,
		"already_missing": true,
	}


func get_qa_snapshot_info() -> Dictionary:
	if not FileAccess.file_exists(QA_SNAPSHOT_PATH):
		return {
			"exists": false,
			"path": QA_SNAPSHOT_PATH,
		}
	var parsed = JSON.parse_string(
		FileAccess.get_file_as_string(QA_SNAPSHOT_PATH)
	)
	if not (parsed is Dictionary):
		return {
			"exists": true,
			"valid": false,
			"path": QA_SNAPSHOT_PATH,
		}
	var payload: Dictionary = parsed
	var files = payload.get("files", [])
	return {
		"exists": true,
		"valid": files is Array,
		"path": QA_SNAPSHOT_PATH,
		"created_unix": int(payload.get("created_unix", 0)),
		"file_count": files.size() if files is Array else 0,
	}


func get_managed_save_paths() -> PackedStringArray:
	var result := PackedStringArray()
	for path in _managed_save_paths(true):
		result.append(path)
	return result


func reset_decks_only() -> Dictionary:
	_delete_with_backup(DECKS_PATH)
	return {
		"success": true,
		"reload_required": true,
	}


func _managed_save_paths(include_backups: bool) -> Array:
	var result: Array = []
	for path in [
		COLLECTION_PATH,
		OPPONENTS_PATH,
		DECKS_PATH,
		PROGRESSION_PATH,
		TRANSFER_JOURNAL_PATH,
		MATCH_RESOLUTION_PATH,
		ACQUISITION_HISTORY_PATH,
		ACQUISITION_STATE_PATH,
		ENCOUNTER_RECORDS_PATH,
		WORLD_DELIVERY_PATH,
		COMPETITIONS_PATH,
		COMPLETION_PATH,
		MANIFEST_PATH,
	]:
		result.append(path)
		if include_backups:
			result.append("%s.bak" % path)
	return result


func _is_managed_save_path(path: String) -> bool:
	return _managed_save_paths(true).has(path)


func _clear_all_triple_triad_saves() -> void:
	for path in _managed_save_paths(false):
		_delete_with_backup(path)


func _delete_with_backup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var backup: String = "%s.bak" % path
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)


func _seed_collection(card_ids, card_catalog: Resource) -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 3)
	if card_ids is PackedStringArray or card_ids is Array:
		for raw_id in card_ids:
			var card_id := StringName(str(raw_id))
			if card_catalog.has_method("get_card_by_id"):
				if card_catalog.call("get_card_by_id", card_id) == null:
					continue
			config.set_value("cards", String(card_id), 1)
	config.save(COLLECTION_PATH)


func _seed_progression(rank_number: int) -> void:
	var rank_points := {
		1: 0,
		2: 6,
		3: 15,
		4: 30,
		5: 50,
		6: 80,
	}
	var clean_rank: int = clampi(rank_number, 1, 6)
	var config := ConfigFile.new()
	config.set_value("progression", "version", 2)
	config.set_value(
		"progression",
		"points",
		int(rank_points.get(clean_rank, 0))
	)
	config.set_value("progression", "matches", 0)
	config.set_value("progression", "wins", 0)
	config.set_value("progression", "losses", 0)
	config.set_value("progression", "draws", 0)
	config.save(PROGRESSION_PATH)


func _seed_acquisition_unlocked() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("meta", "card_game_unlocked", true)
	config.set_value("claimed", "salvaged_card_case", true)
	config.save(ACQUISITION_STATE_PATH)


func _seed_encounters_with_wins(wins_by_opponent: Dictionary) -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	for raw_id in wins_by_opponent.keys():
		var opponent_id: String = str(raw_id)
		var wins: int = maxi(0, int(wins_by_opponent[raw_id]))
		var section: String = "opponent_%s_record" % opponent_id
		config.set_value(section, "matches", wins)
		config.set_value(section, "wins", wins)
		config.set_value(section, "losses", 0)
		config.set_value(section, "draws", 0)
		config.set_value(section, "first_win_unix", 1 if wins > 0 else 0)
		config.set_value(section, "last_result", "win" if wins > 0 else "")
		config.set_value(section, "last_played_unix", 1 if wins > 0 else 0)
		config.set_value(section, "cards_won_from_opponent", 0)
		config.set_value(section, "cards_lost_to_opponent", 0)
		config.set_value(section, "stolen_cards_recovered", 0)
	config.save(ENCOUNTER_RECORDS_PATH)


func _seed_active_regional_round_two() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 3)
	for competition_id in [
		"regional_championship",
		"masters_cup",
	]:
		config.set_value("attempts", competition_id, 0)
		config.set_value("clears", competition_id, 0)
		config.set_value("failures", competition_id, 0)
		config.set_value("abandons", competition_id, 0)
	config.set_value("attempts", "regional_championship", 1)
	config.set_value(
		"active",
		"competition_id",
		"regional_championship"
	)
	config.set_value("active", "round_index", 1)
	config.set_value(
		"active",
		"locked_deck_ids",
		_starter_ids()
	)
	config.save(COMPETITIONS_PATH)


func _seed_encounters(opponent_ids) -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	if opponent_ids is PackedStringArray or opponent_ids is Array:
		for raw_id in opponent_ids:
			var opponent_id: String = str(raw_id)
			var section: String = "opponent_%s_record" % opponent_id
			config.set_value(section, "matches", 1)
			config.set_value(section, "wins", 1)
			config.set_value(section, "losses", 0)
			config.set_value(section, "draws", 0)
			config.set_value(section, "first_win_unix", 1)
			config.set_value(section, "last_result", "win")
			config.set_value(section, "last_played_unix", 1)
			config.set_value(section, "cards_won_from_opponent", 0)
			config.set_value(section, "cards_lost_to_opponent", 0)
			config.set_value(section, "stolen_cards_recovered", 0)
	config.save(ENCOUNTER_RECORDS_PATH)


func _seed_competitions(
	regional_clears: int,
	masters_clears: int
) -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 3)
	for competition_id in [
		"regional_championship",
		"masters_cup",
	]:
		config.set_value("attempts", competition_id, 0)
		config.set_value("failures", competition_id, 0)
		config.set_value("abandons", competition_id, 0)
	config.set_value(
		"clears",
		"regional_championship",
		maxi(0, regional_clears)
	)
	config.set_value(
		"clears",
		"masters_cup",
		maxi(0, masters_clears)
	)
	config.set_value("active", "competition_id", "")
	config.set_value("active", "round_index", 0)
	config.set_value(
		"active",
		"locked_deck_ids",
		PackedStringArray()
	)
	config.save(COMPETITIONS_PATH)


func validate_progression_alignment(card_catalog: Resource) -> Dictionary:
	var errors := PackedStringArray()
	if card_catalog == null:
		errors.append("card_catalog_unavailable")
		return {
			"valid": false,
			"errors": errors,
			"pool_sizes": PackedInt32Array(),
		}

	var stage_ids := PackedStringArray([
		"starter_deck",
		"learn_loop",
		"connected_systems",
		"specialization",
	])
	var expected_sizes := PackedInt32Array([5, 13, 24, 40])
	var pool_sizes := PackedInt32Array()
	var pools: Array = []
	for stage_id in stage_ids:
		var pool: PackedStringArray = _primary_pool_for_stage(
			StringName(stage_id),
			card_catalog
		)
		pools.append(pool)
		pool_sizes.append(pool.size())

	if pool_sizes != expected_sizes:
		errors.append(
			"early primary pools are %s, expected 5/13/24/40"
			% str(pool_sizes)
		)

	var starter_ids: PackedStringArray = _starter_ids()
	if pools.is_empty() or not _same_id_set(pools[0], starter_ids):
		errors.append(
			"starter QA preset does not mirror salvaged_card_case"
		)

	var scenario_targets := PackedInt32Array([5, 8, 20, 35])
	for index in range(mini(pools.size(), scenario_targets.size())):
		var seeded: PackedStringArray = _take_ids(
			pools[index],
			scenario_targets[index]
		)
		if seeded.size() != scenario_targets[index]:
			errors.append(
				"scenario %s cannot seed %d reachable cards"
				% [stage_ids[index], scenario_targets[index]]
			)

	var six_card_recovery: PackedStringArray = _take_ids(
		pools[1] if pools.size() > 1 else PackedStringArray(),
		6
	)
	if six_card_recovery.size() != 6:
		errors.append(
			"six-card recovery preset cannot seed six reachable cards"
		)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"pool_sizes": pool_sizes,
		"scenario_targets": scenario_targets,
		"six_card_recovery_count": six_card_recovery.size(),
	}


func _primary_pool_for_stage(
	stage_id: StringName,
	card_catalog: Resource
) -> PackedStringArray:
	var plan: Dictionary = _load_json_dictionary(
		EARLY_PROGRESSION_PLAN_PATH
	)
	var world_map: Dictionary = _load_json_dictionary(
		WORLD_ACQUISITION_MAP_PATH
	)
	if plan.is_empty() or world_map.is_empty():
		return PackedStringArray()

	var source_cards: Dictionary = {}
	var raw_sources = world_map.get("sources", [])
	if raw_sources is Array:
		for raw_source in raw_sources:
			if not (raw_source is Dictionary):
				continue
			var source: Dictionary = raw_source
			var source_type: String = str(
				source.get("source_type", "")
			)
			var source_id: String = str(
				source.get("source_id", "")
			)
			if source_type.is_empty() or source_id.is_empty():
				continue
			source_cards["%s:%s" % [source_type, source_id]] = (
				source.get("card_ids", [])
			)

	var result := PackedStringArray()
	var found_stage: bool = false
	var raw_stages = plan.get("stages", [])
	if not (raw_stages is Array):
		return result
	for raw_stage in raw_stages:
		if not (raw_stage is Dictionary):
			continue
		var stage: Dictionary = raw_stage
		var raw_new_sources = stage.get("new_sources", [])
		if raw_new_sources is Array:
			for raw_ref in raw_new_sources:
				if not (raw_ref is Dictionary):
					continue
				var source_ref: Dictionary = raw_ref
				var key: String = "%s:%s" % [
					str(source_ref.get("source_type", "")),
					str(source_ref.get("source_id", "")),
				]
				var raw_ids = source_cards.get(key, [])
				if raw_ids is Array or raw_ids is PackedStringArray:
					for raw_id in raw_ids:
						var card_id: String = str(raw_id)
						if card_id.is_empty() or result.has(card_id):
							continue
						if (
							card_catalog.has_method("get_card_by_id")
							and card_catalog.call(
								"get_card_by_id",
								StringName(card_id)
							) == null
						):
							continue
						result.append(card_id)
		if str(stage.get("stage_id", "")) == String(stage_id):
			found_stage = true
			break

	if not found_stage:
		return PackedStringArray()
	return result


func _take_ids(ids: PackedStringArray, target_count: int) -> PackedStringArray:
	var result := ids.duplicate()
	var clean_target: int = maxi(0, target_count)
	if result.size() > clean_target:
		result.resize(clean_target)
	return result


func _same_id_set(a: PackedStringArray, b: PackedStringArray) -> bool:
	if a.size() != b.size():
		return false
	for card_id in a:
		if not b.has(card_id):
			return false
	return true


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func _starter_ids() -> PackedStringArray:
	var result := PackedStringArray()
	if StarterBundle == null:
		return result
	var raw_ids = StarterBundle.get("card_ids")
	if raw_ids is PackedStringArray or raw_ids is Array:
		for raw_id in raw_ids:
			result.append(str(raw_id))
	return result


func _all_card_ids(card_catalog: Resource) -> PackedStringArray:
	var result := PackedStringArray()
	if not card_catalog.has_method("get_total_source_count"):
		return result
	for index in range(
		int(card_catalog.call("get_total_source_count"))
	):
		var card = card_catalog.call("get_card", index)
		if card != null:
			result.append(String(card.card_id))
	return result


func _cards_for_rank(
	card_catalog: Resource,
	max_rank: int,
	target_count: int
) -> PackedStringArray:
	var result := PackedStringArray()

	# Always seed the starter set first when possible.
	for starter_id in _starter_ids():
		if not result.has(starter_id):
			result.append(starter_id)

	var candidates: Array = []
	if card_catalog.has_method("get_total_source_count"):
		for index in range(
			int(card_catalog.call("get_total_source_count"))
		):
			var card = card_catalog.call("get_card", index)
			if card == null:
				continue
			if int(card.required_player_rank) > maxi(1, max_rank):
				continue
			candidates.append(card)

	candidates.sort_custom(func(a, b):
		if int(a.required_player_rank) != int(b.required_player_rank):
			return int(a.required_player_rank) < int(b.required_player_rank)
		return int(a.source_index) < int(b.source_index)
	)

	for card in candidates:
		var card_id: String = String(card.card_id)
		if not result.has(card_id):
			result.append(card_id)
		if result.size() >= target_count:
			break

	# Endgame QA profiles must hit their requested exact count even if a future
	# content rebalance changes rank gates.
	if result.size() < target_count:
		for card_id in _all_card_ids(card_catalog):
			if not result.has(card_id):
				result.append(card_id)
			if result.size() >= target_count:
				break

	if result.size() > target_count:
		result.resize(target_count)
	return result
