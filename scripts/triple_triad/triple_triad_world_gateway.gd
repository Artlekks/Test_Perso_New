extends RefCounted
class_name TripleTriadWorldGateway

signal acquisition_completed(result: Dictionary)
signal card_game_unlock_changed(unlocked: bool)
signal gameplay_event_requested(
	event_type: StringName,
	title: String,
	detail: String,
	payload: Dictionary,
	priority: int
)
signal save_checkpoint_requested(reason: String)
signal backend_state_change_requested(reason: String)

var _card_catalog = null
var _acquisition_service = null
var _world_acquisition_catalog = null
var _world_reward_ledger = null
var _collection_backend = null
var _progression = null
var _encounter_records = null
var _opponent_registry = null
var _rng: RandomNumberGenerator = null
var _fallback_player_rank: int = 1
var _backend_ready: bool = false
var _fishing_salvage_bridge = null


func initialize(
	card_catalog,
	acquisition_service,
	world_acquisition_catalog,
	world_reward_ledger,
	collection_backend,
	progression,
	encounter_records,
	opponent_registry,
	rng: RandomNumberGenerator,
	fallback_player_rank: int = 1
) -> void:
	_disconnect_acquisition_service()
	_card_catalog = card_catalog
	_acquisition_service = acquisition_service
	_world_acquisition_catalog = world_acquisition_catalog
	_world_reward_ledger = world_reward_ledger
	_collection_backend = collection_backend
	_progression = progression
	_encounter_records = encounter_records
	_opponent_registry = opponent_registry
	_rng = rng
	_fallback_player_rank = maxi(1, fallback_player_rank)
	_connect_acquisition_service()


func set_backend_ready(ready: bool) -> void:
	_backend_ready = ready


func set_fishing_salvage_bridge(bridge) -> void:
	_fishing_salvage_bridge = bridge


func is_card_game_unlocked() -> bool:
	if _acquisition_service == null:
		return false
	return bool(_acquisition_service.call("is_card_game_unlocked"))


func get_acquisition_snapshot() -> Dictionary:
	if _acquisition_service == null:
		return {
			"card_game_unlocked": false,
			"claimed_bundle_ids": PackedStringArray(),
			"available_bundle_ids": PackedStringArray(),
		}
	return _acquisition_service.call("get_snapshot")


