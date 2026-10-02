extends RefCounted
class_name TripleTriadRuntimeRecoveryController

signal gameplay_event_requested(
	event_type: StringName,
	title: String,
	detail: String,
	payload: Dictionary,
	priority: int
)
signal checkpoint_requested(reason: String)
signal backend_state_change_requested(reason: String)

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

var _competition = null
var _card_catalog = null
var _world_gateway = null
var _world_reward_ledger = null
var _match_resolution = null
var _match_resolution_journal = null
var _deck_setup = null
var _opponent_registry = null
var _last_recovery: Dictionary = {}


func initialize(
	competition_controller,
	card_catalog,
	world_gateway,
	world_reward_ledger,
	match_resolution,
	match_resolution_journal,
	deck_setup,
	opponent_registry
) -> void:
	_competition = competition_controller
	_card_catalog = card_catalog
	_world_gateway = world_gateway
	_world_reward_ledger = world_reward_ledger
	_match_resolution = match_resolution
	_match_resolution_journal = match_resolution_journal
	_deck_setup = deck_setup
	_opponent_registry = opponent_registry
	_last_recovery.clear()


func get_last_recovery() -> Dictionary:
	return _last_recovery.duplicate(true)


func get_runtime_snapshot() -> Dictionary:
	var pending_resolution: Dictionary = {}
	if _match_resolution_journal != null:
		pending_resolution = _match_resolution_journal.call("get_snapshot")
	var pending_competition_reward: Dictionary = {}
	if _competition != null and _competition.is_ready():
		pending_competition_reward = _competition.get_pending_reward()
	var pending_world_deliveries: Array = []
	if _world_reward_ledger != null:
		pending_world_deliveries = _world_reward_ledger.call(
			"get_pending_deliveries"
		)
	return {
		"last_recovery": _last_recovery.duplicate(true),
		"pending_match_resolution": pending_resolution,
		"pending_competition_reward": pending_competition_reward,
		"pending_world_deliveries": pending_world_deliveries,
	}


func reconcile_runtime_state() -> Dictionary:
	var report := {
		"repaired": false,
		"requires_reward_ui": false,
		"resolution_repaired": false,
		"world_rewards_repaired": 0,
		"competition_reward_repaired": false,
		"stale_tournament_abandoned": false,
		"warnings": [],
	}

	var delivery_report: Dictionary = _reconcile_pending_world_reward_deliveries()
	var delivery_resolved: int = int(delivery_report.get("resolved", 0))
	if delivery_resolved > 0:
		report["repaired"] = true
		report["world_rewards_repaired"] = delivery_resolved
	if int(delivery_report.get("failed", 0)) > 0:
		report["warnings"].append(
			"One or more pending world card rewards could not be reconciled."
		)

	var pending_reward_before: Dictionary = {}
	if _competition != null:
		pending_reward_before = _competition.get_pending_reward()
	if not pending_reward_before.is_empty():
		var reward_result: Dictionary = _competition.resolve_pending_reward()
		var reward_reason: String = str(reward_result.get("reason", ""))
		if (
			bool(reward_result.get("success", false))
			or reward_reason in [
				"event_already_claimed",
				"source_complete",
				"competition_has_no_reward_source",
			]
		):
			report["repaired"] = true
			report["competition_reward_repaired"] = true
		else:
			report["warnings"].append(
				"Pending tournament reward could not be reconciled."
			)

	var pending: Dictionary = {}
	if _match_resolution_journal != null:
		pending = _match_resolution_journal.call("get_snapshot")
	if bool(pending.get("pending", false)):
		var selected_id: String = str(pending.get("selected_card_id", ""))
		var winner: int = int(pending.get("winner", OWNER_NONE))
		var forced_loss_id: String = str(
			pending.get("forced_loss_card_id", "")
		)
		if not selected_id.is_empty():
			var reconcile_result: Dictionary = {}
			if _match_resolution != null:
				reconcile_result = _match_resolution.call(
					"reconcile_selected_pending_resolution",
					pending
				)
			if bool(reconcile_result.get("success", false)):
				if (
					bool(reconcile_result.get("remove_from_decks", false))
					and _deck_setup != null
				):
					_deck_setup.call(
						"remove_card_from_all_profiles",
						StringName(str(reconcile_result.get("card_id", "")))
					)
				_match_resolution_journal.call("clear")
				report["repaired"] = true
				report["resolution_repaired"] = true
				gameplay_event_requested.emit(
					&"match_resolution_recovered",
					"Card Result Recovered",
					"An interrupted card transfer was completed safely.",
					pending.duplicate(true),
					2
				)
			else:
				report["warnings"].append(
					"Selected card resolution could not be reconciled."
				)
		elif winner == OWNER_OPPONENT and forced_loss_id.is_empty():
			_match_resolution_journal.call("clear")
			report["repaired"] = true
			report["resolution_repaired"] = true
		else:
			report["requires_reward_ui"] = true

	if _competition != null:
		var active: Dictionary = _competition.get_active_snapshot()
		if (
			bool(active.get("active", false))
			and bool(active.get("deck_locked", false))
			and _competition.get_locked_deck_cards().size() != 5
		):
			_competition.abandon_active_competition()
			report["repaired"] = true
			report["stale_tournament_abandoned"] = true
			report["warnings"].append(
				"An invalid persisted tournament deck was abandoned safely."
			)
			gameplay_event_requested.emit(
				&"tournament_recovered",
				"Tournament Reset",
				"The saved tournament deck was no longer legal.",
				active.duplicate(true),
				2
			)

	if bool(report["repaired"]):
		checkpoint_requested.emit("runtime_reconcile")
		backend_state_change_requested.emit("runtime_reconcile")
	_last_recovery = report.duplicate(true)
	return report


