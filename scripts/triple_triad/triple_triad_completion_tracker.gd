extends RefCounted

signal changed(snapshot: Dictionary)
signal milestone_reached(unique_card_count: int, snapshot: Dictionary)
signal collection_completed(snapshot: Dictionary)

const SAVE_PATH := "user://triple_triad_completion.cfg"
const SAVE_VERSION := 1
const MILESTONES := [25, 50, 100, 150, 179]

var _catalog = null
var _collection = null
var _world_catalog = null
var _encounter_records = null
var _progression = null
var _competition_service = null
var _opponent_registry = null
var _persistence_enabled: bool = true

var _highest_unique_owned_ever: int = 0
var _earned_milestones := PackedInt32Array()
var _first_collection_complete_unix: int = 0
var _last_snapshot: Dictionary = {}


func initialize(
	catalog,
	collection,
	world_catalog,
	encounter_records,
	progression,
	competition_service,
	opponent_registry,
	persistence_enabled: bool = true
) -> void:
	_catalog = catalog
	_collection = collection
	_world_catalog = world_catalog
	_encounter_records = encounter_records
	_progression = progression
	_competition_service = competition_service
	_opponent_registry = opponent_registry
	_persistence_enabled = persistence_enabled

	_highest_unique_owned_ever = 0
	_earned_milestones = PackedInt32Array()
	_first_collection_complete_unix = 0
	_last_snapshot.clear()

	if _persistence_enabled:
		_load()
	refresh("initialize", false)


func refresh(reason: String = "", emit_change: bool = true) -> Dictionary:
	var before_highest: int = _highest_unique_owned_ever
	var before_complete_unix: int = _first_collection_complete_unix
	var before_milestones: PackedInt32Array = _earned_milestones.duplicate()

	var current_unique: int = _current_unique_owned()
	if current_unique > _highest_unique_owned_ever:
		_highest_unique_owned_ever = current_unique

	var new_milestones: Array[int] = []
	for raw_milestone in MILESTONES:
		var milestone: int = int(raw_milestone)
		if current_unique >= milestone and not _earned_milestones.has(milestone):
			_earned_milestones.append(milestone)
			new_milestones.append(milestone)
	_earned_milestones.sort()

	var total_cards: int = _card_universe_ids().size()
	if (
		total_cards > 0
		and current_unique >= total_cards
		and _first_collection_complete_unix <= 0
	):
		_first_collection_complete_unix = int(Time.get_unix_time_from_system())

	var changed_persistent_state: bool = (
		before_highest != _highest_unique_owned_ever
		or before_complete_unix != _first_collection_complete_unix
		or before_milestones != _earned_milestones
	)
	if changed_persistent_state and _persistence_enabled:
		_save()

	_last_snapshot = _build_snapshot(reason)

	if emit_change:
		changed.emit(_last_snapshot.duplicate(true))
		for milestone in new_milestones:
			milestone_reached.emit(
				milestone,
				_last_snapshot.duplicate(true)
			)
		if (
			before_complete_unix <= 0
			and _first_collection_complete_unix > 0
		):
			collection_completed.emit(
				_last_snapshot.duplicate(true)
			)

	return _last_snapshot.duplicate(true)


func get_snapshot() -> Dictionary:
	return refresh("snapshot", false)


func get_missing_card_ids() -> PackedStringArray:
	var snapshot: Dictionary = get_snapshot()
	return snapshot.get("missing_card_ids", PackedStringArray()).duplicate()


func is_collection_complete() -> bool:
	return bool(get_snapshot().get("collection_complete", false))


