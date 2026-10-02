extends RefCounted
class_name TripleTriadCompetitionController

signal competition_state_changed(snapshot: Dictionary)
signal gameplay_event_requested(
	event_type: StringName,
	title: String,
	detail: String,
	payload: Dictionary,
	priority: int
)
signal backend_state_change_requested(reason: String)

var _service = null
var _card_catalog = null
var _collection_backend = null
var _progression = null
var _encounter_records = null
var _acquisition_policy = null
var _world_gateway = null
var _world_reward_ledger = null
var _opponent_registry = null
var _fallback_player_rank: int = 1

var _match_active: bool = false
var _pending_change: Dictionary = {}


func initialize(
	competition_service,
	card_catalog,
	collection_backend,
	progression,
	encounter_records,
	acquisition_policy,
	world_gateway,
	world_reward_ledger,
	opponent_registry,
	fallback_player_rank: int = 1
) -> void:
	_service = competition_service
	_card_catalog = card_catalog
	_collection_backend = collection_backend
	_progression = progression
	_encounter_records = encounter_records
	_acquisition_policy = acquisition_policy
	_world_gateway = world_gateway
	_world_reward_ledger = world_reward_ledger
	_opponent_registry = opponent_registry
	_fallback_player_rank = maxi(1, fallback_player_rank)
	_match_active = false
	_pending_change.clear()


func is_ready() -> bool:
	return _service != null


func is_match_active() -> bool:
	return _match_active


func set_match_active(active: bool) -> void:
	_match_active = active


func get_pending_change() -> Dictionary:
	return _pending_change.duplicate(true)


func set_pending_change(change: Dictionary) -> void:
	_pending_change = change.duplicate(true)


func clear_pending_change() -> void:
	_pending_change.clear()


func should_continue_after_reward() -> bool:
	return bool(_pending_change.get("round_won", false))


func get_active_snapshot() -> Dictionary:
	if _service == null:
		return {}
	return _service.call("get_active_snapshot")


func get_active_opponent_id() -> StringName:
	if _service == null:
		return &""
	return StringName(str(_service.call("get_active_opponent_id")))


func get_pending_reward() -> Dictionary:
	if _service == null:
		return {}
	var pending = _service.call("get_pending_reward")
	if pending is Dictionary:
		return (pending as Dictionary).duplicate(true)
	return {}


func get_competitive_snapshot() -> Dictionary:
	if _service == null:
		return {}
	return _service.call(
		"get_snapshot",
		_player_rank(),
		_beaten_opponent_ids()
	)


func get_circuit_snapshot(circuit_id: StringName) -> Dictionary:
	if _service == null:
		return {}
	return _service.call(
		"get_circuit_snapshot",
		circuit_id,
		_player_rank(),
		_beaten_opponent_ids()
	)


func get_competition_snapshot(competition_id: StringName) -> Dictionary:
	if _service == null:
		return {}
	return _service.call(
		"get_competition_snapshot",
		competition_id,
		_player_rank(),
		_beaten_opponent_ids()
	)


func start_competition(competition_id: StringName) -> Dictionary:
	if _service == null:
		return {
			"success": false,
			"reason": "competition_service_unavailable",
		}
	var result: Dictionary = _service.call(
		"start_competition",
		competition_id,
		_player_rank(),
		_beaten_opponent_ids()
	)
	if bool(result.get("success", false)):
		competition_state_changed.emit(get_competitive_snapshot())
		backend_state_change_requested.emit("competition_started")
	return result


func prepare_active_match_open() -> Dictionary:
	if _service == null:
		return {
			"success": false,
			"reason": "competition_service_unavailable",
		}
	var opponent_id: StringName = get_active_opponent_id()
	if opponent_id == &"":
		return {
			"success": false,
			"reason": "no_active_competition_round",
		}
	return {
		"success": true,
		"opponent_id": opponent_id,
		"locked_cards": get_locked_deck_cards(),
	}


func abandon_active_competition() -> Dictionary:
	if _service == null:
		return {
			"success": false,
			"reason": "competition_service_unavailable",
		}
	var result: Dictionary = _service.call("abandon_active_competition")
	if bool(result.get("success", false)):
		_match_active = false
		_pending_change.clear()
		competition_state_changed.emit(get_competitive_snapshot())
		backend_state_change_requested.emit("competition_abandoned")
	return result


func get_locked_deck_cards() -> Array:
	var result: Array = []
	if _service == null:
		return result
	var raw_ids = _service.call("get_locked_deck_ids")
	if not (raw_ids is PackedStringArray or raw_ids is Array):
		return result
	if raw_ids.size() != 5:
		return result

	var player_rank: int = _player_rank()
	for raw_id in raw_ids:
		var card_id := StringName(str(raw_id))
		var card = null
		if _card_catalog != null:
			card = _card_catalog.call("get_card_by_id", card_id)
		if card == null:
			return []
		if (
			_collection_backend == null
			or int(_collection_backend.call("get_quantity_by_id", card_id)) <= 0
		):
			return []
		if (
			_acquisition_policy != null
			and _acquisition_policy.has_method("can_use_card")
			and not bool(
				_acquisition_policy.call(
					"can_use_card",
					card,
					player_rank
				)
			)
		):
			return []
		result.append(card)
	return result


