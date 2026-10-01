extends RefCounted
class_name TripleTriadCampaignQAHarness

const StarterBundle = preload(
	"res://data/triple_triad/acquisition/bundles/salvaged_card_case.tres"
)

const SCENARIO_FRESH: StringName = &"fresh"
const SCENARIO_STARTER: StringName = &"starter"
const SCENARIO_FIVE_CARD_SAFETY: StringName = &"five_card_safety"
const SCENARIO_EARLY: StringName = &"early"
const SCENARIO_MID: StringName = &"mid"
const SCENARIO_REGIONAL_READY: StringName = &"regional_ready"
const SCENARIO_MASTERS_READY: StringName = &"masters_ready"
const SCENARIO_COLLECTION_170: StringName = &"collection_170"
const SCENARIO_FULL: StringName = &"full"

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

const FIVE_CARD_IDS = [
	"mugshot_156",
	"mugshot_157",
	"mugshot_161",
	"mugshot_153",
	"mugshot_162",
]

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
			"summary": "10 starter cards, Rank 1, unlocked. Deck #1 rebuilds from the real starter collection.",
		},
		{
			"id": String(SCENARIO_FIVE_CARD_SAFETY),
			"name": "Five-Card Safety",
			"summary": "Exactly 5 playable cards. Lose a match to verify the opponent cannot take a sixth card and strand you at four.",
		},
		{
			"id": String(SCENARIO_EARLY),
			"name": "Early Game",
			"summary": "Rank 2, 24 cards, a couple of early NPC wins. Useful for deck growth and rematch testing.",
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
			_seed_collection(_starter_ids(), card_catalog)
			_seed_progression(1)
			_seed_acquisition_unlocked()
		SCENARIO_FIVE_CARD_SAFETY:
			_seed_collection(FIVE_CARD_IDS, card_catalog)
			_seed_progression(1)
			_seed_acquisition_unlocked()
		SCENARIO_EARLY:
			_seed_collection(_cards_for_rank(card_catalog, 2, 24), card_catalog)
			_seed_progression(2)
			_seed_acquisition_unlocked()
			_seed_encounters(PackedStringArray([
				"pier_apprentice",
				"beach_trader",
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


func reset_decks_only() -> Dictionary:
	_delete_with_backup(DECKS_PATH)
	return {
		"success": true,
		"reload_required": true,
	}


func _clear_all_triple_triad_saves() -> void:
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