func _build_snapshot(reason: String) -> Dictionary:
	var card_ids: PackedStringArray = _card_universe_ids()
	var total_cards: int = card_ids.size()
	var player_rank: int = _player_rank()
	var owned_ids := PackedStringArray()
	var missing_ids := PackedStringArray()
	var missing_cards: Array = []
	var rarity_counts: Dictionary = {}
	var group_counts: Dictionary = {}

	for raw_card_id in card_ids:
		var card_id := StringName(str(raw_card_id))
		var card = _card(card_id)
		var quantity: int = _quantity(card_id)
		var owned: bool = quantity > 0
		if owned:
			owned_ids.append(String(card_id))
		else:
			missing_ids.append(String(card_id))

		var rarity: String = "unknown"
		var group: String = "ungrouped"
		var display_name: String = String(card_id)
		var required_rank: int = 1
		if card != null:
			rarity = String(card.get("rarity_id"))
			if rarity.is_empty():
				rarity = "unknown"
			group = String(card.get("group_id"))
			if group.is_empty():
				group = "ungrouped"
			display_name = str(card.get("display_name"))
			required_rank = maxi(1, int(card.get("required_player_rank")))

		_accumulate_breakdown(rarity_counts, rarity, owned)
		_accumulate_breakdown(group_counts, group, owned)

		if not owned:
			missing_cards.append({
				"card_id": String(card_id),
				"display_name": display_name,
				"rarity": rarity,
				"group": group,
				"required_duel_rank": required_rank,
				"rank_locked": player_rank < required_rank,
				"sources": _card_sources(card_id),
				"stolen_by": _stolen_holders(card_id),
			})

	var owned_unique: int = owned_ids.size()
	var missing_unique: int = missing_ids.size()
	var completion_percent: float = 0.0
	if total_cards > 0:
		completion_percent = (
			float(owned_unique) / float(total_cards) * 100.0
		)

	var source_progress: Array = _source_progress()
	var complete_sources: int = 0
	for source in source_progress:
		if bool(source.get("complete", false)):
			complete_sources += 1

	var opponent_tracking: Dictionary = _opponent_tracking()
	var competitive_tracking: Dictionary = _competitive_tracking()
	var match_tracking: Dictionary = _match_tracking()
	var collection_complete: bool = (
		total_cards > 0 and owned_unique >= total_cards
	)
	var campaign_complete: bool = bool(
		competitive_tracking.get("card_game_completed", false)
	)

	return {
		"reason": reason,
		"catalog_total_unique": total_cards,
		"owned_unique": owned_unique,
		"owned_total": _current_total_owned(),
		"missing_unique": missing_unique,
		"completion_percent": completion_percent,
		"collection_complete": collection_complete,
		"campaign_complete": campaign_complete,
		"full_card_game_completion": (
			collection_complete and campaign_complete
		),
		"highest_unique_owned_ever": _highest_unique_owned_ever,
		"highest_completion_percent_ever": (
			float(_highest_unique_owned_ever) / float(total_cards) * 100.0
			if total_cards > 0
			else 0.0
		),
		"first_collection_complete_unix": _first_collection_complete_unix,
		"milestones": _milestone_snapshot(),
		"owned_card_ids": owned_ids,
		"missing_card_ids": missing_ids,
		"missing_cards": missing_cards,
		"rarity_breakdown": rarity_counts,
		"group_breakdown": group_counts,
		"source_progress": source_progress,
		"sources_complete": complete_sources,
		"sources_total": source_progress.size(),
		"opponents": opponent_tracking,
		"competitive": competitive_tracking,
		"matches": match_tracking,
		"outstanding_stolen_cards": _outstanding_stolen_cards(),
	}


func _card_universe_ids() -> PackedStringArray:
	var seen: Dictionary = {}
	if (
		_world_catalog != null
		and _world_catalog.has_method("get_all_source_snapshots")
	):
		for raw_source in _world_catalog.call("get_all_source_snapshots"):
			if not (raw_source is Dictionary):
				continue
			for raw_card_id in (raw_source as Dictionary).get("card_ids", []):
				var card_id: String = str(raw_card_id)
				if not card_id.is_empty():
					seen[card_id] = true
	var result := PackedStringArray()
	for raw_id in seen.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func _source_progress() -> Array:
	var result: Array = []
	if (
		_world_catalog == null
		or not _world_catalog.has_method("get_all_source_snapshots")
	):
		return result
	var player_rank: int = _player_rank()
	for raw_source in _world_catalog.call("get_all_source_snapshots"):
		if not (raw_source is Dictionary):
			continue
		var source: Dictionary = (raw_source as Dictionary).duplicate(true)
		var card_ids = source.get("card_ids", [])
		var owned_count: int = 0
		var missing := PackedStringArray()
		for raw_card_id in card_ids:
			var card_id := StringName(str(raw_card_id))
			if _quantity(card_id) > 0:
				owned_count += 1
			else:
				missing.append(String(card_id))
		var total_count: int = card_ids.size()
		var percent: float = 0.0
		if total_count > 0:
			percent = float(owned_count) / float(total_count) * 100.0
		var min_rank: int = maxi(1, int(source.get("min_duel_rank", 1)))
		result.append({
			"source_type": str(source.get("source_type", "")),
			"source_id": str(source.get("source_id", "")),
			"display_name": str(source.get("display_name", "")),
			"description": str(source.get("description", "")),
			"min_duel_rank": min_rank,
			"rank_available": player_rank >= min_rank,
			"owned_count": owned_count,
			"total_count": total_count,
			"missing_count": missing.size(),
			"completion_percent": percent,
			"complete": total_count > 0 and missing.is_empty(),
			"missing_card_ids": missing,
		})
	result.sort_custom(func(a, b):
		var type_a: String = str(a.get("source_type", ""))
		var type_b: String = str(b.get("source_type", ""))
		if type_a == type_b:
			return str(a.get("source_id", "")) < str(b.get("source_id", ""))
		return type_a < type_b
	)
	return result


