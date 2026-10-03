extends RefCounted
class_name TripleTriadRuntimeStateController

signal gameplay_event_queued(event: Dictionary)
signal backend_state_changed(reason: String)
signal world_progression_changed(snapshot: Dictionary)

const GameplayEventFeedScript = preload(
	"res://scripts/triple_triad/triple_triad_gameplay_event_feed.gd"
)
const SessionControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_session_controller.gd"
)
const DefaultEconomyPolicy = preload(
	"res://data/triple_triad/economy/default_economy_policy.tres"
)

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const PHASE_CLOSED := SessionControllerScript.PHASE_CLOSED
const PHASE_DEALING := SessionControllerScript.PHASE_DEALING
const PHASE_SELECT_CARD := SessionControllerScript.PHASE_SELECT_CARD
const PHASE_SELECT_CELL := SessionControllerScript.PHASE_SELECT_CELL
const PHASE_ANIMATING := SessionControllerScript.PHASE_ANIMATING
const PHASE_AI := SessionControllerScript.PHASE_AI
const PHASE_RESULT := SessionControllerScript.PHASE_RESULT
const PHASE_REWARD := SessionControllerScript.PHASE_REWARD
const PHASE_DECK_SETUP := SessionControllerScript.PHASE_DECK_SETUP
const PHASE_SURRENDER_CONFIRM := SessionControllerScript.PHASE_SURRENDER_CONFIRM

var _backend_version: String = ""
var _state_api = null
var _completion_tracker = null
var _world_progression_director = null
var _world_gateway = null
var _competition = null
var _runtime_recovery = null
var _developer_tools = null
var _session = null
var _match_context = null
var _presentation = null
var _save_integrity = null
var _collection_backend = null
var _match_resolution = null
var _encounter_records = null
var _gameplay_event_feed = GameplayEventFeedScript.new()


func initialize(config: Dictionary) -> void:
	_backend_version = str(config.get("backend_version", ""))
	_state_api = config.get("state_api")
	_completion_tracker = config.get("completion_tracker")
	_world_progression_director = config.get("world_progression_director")
	_world_gateway = config.get("world_gateway")
	_competition = config.get("competition")
	_runtime_recovery = config.get("runtime_recovery")
	_developer_tools = config.get("developer_tools")
	_session = config.get("session")
	_match_context = config.get("match_context")
	_presentation = config.get("presentation")
	_save_integrity = config.get("save_integrity")
	_collection_backend = config.get("collection_backend")
	_match_resolution = config.get("match_resolution")
	_encounter_records = config.get("encounter_records")
	_gameplay_event_feed.initialize(maxi(1, int(config.get("event_capacity", 32))))


func get_backend_health(
	backend_ready: bool,
	backend_errors: PackedStringArray
) -> Dictionary:
	return {
		"backend_version": _backend_version,
		"ready": backend_ready,
		"errors": backend_errors.duplicate(),
		"save_integrity": (
			_save_integrity.get_last_report()
			if _save_integrity != null
			and _save_integrity.has_method("get_last_report")
			else {}
		),
	}


func get_pending_gameplay_events() -> Array:
	return _gameplay_event_feed.get_pending_events()


func pop_next_gameplay_event() -> Dictionary:
	return _gameplay_event_feed.pop_next_event()


func clear_gameplay_events() -> void:
	_gameplay_event_feed.clear()


func queue_gameplay_event(
	event_type: StringName,
	title: String,
	detail: String = "",
	payload: Dictionary = {},
	priority: int = 0
) -> Dictionary:
	var event: Dictionary = _gameplay_event_feed.push_event(
		event_type,
		title,
		detail,
		payload,
		priority
	)
	gameplay_event_queued.emit(event.duplicate(true))
	if _developer_tools != null and _developer_tools.has_method("append_playtest_event"):
		_developer_tools.call(
			"append_playtest_event",
			&"gameplay_event",
			event
		)
	return event


func get_state_api():
	return _state_api


func get_player_snapshot() -> Dictionary:
	if _state_api == null:
		return {}
	return _state_api.get_player_snapshot()


func get_collection_snapshot() -> Array:
	if _state_api == null:
		return []
	return _state_api.get_collection_snapshot()


func get_deck_profiles_snapshot() -> Array:
	if _state_api == null:
		return []
	return _state_api.get_deck_profiles()


func get_opponent_snapshot(opponent_id: StringName) -> Dictionary:
	if _state_api == null:
		return {}
	return _state_api.get_opponent_snapshot(opponent_id)


func get_opponents_snapshot() -> Array:
	if _state_api == null:
		return []
	return _state_api.get_all_opponents_snapshot()


func get_collection_completion_snapshot() -> Dictionary:
	if _completion_tracker == null:
		return {}
	return _completion_tracker.call("get_snapshot")


func get_missing_card_diagnostics() -> Array:
	var snapshot: Dictionary = get_collection_completion_snapshot()
	return snapshot.get("missing_cards", []).duplicate(true)


