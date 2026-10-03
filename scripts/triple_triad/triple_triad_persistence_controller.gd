extends RefCounted
class_name TripleTriadPersistenceController

# Persistence/progression boundary for the Triple Triad scene facade.
# Owns save-integrity checkpoints, persistent match-result bookkeeping,
# mandatory card-transfer side effects, and collection milestone events.
# It deliberately owns no UI transitions, match animation, or input routing.

signal gameplay_event_requested(
	event_type: StringName,
	title: String,
	detail: String,
	payload: Dictionary,
	priority: int
)
signal backend_state_change_requested(reason: String)
signal state_api_invalidation_requested(reason: String)
signal card_reward_selected(card_definition)

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

var _save_integrity = null
var _card_catalog = null
var _collection_backend = null
var _progression = null
var _match_resolution = null
var _match_resolution_journal = null
var _competition = null
var _deck_setup = null
var _live_match = null
var _match_context = null
var _acquisition_policy: Resource = null
var _player_deck_budget: int = 30


func initialize(config: Dictionary) -> void:
	_save_integrity = config.get("save_integrity")
	_card_catalog = config.get("card_catalog")
	_collection_backend = config.get("collection_backend")
	_progression = config.get("progression")
	_match_resolution = config.get("match_resolution")
	_match_resolution_journal = config.get("match_resolution_journal")
	_competition = config.get("competition")
	_deck_setup = config.get("deck_setup")
	_live_match = config.get("live_match")
	_match_context = config.get("match_context")
	_acquisition_policy = config.get("acquisition_policy")
	_player_deck_budget = maxi(5, int(config.get("player_deck_budget", 30)))


func checkpoint(reason: String) -> Dictionary:
	if _save_integrity == null:
		return {}
	if _card_catalog == null or _collection_backend == null or _progression == null:
		return {}

	var report: Dictionary = _save_integrity.audit_and_checkpoint(
		_card_catalog,
		_collection_backend,
		_progression,
		_player_deck_budget,
		reason,
		_acquisition_policy
	)
	if not bool(report.get("valid", true)):
		push_warning(
			"TripleTriadPersistenceController: save integrity checkpoint '%s' reported: %s"
			% [reason, str(report.get("warnings", []))]
		)
	state_api_invalidation_requested.emit("integrity_checkpoint")
	return report


func record_match_outcome(
	score: Dictionary,
	winner: int,
	result_reason: StringName,
	surrendered: bool,
	starting_player_cards: Array,
	starting_opponent_cards: Array,
	opponent_collection_backend
) -> Dictionary:
	if _match_resolution == null or _match_context == null:
		return {
			"success": false,
			"winner": winner,
			"score": score.duplicate(true),
			"progression": {},
			"competition": {},
			"reason": String(result_reason),
			"surrendered": surrendered,
		}

	var qa_match: bool = _match_context.get("qa_profile_override") != null
	var resolution: Dictionary = _match_resolution.record_match_result(
		winner,
		result_reason,
		surrendered,
		_match_context.get("active_opponent_profile"),
		_match_context.call("active_opponent_id"),
		qa_match,
		_competition != null and _competition.call("is_match_active"),
		starting_player_cards,
		starting_opponent_cards,
		opponent_collection_backend
	)
	var progression_change: Dictionary = (
		resolution.get("progression", {}) as Dictionary
	).duplicate(true)
	var competition_change: Dictionary = {}
	if _competition != null:
		competition_change = (
			_competition.call("apply_match_resolution", resolution) as Dictionary
		).duplicate(true)

	if bool(progression_change.get("rank_up", false)):
		gameplay_event_requested.emit(
			&"duel_rank_up",
			"Duel Rank %d" % int(progression_change.get("rank_after", 1)),
			str(progression_change.get("rank_name", "")),
			progression_change.duplicate(true),
			2
		)

	backend_state_change_requested.emit("match_result")
	return {
		"success": true,
		"winner": winner,
		"score": score.duplicate(true),
		"progression": progression_change,
		"competition": competition_change,
		"reason": String(result_reason),
		"surrendered": surrendered,
	}


