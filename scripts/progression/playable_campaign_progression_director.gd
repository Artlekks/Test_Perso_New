extends Node
class_name PlayableCampaignProgressionDirector

## Read-only campaign progression composer for the current playable vertical slice.
##
## This service does not grant rewards, unlock content, mutate rank, or persist
## campaign state. It reads the systems that already own those facts and turns
## them into one stable snapshot for QA, developer guidance, and future player UI.

const ProgressionPolicyScript = preload(
	"res://scripts/progression/playable_campaign_progression_policy.gd"
)

const PLAN_PATH := "res://data/progression/playable_campaign_loop_v1.json"
const STARTER_BUNDLE_ID := "salvaged_card_case"
const HARBOR_LOCKBOX_EVENT_ID := "beach_demo_harbor_lockbox_01"
const HARBOR_REQUEST_EVENT_ID := "beach_demo_harbor_errand_01"
const REGIONAL_CHAMPIONSHIP_ID := "regional_championship"
const KEY_OPPONENT_IDS := [
	"beach_trader",
	"pier_apprentice",
	"gearwright",
	"dock_bruiser",
	"marsh_keeper",
]

var fishing_progress = null
var fishing_inventory = null
var fishing_unlock_state = null
var prepared_bait_service = null
var card_maker_service = null
var _plan: Dictionary = {}
var _cached_triple_triad_game: Node = null


func configure(
	new_fishing_progress,
	new_fishing_inventory,
	new_fishing_unlock_state = null,
	new_prepared_bait_service = null,
	new_card_maker_service = null
) -> void:
	fishing_progress = new_fishing_progress
	fishing_inventory = new_fishing_inventory
	fishing_unlock_state = new_fishing_unlock_state
	prepared_bait_service = new_prepared_bait_service
	card_maker_service = new_card_maker_service
	_plan = _load_json(PLAN_PATH)


func get_snapshot() -> Dictionary:
	if _plan.is_empty():
		_plan = _load_json(PLAN_PATH)
	return build_snapshot_from_state(
		_plan,
		_collect_runtime_state()
	)


func get_plan_snapshot() -> Dictionary:
	if _plan.is_empty():
		_plan = _load_json(PLAN_PATH)
	return _plan.duplicate(true)


func invalidate_triple_triad_provider() -> void:
	_cached_triple_triad_game = null