func get_source_completion_snapshot() -> Array:
	var snapshot: Dictionary = get_collection_completion_snapshot()
	return snapshot.get("source_progress", []).duplicate(true)


func get_global_snapshot() -> Dictionary:
	var snapshot: Dictionary = (
		_state_api.get_global_snapshot()
		if _state_api != null
		else {}
	)
	var open_now: bool = is_open()
	snapshot["runtime"] = {
		"backend_version": _backend_version,
		"is_open": open_now,
		"phase": _session.phase if _session != null else PHASE_CLOSED,
		"active_opponent_id": (
			String(_match_context.active_opponent_id())
			if open_now
			and _match_context != null
			and _match_context.has_method("active_opponent_id")
			else ""
		),
	}
	snapshot["completion"] = get_collection_completion_snapshot()
	snapshot["competitive"] = get_competitive_snapshot()
	snapshot["world_progression"] = get_world_progression_snapshot()
	snapshot["recovery"] = get_runtime_recovery_snapshot()
	return snapshot


func get_world_progression_snapshot() -> Dictionary:
	if _world_progression_director == null:
		return {}
	return _world_progression_director.call(
		"build_snapshot",
		get_player_snapshot(),
		get_onboarding_snapshot(),
		get_competitive_snapshot(),
		get_collection_completion_snapshot(),
		get_available_card_player_ids()
	)


func get_card_economy_snapshot() -> Dictionary:
	var minimum_unique: int = 5
	var protect_collection: bool = true
	var stolen_recoverable: bool = true
	if DefaultEconomyPolicy != null:
		minimum_unique = maxi(
			5,
			int(DefaultEconomyPolicy.minimum_playable_unique_cards)
		)
		protect_collection = bool(
			DefaultEconomyPolicy.protect_minimum_playable_collection
		)
		stolen_recoverable = bool(
			DefaultEconomyPolicy.stolen_cards_recoverable
		)

	var unique_owned: int = 0
	var total_owned: int = 0
	if _collection_backend != null:
		if _collection_backend.has_method("unique_owned_count"):
			unique_owned = int(
				_collection_backend.call("unique_owned_count")
			)
		if _collection_backend.has_method("total_owned_count"):
			total_owned = int(
				_collection_backend.call("total_owned_count")
			)

	var playable_unique: int = 0
	if _match_resolution != null and _match_resolution.has_method("get_playable_owned_cards"):
		playable_unique = _match_resolution.call("get_playable_owned_cards").size()
	var stolen_total: int = 0
	var stolen_by_opponent: Array = []
	if (
		_encounter_records != null
		and _encounter_records.has_method("get_all_recorded_ids")
		and _encounter_records.has_method("get_snapshot")
	):
		for raw_id in _encounter_records.call("get_all_recorded_ids"):
			var opponent_id := StringName(str(raw_id))
			var encounter: Dictionary = _encounter_records.call(
				"get_snapshot",
				opponent_id
			)
			var opponent_stolen: int = int(
				encounter.get("stolen_total", 0)
			)
			if opponent_stolen <= 0:
				continue
			stolen_total += opponent_stolen
			stolen_by_opponent.append({
				"opponent_id": String(opponent_id),
				"stolen_total": opponent_stolen,
				"stolen_quantities": (
					encounter.get("stolen_quantities", {}) as Dictionary
				).duplicate(true),
			})

	return {
		"minimum_playable_unique_cards": minimum_unique,
		"protect_minimum_playable_collection": protect_collection,
		"stolen_cards_recoverable": stolen_recoverable,
		"unique_owned_count": unique_owned,
		"total_owned_count": total_owned,
		"playable_unique_count": playable_unique,
		"minimum_deck_protection_active": (
			protect_collection
			and playable_unique <= minimum_unique
		),
		"stolen_total": stolen_total,
		"stolen_by_opponent": stolen_by_opponent,
	}