func claim_acquisition_bundle(
	bundle_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	if not _backend_ready or _acquisition_service == null:
		return {
			"success": false,
			"reason": "backend_unavailable",
			"bundle_id": String(bundle_id),
		}

	var result: Dictionary = _acquisition_service.call(
		"claim_bundle",
		bundle_id,
		source_context
	)
	if bool(result.get("success", false)):
		save_checkpoint_requested.emit("acquisition_bundle")
		gameplay_event_requested.emit(
			&"bundle_acquired",
			str(result.get("display_name", "Card Bundle")),
			"%d cards acquired." % int(result.get("granted_cards", 0)),
			result.duplicate(true),
			0
		)
		if bool(result.get("unlocked_card_game", false)):
			gameplay_event_requested.emit(
				&"card_game_unlocked",
				"Card Duels Unlocked",
				"Card players can now be challenged.",
				result.duplicate(true),
				2
			)
		backend_state_change_requested.emit("acquisition_bundle")
	return result


func claim_salvaged_card_case(
	source_context: StringName = &"sea_salvage"
) -> Dictionary:
	return claim_acquisition_bundle(
		&"salvaged_card_case",
		source_context
	)


func get_onboarding_snapshot() -> Dictionary:
	var acquisition: Dictionary = get_acquisition_snapshot()
	var collection_unique_count: int = 0
	if (
		_collection_backend != null
		and _collection_backend.has_method("unique_owned_count")
	):
		collection_unique_count = int(
			_collection_backend.call("unique_owned_count")
		)

	var starter_case_claimed: bool = false
	var raw_claimed_ids = acquisition.get(
		"claimed_bundle_ids",
		PackedStringArray()
	)
	if raw_claimed_ids is PackedStringArray or raw_claimed_ids is Array:
		for raw_id in raw_claimed_ids:
			if str(raw_id) == "salvaged_card_case":
				starter_case_claimed = true
				break

	var bridge_snapshot: Dictionary = {}
	if (
		is_instance_valid(_fishing_salvage_bridge)
		and _fishing_salvage_bridge.has_method("get_debug_snapshot")
	):
		bridge_snapshot = _fishing_salvage_bridge.call(
			"get_debug_snapshot"
		)

	return {
		"card_game_unlocked": bool(
			acquisition.get("card_game_unlocked", false)
		),
		"starter_case_claimed": starter_case_claimed,
		"collection_unique_count": collection_unique_count,
		"available_card_player_ids": get_available_card_player_ids(),
		"fishing_salvage_bridge": bridge_snapshot,
	}


func get_card_acquisition_sources(card_id: StringName) -> Array:
	if _world_acquisition_catalog == null:
		return []
	return _world_acquisition_catalog.call(
		"get_sources_for_card",
		card_id
	)


func get_acquisition_source_snapshot(
	source_type: StringName,
	source_id: StringName
) -> Dictionary:
	if _world_acquisition_catalog == null:
		return {}
	return _world_acquisition_catalog.call(
		"get_source_snapshot",
		source_type,
		source_id
	)


func get_world_acquisition_sources() -> Array:
	if _world_acquisition_catalog == null:
		return []
	return _world_acquisition_catalog.call(
		"get_all_source_snapshots"
	)


func claim_world_source_card(
	source_type: StringName,
	source_id: StringName,
	card_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	if not _backend_ready:
		return {"success": false, "reason": "backend_not_ready"}
	if _world_acquisition_catalog == null or _acquisition_service == null:
		return {
			"success": false,
			"reason": "acquisition_backend_unavailable",
		}

	var validation: Dictionary = _world_acquisition_catalog.call(
		"validate_claim",
		source_type,
		source_id,
		card_id,
		_player_rank()
	)
	if not bool(validation.get("valid", false)):
		return {
			"success": false,
			"reason": str(
				validation.get("reason", "invalid_source_claim")
			),
			"required_duel_rank": int(
				validation.get("required_duel_rank", 1)
			),
		}

	var context_text: String = String(source_context)
	if context_text.is_empty():
		context_text = "%s:%s" % [
			String(source_type),
			String(source_id),
		]
	var result: Dictionary = _acquisition_service.call(
		"grant_card",
		card_id,
		source_type,
		StringName(context_text),
		1
	)
	if bool(result.get("success", false)):
		save_checkpoint_requested.emit("world_card_acquired")
		acquisition_completed.emit(result.duplicate(true))
		gameplay_event_requested.emit(
			&"card_acquired",
			str(result.get("display_name", String(card_id))),
			"New card acquired.",
			result.duplicate(true),
			0
		)
		backend_state_change_requested.emit("world_card_acquired")
	return result


func claim_world_source_reward(
	source_type: StringName,
	source_id: StringName,
	source_context: StringName = &"",
	event_id: StringName = &"",
	one_shot: bool = false
) -> Dictionary:
	if not _backend_ready:
		return {
			"success": false,
			"reason": "backend_not_ready",
		}
	if _world_acquisition_catalog == null:
		return {
			"success": false,
			"reason": "acquisition_catalog_unavailable",
		}
	if not bool(
		_world_acquisition_catalog.call(
			"can_direct_claim_source",
			source_type
		)
	):
		return {
			"success": false,
			"reason": "source_owned_by_other_system",
		}

	var event_key: String = String(event_id).strip_edges()
	if (
		one_shot
		and not event_key.is_empty()
		and has_world_reward_event_claimed(event_id)
	):
		return {
			"success": false,
			"reason": "event_already_claimed",
			"event_id": event_key,
		}

	var source: Dictionary = get_acquisition_source_snapshot(
		source_type,
		source_id
	)
	if source.is_empty():
		return {
			"success": false,
			"reason": "unknown_source",
		}

	var required_rank: int = maxi(
		1,
		int(source.get("min_duel_rank", 1))
	)
	if _player_rank() < required_rank:
		return {
			"success": false,
			"reason": "duel_rank_too_low",
			"required_duel_rank": required_rank,
		}

	var source_cards: Array = _world_acquisition_catalog.call(
		"get_cards_for_source",
		source_type,
		source_id,
		_player_rank()
	)
	if source_cards.is_empty():
		return {
			"success": false,
			"reason": "source_has_no_eligible_cards",
		}

	var resolved_context: StringName = source_context
	if String(resolved_context).is_empty():
		resolved_context = StringName(
			"%s:%s" % [
				String(source_type),
				String(source_id),
			]
		)

	var chosen_card = null
	var chosen_id: StringName = &""
	var owned_before: int = 0
	var pending_delivery: Dictionary = {}
	if (
		one_shot
		and not event_key.is_empty()
		and _world_reward_ledger != null
	):
		pending_delivery = _world_reward_ledger.call(
			"get_pending_delivery",
			event_id
		)

	if not pending_delivery.is_empty():
		if (
			str(pending_delivery.get("source_type", ""))
			!= String(source_type)
			or str(pending_delivery.get("source_id", ""))
			!= String(source_id)
		):
			return {
				"success": false,
				"reason": "pending_delivery_source_mismatch",
				"event_id": event_key,
			}
		chosen_id = StringName(
			str(pending_delivery.get("card_id", ""))
		)
		if _card_catalog != null:
			chosen_card = _card_catalog.call(
				"get_card_by_id",
				chosen_id
			)
		owned_before = maxi(
			0,
			int(
				pending_delivery.get(
					"owned_quantity_before",
					0
				)
			)
		)
		if chosen_card == null:
			return {
				"success": false,
				"reason": "pending_delivery_card_missing",
				"event_id": event_key,
			}

		var current_quantity: int = _owned_quantity(chosen_id)
		if current_quantity > owned_before:
			_world_reward_ledger.call(
				"complete_delivery",
				event_id
			)
			return {
				"success": true,
				"reason": "pending_delivery_recovered",
				"card_id": String(chosen_id),
				"display_name": str(chosen_card.get("display_name")),
				"source_id": String(source_id),
				"source_display_name": str(
					source.get("display_name", "")
				),
				"event_id": event_key,
				"recovered": true,
			}
	else:
		var unowned_cards: Array = []
		for card in source_cards:
			if card == null:
				continue
			var card_id := StringName(str(card.get("card_id")))
			if _owned_quantity(card_id) <= 0:
				unowned_cards.append(card)

		if unowned_cards.is_empty():
			return {
				"success": false,
				"reason": "source_complete",
				"source_type": String(source_type),
				"source_id": String(source_id),
				"source_display_name": str(
					source.get("display_name", "")
				),
			}

		var chosen_index: int = 0
		if _rng != null and unowned_cards.size() > 1:
			chosen_index = _rng.randi_range(
				0,
				unowned_cards.size() - 1
			)
		chosen_card = unowned_cards[chosen_index]
		chosen_id = StringName(str(chosen_card.get("card_id")))
		owned_before = _owned_quantity(chosen_id)

		if (
			one_shot
			and not event_key.is_empty()
			and _world_reward_ledger != null
		):
			if not bool(
				_world_reward_ledger.call(
					"begin_delivery",
					event_id,
					source_type,
					source_id,
					chosen_id,
					resolved_context,
					owned_before
				)
			):
				return {
					"success": false,
					"reason": "could_not_journal_world_reward",
					"event_id": event_key,
				}

	var result: Dictionary = claim_world_source_card(
		source_type,
		source_id,
		chosen_id,
		resolved_context
	)
	result["source_id"] = String(source_id)
	result["source_display_name"] = str(
		source.get("display_name", "")
	)
	result["event_id"] = event_key

	if bool(result.get("success", false)):
		if (
			one_shot
			and not event_key.is_empty()
			and _world_reward_ledger != null
		):
			_world_reward_ledger.call(
				"complete_delivery",
				event_id
			)
	else:
		result["delivery_pending"] = (
			one_shot
			and not event_key.is_empty()
			and _world_reward_ledger != null
			and not (
				_world_reward_ledger.call(
					"get_pending_delivery",
					event_id
				) as Dictionary
			).is_empty()
		)

	return result


func claim_fishing_salvage_reward(
	source_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	return claim_world_source_reward(
		&"fishing_salvage",
		source_id,
		source_context
	)


func claim_treasure_cache_reward(
	source_id: StringName,
	cache_event_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	return claim_world_source_reward(
		&"treasure_cache",
		source_id,
		source_context,
		cache_event_id,
		true
	)


func claim_quest_card_reward(
	source_id: StringName,
	quest_event_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	return claim_world_source_reward(
		&"quest_reward",
		source_id,
		source_context,
		quest_event_id,
		true
	)


func claim_tournament_card_reward(
	source_id: StringName,
	tournament_event_id: StringName,
	source_context: StringName = &"",
	one_shot: bool = true
) -> Dictionary:
	return claim_world_source_reward(
		&"tournament_reward",
		source_id,
		source_context,
		tournament_event_id,
		one_shot
	)


func advance_world_reward_counter(counter_id: StringName) -> int:
	if _world_reward_ledger == null:
		return 0
	return int(
		_world_reward_ledger.call(
			"increment_counter",
			counter_id
		)
	)


func get_world_reward_delivery_snapshot() -> Dictionary:
	if _world_reward_ledger == null:
		return {}
	return _world_reward_ledger.call("get_snapshot")


func has_world_reward_event_claimed(event_id: StringName) -> bool:
	if _world_reward_ledger == null:
		return false
	return bool(
		_world_reward_ledger.call(
			"has_claimed",
			event_id
		)
	)


func get_opponent_availability(opponent_id: StringName) -> Dictionary:
	if (
		_opponent_registry == null
		or not _opponent_registry.has_method("get_availability")
	):
		return {
			"available": false,
			"reason": "Opponent registry unavailable.",
			"required_player_rank": 1,
		}
	return _opponent_registry.call(
		"get_availability",
		opponent_id,
		_player_rank(),
		&"",
		&"",
		_opponent_availability_context()
	)


func get_available_card_player_ids(
	region_id: StringName = &"",
	required_tag: StringName = &""
) -> PackedStringArray:
	var result := PackedStringArray()
	if (
		_opponent_registry == null
		or not _opponent_registry.has_method("get_available_opponents")
	):
		return result
	var profiles: Array = _opponent_registry.call(
		"get_available_opponents",
		_player_rank(),
		region_id,
		required_tag,
		_opponent_availability_context()
	)
	for profile in profiles:
		if profile != null:
			result.append(String(profile.get("opponent_id")))
	return result


func get_opponent_availability_context() -> Dictionary:
	return _opponent_availability_context()


func _opponent_availability_context() -> Dictionary:
	var beaten_ids := PackedStringArray()
	var total_wins: int = 0
	if _encounter_records != null:
		if _encounter_records.has_method("get_beaten_opponent_ids"):
			beaten_ids = _encounter_records.call(
				"get_beaten_opponent_ids"
			)
		if _encounter_records.has_method("get_total_player_wins"):
			total_wins = int(
				_encounter_records.call("get_total_player_wins")
			)
	return {
		"card_game_unlocked": is_card_game_unlocked(),
		"beaten_opponent_ids": beaten_ids,
		"total_player_wins": total_wins,
	}


func _player_rank() -> int:
	if _progression != null and _progression.has_method("get_rank_number"):
		return maxi(1, int(_progression.call("get_rank_number")))
	return _fallback_player_rank


func _owned_quantity(card_id: StringName) -> int:
	if (
		_collection_backend == null
		or not _collection_backend.has_method("get_quantity_by_id")
	):
		return 0
	return maxi(
		0,
		int(
			_collection_backend.call(
				"get_quantity_by_id",
				card_id
			)
		)
	)


func _connect_acquisition_service() -> void:
	if _acquisition_service == null:
		return
	var bundle_callable := Callable(self, "_on_bundle_claimed")
	var unlock_callable := Callable(self, "_on_unlock_changed")
	if (
		_acquisition_service.has_signal("bundle_claimed")
		and not _acquisition_service.is_connected(
			&"bundle_claimed",
			bundle_callable
		)
	):
		_acquisition_service.connect(
			&"bundle_claimed",
			bundle_callable
		)
	if (
		_acquisition_service.has_signal("unlock_changed")
		and not _acquisition_service.is_connected(
			&"unlock_changed",
			unlock_callable
		)
	):
		_acquisition_service.connect(
			&"unlock_changed",
			unlock_callable
		)


func _disconnect_acquisition_service() -> void:
	if _acquisition_service == null:
		return
	var bundle_callable := Callable(self, "_on_bundle_claimed")
	var unlock_callable := Callable(self, "_on_unlock_changed")
	if (
		_acquisition_service.has_signal("bundle_claimed")
		and _acquisition_service.is_connected(
			&"bundle_claimed",
			bundle_callable
		)
	):
		_acquisition_service.disconnect(
			&"bundle_claimed",
			bundle_callable
		)
	if (
		_acquisition_service.has_signal("unlock_changed")
		and _acquisition_service.is_connected(
			&"unlock_changed",
			unlock_callable
		)
	):
		_acquisition_service.disconnect(
			&"unlock_changed",
			unlock_callable
		)


func _on_bundle_claimed(result: Dictionary) -> void:
	acquisition_completed.emit(result.duplicate(true))


func _on_unlock_changed(unlocked: bool) -> void:
	card_game_unlock_changed.emit(unlocked)