func _opponent_tracking() -> Dictionary:
	var total_opponents: int = 0
	if (
		_opponent_registry != null
		and _opponent_registry.has_method("get_all_opponents")
	):
		total_opponents = (_opponent_registry.call("get_all_opponents") as Array).size()
	var beaten := PackedStringArray()
	if (
		_encounter_records != null
		and _encounter_records.has_method("get_beaten_opponent_ids")
	):
		beaten = _encounter_records.call("get_beaten_opponent_ids")
	var undefeated := PackedStringArray()
	if (
		_opponent_registry != null
		and _opponent_registry.has_method("get_all_opponents")
	):
		for profile in _opponent_registry.call("get_all_opponents"):
			if profile == null:
				continue
			var opponent_id: String = String(profile.get("opponent_id"))
			if not beaten.has(opponent_id):
				undefeated.append(opponent_id)
	undefeated.sort()
	return {
		"beaten_count": beaten.size(),
		"total_count": total_opponents,
		"all_beaten": total_opponents > 0 and beaten.size() >= total_opponents,
		"beaten_ids": beaten,
		"undefeated_ids": undefeated,
	}


func _competitive_tracking() -> Dictionary:
	if _competition_service == null:
		return {
			"card_game_completed": false,
			"card_master": false,
			"regional_champion": false,
			"circuits": [],
			"competitions": [],
			"earned_titles": PackedStringArray(),
		}
	var beaten := PackedStringArray()
	if _encounter_records != null:
		beaten = _encounter_records.call("get_beaten_opponent_ids")
	return _competition_service.call(
		"get_snapshot",
		_player_rank(),
		beaten
	)


func _match_tracking() -> Dictionary:
	var snapshot: Dictionary = {}
	if _progression != null and _progression.has_method("get_snapshot"):
		snapshot = _progression.call("get_snapshot")
	var wins: int = maxi(0, int(snapshot.get("wins", 0)))
	var losses: int = maxi(0, int(snapshot.get("losses", 0)))
	var draws: int = maxi(0, int(snapshot.get("draws", 0)))
	var matches: int = maxi(
		wins + losses + draws,
		int(snapshot.get("matches", 0))
	)
	var decisive: int = wins + losses
	return {
		"matches": matches,
		"wins": wins,
		"losses": losses,
		"draws": draws,
		"win_rate": float(wins) / float(matches) if matches > 0 else 0.0,
		"decisive_win_rate": float(wins) / float(decisive) if decisive > 0 else 0.0,
		"duel_rank": _player_rank(),
		"duel_points": maxi(0, int(snapshot.get("points", 0))),
	}


func _outstanding_stolen_cards() -> Dictionary:
	var total: int = 0
	var by_opponent: Array = []
	if _encounter_records == null:
		return {"total": 0, "by_opponent": []}
	for raw_id in _encounter_records.call("get_all_recorded_ids"):
		var encounter: Dictionary = _encounter_records.call(
			"get_snapshot",
			StringName(str(raw_id))
		)
		var stolen_total: int = maxi(0, int(encounter.get("stolen_total", 0)))
		if stolen_total <= 0:
			continue
		total += stolen_total
		by_opponent.append({
			"opponent_id": str(raw_id),
			"stolen_total": stolen_total,
			"stolen_quantities": (encounter.get("stolen_quantities", {}) as Dictionary).duplicate(true),
		})
	return {"total": total, "by_opponent": by_opponent}