func commit_reward_transfer(
	card_definition,
	winner: int,
	opponent_collection_backend
) -> Dictionary:
	if card_definition == null:
		return {
			"success": false,
			"reason": "missing_card",
			"error_message": transfer_failure_message("missing_card"),
		}
	if _match_resolution == null or _match_context == null:
		return {
			"success": false,
			"reason": "persistence_unavailable",
			"error_message": transfer_failure_message("persistence_unavailable"),
		}

	var opponent_id: StringName = _match_context.call("active_opponent_id")
	var transfer_result: Dictionary = _match_resolution.commit_reward_transfer(
		card_definition,
		winner,
		opponent_id,
		opponent_collection_backend
	)
	if not bool(transfer_result.get("success", false)):
		var failure_reason: String = str(
			transfer_result.get("reason", "unknown")
		)
		var error_message: String = transfer_failure_message(failure_reason)
		transfer_result["error_message"] = error_message
		push_error(error_message)
		return transfer_result

	var metadata_ok: bool = bool(transfer_result.get("metadata_ok", false))
	var card_id := StringName(str(card_definition.get("card_id")))
	var display_name: String = str(card_definition.get("display_name"))
	var opponent_name: String = str(
		_match_context.call("active_opponent_display_name")
	)

	if winner == OWNER_PLAYER:
		card_reward_selected.emit(card_definition)
		gameplay_event_requested.emit(
			&"opponent_card_won",
			display_name,
			"Won from %s." % opponent_name,
			{
				"card_id": String(card_id),
				"opponent_id": String(opponent_id),
			},
			1
		)
	elif winner == OWNER_OPPONENT:
		gameplay_event_requested.emit(
			&"card_lost",
			display_name,
			"Lost to %s. Win it back in a rematch." % opponent_name,
			{
				"card_id": String(card_id),
				"opponent_id": String(opponent_id),
			},
			1
		)
		if bool(transfer_result.get("remove_from_decks", false)):
			if _deck_setup != null:
				_deck_setup.call("remove_card_from_all_profiles", card_id)
			if _live_match != null:
				_live_match.call("remove_card_from_active_deck", card_id)

	if not metadata_ok:
		push_warning(
			"TripleTriadPersistenceController: ownership transfer succeeded but reward metadata reconciliation reported a problem."
		)

	checkpoint("reward_transfer")
	backend_state_change_requested.emit("card_transfer")
	return transfer_result


func complete_reward_resolution() -> Dictionary:
	if _match_resolution_journal != null:
		_match_resolution_journal.call("clear")
	return checkpoint("reward_resolution_complete")


func on_collection_milestone_reached(
	unique_card_count: int,
	snapshot: Dictionary
) -> void:
	gameplay_event_requested.emit(
		&"collection_milestone",
		"%d Cards Collected" % unique_card_count,
		"Collection progress: %.1f%%"
		% float(snapshot.get("completion_percent", 0.0)),
		{
			"unique_card_count": unique_card_count,
			"completion": snapshot.duplicate(true),
		},
		1
	)


func on_collection_completed(snapshot: Dictionary) -> void:
	gameplay_event_requested.emit(
		&"collection_complete",
		"179 / 179 Cards",
		"Card collection complete.",
		snapshot.duplicate(true),
		3
	)


func transfer_failure_message(reason: String) -> String:
	match reason:
		"missing_card":
			return "TripleTriadPersistenceController: reward transfer is missing a card."
		"economy_unavailable":
			return "TripleTriadPersistenceController: card economy is unavailable during reward transfer."
		"journal_selection_failed":
			return "TripleTriadPersistenceController: could not journal the mandatory card selection."
		"transfer_failed":
			return "TripleTriadPersistenceController: failed to commit the mandatory card transfer."
		"persistence_unavailable":
			return "TripleTriadPersistenceController: persistence services are unavailable during reward transfer."
		_:
			return "TripleTriadPersistenceController: reward transfer rejected (%s)." % reason