func lock_active_deck(cards: Array) -> bool:
	if _service == null or cards.size() != 5:
		return false
	if bool(_service.call("has_locked_deck")):
		return true
	var ids := PackedStringArray()
	for card in cards:
		if card == null:
			return false
		var card_id: String = str(card.get("card_id"))
		if card_id.is_empty() or ids.has(card_id):
			return false
		ids.append(card_id)
	return bool(_service.call("set_locked_deck_ids", ids))


func apply_match_resolution(resolution: Dictionary) -> Dictionary:
	var competition_change: Dictionary = (
		resolution.get("competition", {}) as Dictionary
	).duplicate(true)
	_match_active = bool(
		resolution.get(
			"competition_match_active",
			_match_active
		)
	)
	if bool(resolution.get("competition_state_changed", false)):
		competition_state_changed.emit(get_competitive_snapshot())

	if bool(competition_change.get("completed", false)):
		competition_change["tournament_reward"] = (
			resolve_pending_reward()
		)

	_pending_change = competition_change.duplicate(true)
	if bool(competition_change.get("round_won", false)):
		gameplay_event_requested.emit(
			&"tournament_round_won",
			"Round Won",
			"Next opponent: %s"
			% str(competition_change.get("next_opponent_id", "")),
			competition_change.duplicate(true),
			0
		)
	elif bool(competition_change.get("failed", false)):
		gameplay_event_requested.emit(
			&"tournament_failed",
			"Tournament Attempt Ended",
			"Return when you are ready to try again.",
			competition_change.duplicate(true),
			0
		)
	elif bool(competition_change.get("completed", false)):
		gameplay_event_requested.emit(
			&"tournament_cleared",
			"Tournament Cleared",
			str(competition_change.get("title_awarded", "")),
			competition_change.duplicate(true),
			2
		)
	return competition_change


func prepare_next_round() -> Dictionary:
	if _service == null:
		return {
			"success": false,
			"reason": "competition_service_unavailable",
		}
	var next_opponent_id: StringName = get_active_opponent_id()
	if next_opponent_id == &"":
		return {
			"success": false,
			"reason": "no_next_opponent",
		}

	var locked_cards: Array = get_locked_deck_cards()
	if locked_cards.size() != 5:
		abandon_active_competition()
		return {
			"success": false,
			"reason": "invalid_locked_deck",
		}

	var profile = null
	if _opponent_registry != null:
		profile = _opponent_registry.call("get_opponent", next_opponent_id)
	if profile == null:
		abandon_active_competition()
		return {
			"success": false,
			"reason": "missing_opponent",
			"opponent_id": String(next_opponent_id),
		}

	_match_active = true
	_pending_change.clear()
	gameplay_event_requested.emit(
		&"tournament_next_round",
		"Next Round",
		str(profile.get("display_name")),
		{
			"opponent_id": String(next_opponent_id),
			"competition": get_competitive_snapshot(),
		},
		0
	)
	backend_state_change_requested.emit("competition_next_round")
	return {
		"success": true,
		"opponent_id": next_opponent_id,
		"profile": profile,
		"locked_cards": locked_cards,
	}


func resolve_pending_reward() -> Dictionary:
	if _service == null:
		return {}
	var pending: Dictionary = _service.call("get_pending_reward")
	if pending.is_empty():
		return {}

	var event_id := StringName(str(pending.get("reward_event_id", "")))
	var source_id := StringName(str(pending.get("reward_source_id", "")))
	if String(event_id).is_empty():
		return {
			"success": false,
			"reason": "pending_reward_missing_event_id",
		}

	if (
		_world_gateway != null
		and bool(
			_world_gateway.call(
				"has_world_reward_event_claimed",
				event_id
			)
		)
	):
		_service.call("acknowledge_pending_reward", event_id)
		return {
			"success": true,
			"reason": "event_already_claimed",
			"event_id": String(event_id),
		}

	if String(source_id).is_empty():
		_service.call("acknowledge_pending_reward", event_id)
		return {
			"success": true,
			"reason": "competition_has_no_reward_source",
			"event_id": String(event_id),
		}

	if _world_gateway == null:
		return {
			"success": false,
			"reason": "world_gateway_unavailable",
		}

	var result: Dictionary = _world_gateway.call(
		"claim_tournament_card_reward",
		source_id,
		event_id,
		StringName(
			"competition:%s"
			% str(pending.get("competition_id", ""))
		),
		true
	)
	var reason: String = str(result.get("reason", ""))
	var resolved: bool = (
		bool(result.get("success", false))
		or reason == "event_already_claimed"
		or reason == "source_complete"
	)
	if resolved:
		if reason == "source_complete" and _world_reward_ledger != null:
			_world_reward_ledger.call("mark_claimed", event_id)
		_service.call("acknowledge_pending_reward", event_id)
		competition_state_changed.emit(get_competitive_snapshot())
	return result


func _player_rank() -> int:
	if _progression != null and _progression.has_method("get_rank_number"):
		return maxi(1, int(_progression.call("get_rank_number")))
	return _fallback_player_rank


func _beaten_opponent_ids() -> PackedStringArray:
	if (
		_encounter_records != null
		and _encounter_records.has_method("get_beaten_opponent_ids")
	):
		return _encounter_records.call("get_beaten_opponent_ids")
	return PackedStringArray()