func build_pending_resolution_resume_payload() -> Dictionary:
	if _match_resolution_journal == null:
		return {"success": false, "reason": "journal_unavailable"}
	var pending: Dictionary = _match_resolution_journal.call("get_snapshot")
	if not bool(pending.get("pending", false)):
		return {"success": false, "reason": "no_pending_resolution"}
	if not str(pending.get("selected_card_id", "")).is_empty():
		return {"success": false, "reason": "selection_already_recorded"}

	var opponent_id := StringName(str(pending.get("opponent_id", "")))
	var winner: int = int(pending.get("winner", OWNER_NONE))
	if (
		String(opponent_id).is_empty()
		or winner not in [OWNER_PLAYER, OWNER_OPPONENT]
	):
		_match_resolution_journal.call("clear")
		return {"success": false, "reason": "invalid_resolution_header"}

	var profile = null
	if _opponent_registry != null:
		profile = _opponent_registry.call("get_opponent", opponent_id)
	var player_cards: Array = _cards_from_ids(
		pending.get("player_card_ids", PackedStringArray())
	)
	var opponent_cards: Array = _cards_from_ids(
		pending.get("opponent_card_ids", PackedStringArray())
	)
	if (
		profile == null
		or player_cards.size() != 5
		or opponent_cards.size() != 5
	):
		_match_resolution_journal.call("clear")
		if (
			_competition != null
			and bool(_competition.get_active_snapshot().get("active", false))
		):
			_competition.abandon_active_competition()
		gameplay_event_requested.emit(
			&"recovery_warning",
			"Card Result Reset",
			"An invalid interrupted result was cleared safely.",
			pending.duplicate(true),
			3
		)
		return {"success": false, "reason": "invalid_resolution_payload"}

	if _competition != null:
		_competition.set_pending_change(
			(pending.get("competition_change", {}) as Dictionary)
		)
	var opponent_take_index: int = -1
	var forced_loss_id: String = str(
		pending.get("forced_loss_card_id", "")
	)
	if winner == OWNER_OPPONENT and not forced_loss_id.is_empty():
		for index in range(player_cards.size()):
			var card = player_cards[index]
			if card != null and String(card.get("card_id")) == forced_loss_id:
				opponent_take_index = index
				break

	var eligible_reward_ids := PackedStringArray()
	var raw_eligible = pending.get(
		"eligible_reward_ids",
		PackedStringArray()
	)
	if raw_eligible is PackedStringArray or raw_eligible is Array:
		for raw_id in raw_eligible:
			eligible_reward_ids.append(str(raw_id))

	return {
		"success": true,
		"pending": pending.duplicate(true),
		"opponent_id": opponent_id,
		"winner": winner,
		"profile": profile,
		"player_cards": player_cards,
		"opponent_cards": opponent_cards,
		"result_reason": StringName(
			str(pending.get("result_reason", "recovered"))
		),
		"surrendered": bool(pending.get("surrendered", false)),
		"opponent_take_index": opponent_take_index,
		"eligible_reward_ids": eligible_reward_ids,
	}


func _reconcile_pending_world_reward_deliveries() -> Dictionary:
	var report := {
		"pending_before": 0,
		"resolved": 0,
		"failed": 0,
	}
	if _world_reward_ledger == null or _world_gateway == null:
		return report
	var deliveries: Array = _world_reward_ledger.call("get_pending_deliveries")
	report["pending_before"] = deliveries.size()
	for raw_delivery in deliveries:
		if not (raw_delivery is Dictionary):
			report["failed"] = int(report["failed"]) + 1
			continue
		var delivery: Dictionary = raw_delivery
		var event_id := StringName(str(delivery.get("event_id", "")))
		var source_type := StringName(str(delivery.get("source_type", "")))
		var source_id := StringName(str(delivery.get("source_id", "")))
		var source_context := StringName(
			str(delivery.get("source_context", ""))
		)
		if (
			String(event_id).is_empty()
			or String(source_type).is_empty()
			or String(source_id).is_empty()
		):
			report["failed"] = int(report["failed"]) + 1
			continue

		var result: Dictionary = _world_gateway.call(
			"claim_world_source_reward",
			source_type,
			source_id,
			source_context,
			event_id,
			true
		)
		if (
			bool(result.get("success", false))
			or str(result.get("reason", "")) == "event_already_claimed"
		):
			report["resolved"] = int(report["resolved"]) + 1
		else:
			report["failed"] = int(report["failed"]) + 1
	return report


func _cards_from_ids(card_ids) -> Array:
	var result: Array = []
	if _card_catalog == null:
		return result
	if not (card_ids is PackedStringArray or card_ids is Array):
		return result
	for raw_id in card_ids:
		var card = _card_catalog.call(
			"get_card_by_id",
			StringName(str(raw_id))
		)
		if card == null:
			return []
		result.append(card)
	return result