func get_runtime_ui_snapshot(
	match_state,
	selected_hand_index: int,
	selected_cell_index: int
) -> Dictionary:
	var selected_card = null
	var selected_rotation: int = 0
	if (
		match_state != null
		and selected_hand_index >= 0
		and selected_hand_index < match_state.player_hand.size()
	):
		selected_card = match_state.player_hand[selected_hand_index]
		selected_rotation = match_state.get_hand_rotation(
			OWNER_PLAYER,
			selected_hand_index
		)

	var player_hand_snapshot: Array = []
	var opponent_hand_snapshot: Array = []
	if match_state != null:
		for hand_index in range(match_state.player_hand.size()):
			player_hand_snapshot.append(
				_runtime_card_snapshot(
					match_state.player_hand[hand_index],
					match_state.get_hand_rotation(OWNER_PLAYER, hand_index)
				)
			)
		var reveal_opponent: bool = (
			_match_context == null
			or _match_context.active_rule_set == null
			or bool(_match_context.active_rule_set.open_rule)
		)
		for hand_index in range(match_state.opponent_hand.size()):
			if reveal_opponent:
				opponent_hand_snapshot.append(
					_runtime_card_snapshot(
						match_state.opponent_hand[hand_index],
						match_state.get_hand_rotation(
							OWNER_OPPONENT,
							hand_index
						)
					)
				)
			else:
				opponent_hand_snapshot.append({"hidden": true})

	var phase: int = _session.phase if _session != null else PHASE_CLOSED
	var placement_preview: Dictionary = {}
	if _presentation != null and _presentation.has_method("get_placement_preview"):
		placement_preview = _presentation.call(
			"get_placement_preview",
			match_state,
			phase,
			selected_hand_index,
			selected_cell_index
		)

	return {
		"schema_version": 2,
		"backend_version": _backend_version,
		"is_open": is_open(),
		"phase": phase,
		"phase_name": phase_name(phase),
		"round_number": _session.round_number if _session != null else 0,
		"match_started": _session.match_started if _session != null else false,
		"current_owner": (
			int(match_state.current_owner)
			if match_state != null
			else OWNER_NONE
		),
		"selected_hand_index": selected_hand_index,
		"selected_cell_index": selected_cell_index,
		"selected_rotation": selected_rotation,
		"selected_card": (
			_runtime_card_snapshot(selected_card, selected_rotation)
			if selected_card != null
			else {}
		),
		"player_hand": player_hand_snapshot,
		"opponent_hand": opponent_hand_snapshot,
		"opponent_hand_count": (
			match_state.opponent_hand.size()
			if match_state != null
			else 0
		),
		"score": match_state.get_score() if match_state != null else {},
		"board_influence": (
			match_state.get_influence_board_snapshot()
			if match_state != null
			and match_state.has_method("get_influence_board_snapshot")
			else []
		),
		"placement_preview": placement_preview,
		"can_surrender": (
			_session != null
			and _session.match_started
			and phase in [PHASE_SELECT_CARD, PHASE_AI]
		),
	}


func runtime_card_snapshot(card, rotation_quarters: int = 0) -> Dictionary:
	return _runtime_card_snapshot(card, rotation_quarters)


func phase_name(phase_value: int) -> String:
	match phase_value:
		PHASE_CLOSED:
			return "closed"
		PHASE_DEALING:
			return "dealing"
		PHASE_SELECT_CARD:
			return "select_card"
		PHASE_SELECT_CELL:
			return "select_cell"
		PHASE_ANIMATING:
			return "animating"
		PHASE_AI:
			return "ai"
		PHASE_RESULT:
			return "result"
		PHASE_REWARD:
			return "reward"
		PHASE_DECK_SETUP:
			return "deck_setup"
		_:
			return "unknown"


func invalidate_state_api(reason: String = "") -> void:
	if _state_api != null and _state_api.has_method("invalidate"):
		_state_api.call("invalidate", reason)


func publish_backend_state_change(reason: String) -> void:
	if _completion_tracker != null:
		_completion_tracker.call("refresh", reason, true)
	invalidate_state_api(reason)
	backend_state_changed.emit(reason)
	if _world_progression_director != null:
		world_progression_changed.emit(get_world_progression_snapshot())


func is_open() -> bool:
	return _session != null and _session.is_open()


func get_onboarding_snapshot() -> Dictionary:
	if _world_gateway == null:
		return {}
	return _world_gateway.get_onboarding_snapshot()


func get_competitive_snapshot() -> Dictionary:
	if _competition == null:
		return {}
	return _competition.get_competitive_snapshot()


func get_runtime_recovery_snapshot() -> Dictionary:
	if _runtime_recovery == null:
		return {}
	return _runtime_recovery.get_runtime_snapshot()


func get_available_card_player_ids() -> PackedStringArray:
	if _world_gateway == null:
		return PackedStringArray()
	return _world_gateway.get_available_card_player_ids()


func _runtime_card_snapshot(card, rotation_quarters: int = 0) -> Dictionary:
	if card == null:
		return {}
	var ranks: Array[int] = []
	for side in range(4):
		if card.has_method("rank_for_side_rotated"):
			ranks.append(int(card.call("rank_for_side_rotated", side, rotation_quarters)))
		else:
			ranks.append(int(card.call("rank_for_side", side)))
	return {
		"card_id": String(card.get("card_id")),
		"display_name": str(card.get("display_name")),
		"rotation": posmod(rotation_quarters, 4),
		"ranks": ranks,
		"deck_cost": int(card.get("deck_cost")),
		"influence": (
			card.call("get_influence_snapshot", rotation_quarters)
			if card.has_method("get_influence_snapshot")
			else {
				"mode": "none",
				"strength": 0,
				"display_name": "None",
				"description": "This card does not project Influence.",
				"rotation_quarters": posmod(rotation_quarters, 4),
				"offsets": [],
				"grid": {
					"width": 1,
					"height": 1,
					"origin": [0, 0],
					"cells": [[2]],
				},
			}
		),
	}