func _collect_runtime_state() -> Dictionary:
	var total_catches: int = 0
	var species_ids := PackedStringArray()
	if fishing_progress != null:
		if fishing_progress.has_method("get_total_catches"):
			total_catches = maxi(
				0,
				int(fishing_progress.call("get_total_catches"))
			)
		if fishing_progress.has_method("get_all_records"):
			var records = fishing_progress.call("get_all_records")
			if records is Dictionary:
				for raw_species_id in (records as Dictionary).keys():
					var raw_record = (records as Dictionary).get(raw_species_id, {})
					if (
						raw_record is Dictionary
						and int((raw_record as Dictionary).get("caught_count", 0)) > 0
					):
						species_ids.append(str(raw_species_id))
			species_ids.sort()

	var zenny: int = 0
	var rod_ids := PackedStringArray()
	var lure_ids := PackedStringArray()
	if fishing_inventory != null:
		if fishing_inventory.has_method("get_zenny"):
			zenny = maxi(0, int(fishing_inventory.call("get_zenny")))
		if fishing_inventory.has_method("get_owned_rod_ids"):
			var raw_rods = fishing_inventory.call("get_owned_rod_ids")
			if raw_rods is PackedStringArray or raw_rods is Array:
				for raw_rod in raw_rods:
					rod_ids.append(str(raw_rod))
		if fishing_inventory.has_method("get_owned_lure_ids"):
			var raw_lures = fishing_inventory.call("get_owned_lure_ids")
			if raw_lures is PackedStringArray or raw_lures is Array:
				for raw_lure in raw_lures:
					lure_ids.append(str(raw_lure))
	rod_ids.sort()
	lure_ids.sort()

	var prepared_bait_snapshot: Dictionary = {}
	if (
		prepared_bait_service != null
		and prepared_bait_service.has_method("get_runtime_snapshot")
	):
		var raw_bait = prepared_bait_service.call("get_runtime_snapshot")
		if raw_bait is Dictionary:
			prepared_bait_snapshot = (raw_bait as Dictionary).duplicate(true)

	var card_state: Dictionary = _collect_card_state()
	var card_maker_recipe_statuses: Array = []
	if card_maker_service != null and card_state.get("backend_available", false):
		if card_maker_service.has_method("get_all_recipe_snapshots"):
			var raw_recipes = card_maker_service.call("get_all_recipe_snapshots")
			if raw_recipes is Array:
				for raw_recipe in raw_recipes:
					if raw_recipe is Dictionary:
						card_maker_recipe_statuses.append(
							(raw_recipe as Dictionary).duplicate(true)
						)

	var fishing_flags := PackedStringArray()
	if (
		fishing_unlock_state != null
		and fishing_unlock_state.has_method("get_all_flags")
	):
		var raw_flags = fishing_unlock_state.call("get_all_flags")
		if raw_flags is PackedStringArray or raw_flags is Array:
			for raw_flag in raw_flags:
				fishing_flags.append(str(raw_flag))
	fishing_flags.sort()

	return {
		"zenny": zenny,
		"total_catches": total_catches,
		"species_discovered": species_ids.size(),
		"species_ids": species_ids,
		"rods_owned": rod_ids.size(),
		"rod_ids": rod_ids,
		"lures_owned": lure_ids.size(),
		"lure_ids": lure_ids,
		"fishing_unlock_flags": fishing_flags,
		"prepared_bait": prepared_bait_snapshot,
		"card_maker_recipe_statuses": card_maker_recipe_statuses,
		"card_state": card_state,
	}