func _stolen_holders(card_id: StringName) -> PackedStringArray:
	var result := PackedStringArray()
	if _encounter_records == null:
		return result
	for raw_id in _encounter_records.call("get_all_recorded_ids"):
		var encounter: Dictionary = _encounter_records.call(
			"get_snapshot",
			StringName(str(raw_id))
		)
		var stolen: Dictionary = encounter.get("stolen_quantities", {})
		if int(stolen.get(String(card_id), 0)) > 0:
			result.append(str(raw_id))
	result.sort()
	return result


func _milestone_snapshot() -> Array:
	var result: Array = []
	for raw_milestone in MILESTONES:
		var milestone: int = int(raw_milestone)
		result.append({
			"unique_cards": milestone,
			"earned": _earned_milestones.has(milestone),
			"current_reached": _current_unique_owned() >= milestone,
		})
	return result


func _accumulate_breakdown(target: Dictionary, key: String, owned: bool) -> void:
	var entry: Dictionary = target.get(key, {
		"owned": 0,
		"total": 0,
		"missing": 0,
		"completion_percent": 0.0,
	}).duplicate(true)
	entry["total"] = int(entry.get("total", 0)) + 1
	if owned:
		entry["owned"] = int(entry.get("owned", 0)) + 1
	else:
		entry["missing"] = int(entry.get("missing", 0)) + 1
	entry["completion_percent"] = (
		float(entry["owned"]) / float(entry["total"]) * 100.0
		if int(entry["total"]) > 0
		else 0.0
	)
	target[key] = entry


func _card_sources(card_id: StringName) -> Array:
	if (
		_world_catalog != null
		and _world_catalog.has_method("get_sources_for_card")
	):
		return _world_catalog.call("get_sources_for_card", card_id)
	return []


func _card(card_id: StringName):
	if _catalog != null and _catalog.has_method("get_card_by_id"):
		return _catalog.call("get_card_by_id", card_id)
	return null


func _quantity(card_id: StringName) -> int:
	if _collection != null and _collection.has_method("get_quantity_by_id"):
		return maxi(0, int(_collection.call("get_quantity_by_id", card_id)))
	return 0


func _current_unique_owned() -> int:
	if _collection != null and _collection.has_method("unique_owned_count"):
		return maxi(0, int(_collection.call("unique_owned_count")))
	return 0


func _current_total_owned() -> int:
	if _collection != null and _collection.has_method("total_owned_count"):
		return maxi(0, int(_collection.call("total_owned_count")))
	return 0


func _player_rank() -> int:
	if _progression != null and _progression.has_method("get_rank_number"):
		return maxi(1, int(_progression.call("get_rank_number")))
	return 1


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	if int(config.get_value("meta", "version", 0)) <= 0:
		return
	_highest_unique_owned_ever = maxi(
		0,
		int(config.get_value("completion", "highest_unique_owned_ever", 0))
	)
	_first_collection_complete_unix = maxi(
		0,
		int(config.get_value("completion", "first_collection_complete_unix", 0))
	)
	var raw_milestones = config.get_value(
		"completion",
		"earned_milestones",
		PackedInt32Array()
	)
	_earned_milestones = PackedInt32Array()
	if raw_milestones is PackedInt32Array or raw_milestones is Array:
		for raw_milestone in raw_milestones:
			var milestone: int = int(raw_milestone)
			if milestone in MILESTONES and not _earned_milestones.has(milestone):
				_earned_milestones.append(milestone)
	_earned_milestones.sort()


func _save() -> Error:
	if not _persistence_enabled:
		return OK
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value(
		"completion",
		"highest_unique_owned_ever",
		_highest_unique_owned_ever
	)
	config.set_value(
		"completion",
		"earned_milestones",
		_earned_milestones
	)
	config.set_value(
		"completion",
		"first_collection_complete_unix",
		_first_collection_complete_unix
	)
	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadCompletionTracker: could not save completion state (%s)."
			% error_string(save_error)
		)
	return save_error