func _collect_card_state() -> Dictionary:
	var result := {
		"backend_available": false,
		"card_game_unlocked": false,
		"starter_case_discovered": false,
		"cards_owned_unique": 0,
		"cards_owned_total": 0,
		"duel_rank": 1,
		"duel_points": 0,
		"matches": 0,
		"wins": 0,
		"beaten_opponent_ids": PackedStringArray(),
		"opponents": {},
		"claimed_world_event_ids": PackedStringArray(),
		"pending_world_reward_count": 0,
		"active_competition": {},
		"regional_championship": {},
		"world_progression": {},
		"source_acquisition_counts": {},
	}
	var game: Node = _find_triple_triad_game()
	if game == null:
		return result

	result["backend_available"] = true

	var player_snapshot: Dictionary = {}
	if game.has_method("get_player_snapshot"):
		var raw_player = game.call("get_player_snapshot")
		if raw_player is Dictionary:
			player_snapshot = (raw_player as Dictionary).duplicate(true)
	result["card_game_unlocked"] = bool(
		player_snapshot.get("card_game_unlocked", false)
	)
	result["cards_owned_unique"] = maxi(
		0,
		int(player_snapshot.get("owned_unique_cards", 0))
	)
	result["cards_owned_total"] = maxi(
		0,
		int(player_snapshot.get("owned_total_cards", 0))
	)
	result["duel_rank"] = maxi(1, int(player_snapshot.get("duel_rank", 1)))
	result["duel_points"] = maxi(0, int(player_snapshot.get("duel_points", 0)))
	result["matches"] = maxi(0, int(player_snapshot.get("matches", 0)))
	result["wins"] = maxi(0, int(player_snapshot.get("wins", 0)))

	var acquisition_snapshot: Dictionary = {}
	if game.has_method("get_acquisition_snapshot"):
		var raw_acquisition = game.call("get_acquisition_snapshot")
		if raw_acquisition is Dictionary:
			acquisition_snapshot = (raw_acquisition as Dictionary).duplicate(true)
	result["card_game_unlocked"] = bool(
		acquisition_snapshot.get(
			"card_game_unlocked",
			result.get("card_game_unlocked", false)
		)
	)
	result["starter_case_discovered"] = _list_has_string(
		acquisition_snapshot.get("claimed_bundle_ids", []),
		STARTER_BUNDLE_ID
	)

	var opponents: Dictionary = {}
	var beaten_ids := PackedStringArray()
	if game.has_method("get_opponent_snapshot"):
		for opponent_id in KEY_OPPONENT_IDS:
			var raw_opponent = game.call(
				"get_opponent_snapshot",
				StringName(str(opponent_id))
			)
			if not (raw_opponent is Dictionary):
				continue
			var opponent: Dictionary = (raw_opponent as Dictionary).duplicate(true)
			opponents[str(opponent_id)] = opponent
			if bool(opponent.get("beaten_before", false)):
				beaten_ids.append(str(opponent_id))
	beaten_ids.sort()
	result["opponents"] = opponents
	result["beaten_opponent_ids"] = beaten_ids

	if game.has_method("get_world_reward_delivery_snapshot"):
		var raw_delivery = game.call("get_world_reward_delivery_snapshot")
		if raw_delivery is Dictionary:
			var delivery: Dictionary = raw_delivery
			var claimed_ids := PackedStringArray()
			var raw_claimed = delivery.get("claimed_event_ids", [])
			if raw_claimed is PackedStringArray or raw_claimed is Array:
				for raw_id in raw_claimed:
					claimed_ids.append(str(raw_id))
			claimed_ids.sort()
			result["claimed_world_event_ids"] = claimed_ids
			var pending = delivery.get("pending_deliveries", [])
			if pending is Array:
				result["pending_world_reward_count"] = pending.size()

	if game.has_method("get_competitive_snapshot"):
		var raw_competitive = game.call("get_competitive_snapshot")
		if raw_competitive is Dictionary:
			var competitive: Dictionary = raw_competitive
			var raw_active = competitive.get("active", {})
			if raw_active is Dictionary:
				result["active_competition"] = (
					raw_active as Dictionary
				).duplicate(true)

	if game.has_method("get_competition_snapshot"):
		var raw_regional = game.call(
			"get_competition_snapshot",
			StringName(REGIONAL_CHAMPIONSHIP_ID)
		)
		if raw_regional is Dictionary:
			result["regional_championship"] = (
				raw_regional as Dictionary
			).duplicate(true)

	if game.has_method("get_world_progression_snapshot"):
		var raw_world_progression = game.call("get_world_progression_snapshot")
		if raw_world_progression is Dictionary:
			result["world_progression"] = (
				raw_world_progression as Dictionary
			).duplicate(true)

	result["source_acquisition_counts"] = (
		_collect_required_source_acquisition_counts(game)
	)

	return result


func _collect_required_source_acquisition_counts(game: Node) -> Dictionary:
	var result: Dictionary = {}
	if game == null or _plan.is_empty():
		return result
	if (
		not game.has_method("get_acquisition_source_snapshot")
		or not game.has_method("get_acquisition_sources_snapshot")
		or not game.has_method("get_card_snapshot")
	):
		return result

	var exact_sources: Dictionary = {}
	var wildcard_types: Dictionary = {}
	for raw_milestone in _plan.get("milestones", []):
		if not (raw_milestone is Dictionary):
			continue
		var milestone: Dictionary = raw_milestone
		_collect_activity_source_refs(
			milestone.get("activity_requirements", []),
			exact_sources,
			wildcard_types
		)
		for raw_group in milestone.get("activity_choice_groups", []):
			if not (raw_group is Dictionary):
				continue
			_collect_activity_source_refs(
				(raw_group as Dictionary).get("options", []),
				exact_sources,
				wildcard_types
			)

	for raw_key in exact_sources.keys():
		var key: String = str(raw_key)
		var parts: PackedStringArray = key.split(":", false, 1)
		if parts.size() != 2:
			continue
		var source_type := StringName(parts[0])
		var source_id := StringName(parts[1])
		var raw_source = game.call(
			"get_acquisition_source_snapshot",
			source_type,
			source_id
		)
		if not (raw_source is Dictionary):
			continue
		result[key] = _count_source_acquisition_history(
			game,
			raw_source as Dictionary
		)

	if not wildcard_types.is_empty():
		var raw_sources = game.call("get_acquisition_sources_snapshot")
		if raw_sources is Array:
			for raw_type in wildcard_types.keys():
				var source_type_text: String = str(raw_type)
				var acquired_count: int = 0
				for raw_source in raw_sources:
					if not (raw_source is Dictionary):
						continue
					var source: Dictionary = raw_source
					if str(source.get("source_type", "")) != source_type_text:
						continue
					acquired_count += _count_source_acquisition_history(
						game,
						source
					)
				result["%s:*" % source_type_text] = acquired_count

	return result


func _collect_activity_source_refs(
	raw_activities,
	exact_sources: Dictionary,
	wildcard_types: Dictionary
) -> void:
	if not (raw_activities is Array):
		return
	for raw_activity in raw_activities:
		if not (raw_activity is Dictionary):
			continue
		var activity: Dictionary = raw_activity
		var kind: String = str(activity.get("kind", ""))
		var source_type: String = str(
			activity.get("source_type", "")
		).strip_edges()
		if source_type.is_empty():
			continue
		if kind == "source_acquired":
			var source_id: String = str(
				activity.get("source_id", "")
			).strip_edges()
			if not source_id.is_empty():
				exact_sources["%s:%s" % [source_type, source_id]] = true
		elif kind == "source_type_acquired":
			wildcard_types[source_type] = true


func _count_source_acquisition_history(
	game: Node,
	source: Dictionary
) -> int:
	var source_type: String = str(source.get("source_type", ""))
	if source_type.is_empty():
		return 0
	var count: int = 0
	for raw_card_id in source.get("card_ids", []):
		var raw_card = game.call(
			"get_card_snapshot",
			StringName(str(raw_card_id))
		)
		if not (raw_card is Dictionary):
			continue
		var card: Dictionary = raw_card
		var raw_history = card.get("history", {})
		var history: Dictionary = (
			raw_history as Dictionary
			if raw_history is Dictionary
			else {}
		)
		var acquired: int = maxi(0, int(history.get("acquired", 0)))
		var first_source: String = str(history.get("first_source", ""))
		var last_source: String = str(history.get("last_source", ""))
		var history_matches: bool = (
			acquired > 0
			and (first_source == source_type or last_source == source_type)
		)
		# QA presets and pre-history migration saves can own a canonical source
		# card without an acquisition-history entry. Since the early campaign
		# sources used here are exclusive primary routes, current ownership is a
		# safe compatibility fallback only when no history exists.
		var migration_fallback: bool = (
			acquired <= 0
			and history.is_empty()
			and bool(card.get("owned", false))
		)
		if history_matches or migration_fallback:
			count += 1
	return count


func _find_triple_triad_game() -> Node:
	if is_instance_valid(_cached_triple_triad_game):
		return _cached_triple_triad_game
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	_cached_triple_triad_game = tree.current_scene.find_child(
		"TripleTriadGame",
		true,
		false
	)
	return _cached_triple_triad_game


static func build_snapshot_from_state(
	plan: Dictionary,
	runtime: Dictionary
) -> Dictionary:
	return ProgressionPolicyScript.build_snapshot_from_state(plan, runtime)


func _list_has_string(raw_values, expected: String) -> bool:
	if not (raw_values is PackedStringArray or raw_values is Array):
		return false
	for raw_value in raw_values:
		if str(raw_value) == expected:
			return true
	return false



func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Campaign Progression Director: missing %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Campaign Progression Director: could not open %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("Campaign Progression Director: invalid JSON in %s" % path)
		return {}
	return (parsed as Dictionary).duplicate(true)
