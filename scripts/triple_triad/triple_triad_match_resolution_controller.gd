extends RefCounted

# Persistent match-result and mandatory card-transfer coordinator.
# Owns progression/result bookkeeping, reward eligibility, transfer journaling,
# and interrupted-transfer reconciliation. It deliberately owns no UI, scene
# transitions, gameplay-event presentation, or save-integrity checkpoints.

const OpponentCollectionScript = preload(
	"res://scripts/triple_triad/triple_triad_opponent_collection.gd"
)

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

var _card_catalog = null
var _collection_backend = null
var _progression = null
var _encounter_records = null
var _competition_service = null
var _card_economy = null
var _acquisition_tracker = null
var _resolution_journal = null
var _stake_policy = null
var _economy_policy: Resource = null
var _acquisition_policy: Resource = null


func initialize(
	card_catalog,
	collection_backend,
	progression,
	encounter_records,
	competition_service,
	card_economy,
	acquisition_tracker,
	resolution_journal,
	stake_policy,
	economy_policy: Resource,
	acquisition_policy: Resource
) -> void:
	_card_catalog = card_catalog
	_collection_backend = collection_backend
	_progression = progression
	_encounter_records = encounter_records
	_competition_service = competition_service
	_card_economy = card_economy
	_acquisition_tracker = acquisition_tracker
	_resolution_journal = resolution_journal
	_stake_policy = stake_policy
	_economy_policy = economy_policy
	_acquisition_policy = acquisition_policy


func record_match_result(
	winner: int,
	result_reason: StringName,
	surrendered: bool,
	opponent_profile: Resource,
	opponent_id: StringName,
	qa_match: bool,
	competition_match_active: bool,
	starting_player_cards: Array,
	starting_opponent_cards: Array,
	opponent_collection_backend
) -> Dictionary:
	var progression_change: Dictionary = {}
	var competition_change: Dictionary = {}
	var next_competition_match_active: bool = competition_match_active
	var competition_state_changed: bool = false

	# QA/debug matches must never mutate permanent progression. Campaign points
	# are first-clear rewards by default; rematches may use an authored override.
	if _progression != null and not qa_match:
		var already_beaten: bool = false
		if _encounter_records != null:
			var previous_record: Dictionary = _encounter_records.get_snapshot(
				opponent_id
			)
			already_beaten = bool(previous_record.get("beaten_before", false))

		var progression_override: int = -1
		if winner == OWNER_PLAYER and opponent_profile != null:
			var first_win_only_value = opponent_profile.get(
				"first_win_progression_only"
			)
			if bool(first_win_only_value) and already_beaten:
				progression_override = maxi(
					0,
					int(opponent_profile.get(
						"rematch_progression_points_on_win"
					))
				)

		progression_change = _progression.record_result(
			winner,
			OWNER_PLAYER,
			opponent_profile,
			progression_override
		)
		if _encounter_records != null:
			_encounter_records.record_result(
				opponent_id,
				winner,
				OWNER_PLAYER,
				OWNER_OPPONENT
			)

	if (
		competition_match_active
		and not qa_match
		and _competition_service != null
	):
		competition_change = _competition_service.call(
			"record_match_result",
			opponent_id,
			winner,
			OWNER_PLAYER
		)
		if winner != OWNER_NONE:
			next_competition_match_active = false
		competition_state_changed = true

	var journal_started: bool = false
	if winner in [OWNER_PLAYER, OWNER_OPPONENT] and not qa_match:
		journal_started = _begin_resolution_journal(
			winner,
			result_reason,
			surrendered,
			opponent_profile,
			opponent_id,
			starting_player_cards,
			starting_opponent_cards,
			opponent_collection_backend,
			competition_change
		)

	return {
		"progression": progression_change,
		"competition": competition_change,
		"competition_match_active": next_competition_match_active,
		"competition_state_changed": competition_state_changed,
		"journal_started": journal_started,
	}


func prepare_reward_presentation(
	winner: int,
	opponent_profile: Resource,
	opponent_id: StringName,
	starting_player_cards: Array,
	starting_opponent_cards: Array,
	opponent_collection_backend
) -> Dictionary:
	var opponent_take_index: int = -1
	var eligible_reward_ids := PackedStringArray()
	var used_journal: bool = false
	var pending_resolution: Dictionary = {}
	if _resolution_journal != null:
		pending_resolution = _resolution_journal.get_snapshot()

	if (
		bool(pending_resolution.get("pending", false))
		and str(pending_resolution.get("opponent_id", "")) == String(opponent_id)
		and int(pending_resolution.get("winner", OWNER_NONE)) == winner
	):
		used_journal = true
		var raw_eligible = pending_resolution.get(
			"eligible_reward_ids",
			PackedStringArray()
		)
		if raw_eligible is PackedStringArray or raw_eligible is Array:
			for raw_id in raw_eligible:
				eligible_reward_ids.append(str(raw_id))

		var forced_loss_id: String = str(
			pending_resolution.get("forced_loss_card_id", "")
		)
		if winner == OWNER_OPPONENT and not forced_loss_id.is_empty():
			for index in range(starting_player_cards.size()):
				var card = starting_player_cards[index]
				if card != null and String(card.card_id) == forced_loss_id:
					opponent_take_index = index
					break
	else:
		if winner == OWNER_OPPONENT:
			opponent_take_index = choose_safe_player_stake_index(
				starting_player_cards
			)
		elif winner == OWNER_PLAYER:
			eligible_reward_ids = player_reward_candidate_ids(
				opponent_profile,
				opponent_collection_backend,
				starting_opponent_cards
			)

	return {
		"opponent_take_index": opponent_take_index,
		"eligible_reward_ids": eligible_reward_ids,
		"used_journal": used_journal,
	}


func commit_reward_transfer(
	card_definition,
	winner: int,
	opponent_id: StringName,
	opponent_collection_backend
) -> Dictionary:
	if card_definition == null:
		return {"success": false, "reason": "missing_card"}
	if _card_economy == null or opponent_collection_backend == null:
		return {"success": false, "reason": "economy_unavailable"}

	var transfer_state: Dictionary = prepare_reward_transfer_state(
		card_definition,
		winner,
		opponent_id,
		opponent_collection_backend
	)
	if transfer_state.is_empty():
		return {"success": false, "reason": "invalid_transfer_state"}

	var journal_pending: bool = (
		_resolution_journal != null
		and _resolution_journal.has_pending()
	)
	if journal_pending:
		if not _resolution_journal.record_selection(
			StringName(card_definition.card_id),
			transfer_state
		):
			return {"success": false, "reason": "journal_selection_failed"}

	var transfer_success: bool = false
	if winner == OWNER_PLAYER:
		transfer_success = _card_economy.transfer_opponent_to_player(
			card_definition,
			_collection_backend,
			opponent_collection_backend
		)
	elif winner == OWNER_OPPONENT:
		transfer_success = _card_economy.transfer_player_to_opponent(
			card_definition,
			_collection_backend,
			opponent_collection_backend
		)
	else:
		return {"success": false, "reason": "invalid_winner"}

	if not transfer_success:
		return {"success": false, "reason": "transfer_failed"}

	if journal_pending:
		_resolution_journal.mark_transfer_committed()

	var metadata_ok: bool = _reconcile_reward_metadata_from_state(
		transfer_state
	)
	if journal_pending and metadata_ok:
		_resolution_journal.mark_metadata_committed()

	var remove_from_decks: bool = (
		winner == OWNER_OPPONENT
		and _collection_backend != null
		and not _collection_backend.owns_card(card_definition)
	)
	return {
		"success": true,
		"reason": "ok",
		"metadata_ok": metadata_ok,
		"remove_from_decks": remove_from_decks,
		"transfer_state": transfer_state,
	}


func prepare_reward_transfer_state(
	card_definition,
	winner: int,
	opponent_id: StringName,
	opponent_collection_backend
) -> Dictionary:
	if (
		card_definition == null
		or _collection_backend == null
		or opponent_collection_backend == null
	):
		return {}
	if winner not in [OWNER_PLAYER, OWNER_OPPONENT]:
		return {}

	var card_id := StringName(str(card_definition.get("card_id")))
	var player_before: int = _collection_backend.get_quantity_by_id(card_id)
	var opponent_before: int = opponent_collection_backend.get_quantity_by_id(
		card_id
	)
	var desired_player: int = player_before
	var desired_opponent: int = opponent_before
	if winner == OWNER_PLAYER:
		desired_player += 1
		desired_opponent = maxi(0, desired_opponent - 1)
	else:
		desired_player = maxi(0, desired_player - 1)
		desired_opponent += 1

	var history: Dictionary = {}
	if _acquisition_tracker != null:
		history = _acquisition_tracker.get_card_history(card_id)
	var acquired_before: int = maxi(0, int(history.get("acquired", 0)))
	var lost_before: int = maxi(0, int(history.get("lost", 0)))

	var encounter: Dictionary = {}
	if _encounter_records != null:
		encounter = _encounter_records.get_snapshot(opponent_id)
	var stolen_quantities: Dictionary = encounter.get(
		"stolen_quantities",
		{}
	)
	var stolen_before: int = maxi(
		0,
		int(stolen_quantities.get(String(card_id), 0))
	)
	var desired_stolen: int = stolen_before
	var desired_cards_won: int = maxi(
		0,
		int(encounter.get("cards_won_from_opponent", 0))
	)
	var desired_cards_lost: int = maxi(
		0,
		int(encounter.get("cards_lost_to_opponent", 0))
	)
	var desired_recovered: int = maxi(
		0,
		int(encounter.get("stolen_cards_recovered", 0))
	)
	var desired_acquired: int = acquired_before
	var desired_lost: int = lost_before

	if winner == OWNER_PLAYER:
		desired_acquired += 1
		desired_cards_won += 1
		if stolen_before > 0:
			desired_stolen = stolen_before - 1
			desired_recovered += 1
	else:
		desired_lost += 1
		desired_cards_lost += 1
		desired_stolen = stolen_before + 1

	return {
		"card_id": String(card_id),
		"winner": winner,
		"opponent_id": String(opponent_id),
		"player_before": player_before,
		"opponent_before": opponent_before,
		"desired_player": desired_player,
		"desired_opponent": desired_opponent,
		"promote_for_rematch": winner == OWNER_OPPONENT,
		"desired_acquired": desired_acquired,
		"desired_lost": desired_lost,
		"desired_cards_won": desired_cards_won,
		"desired_cards_lost": desired_cards_lost,
		"desired_stolen_recovered": desired_recovered,
		"desired_stolen_quantity": desired_stolen,
	}


func reconcile_selected_pending_resolution(
	pending: Dictionary
) -> Dictionary:
	if (
		_card_catalog == null
		or _collection_backend == null
		or _card_economy == null
		or _resolution_journal == null
	):
		return {"success": false, "reason": "resolution_unavailable"}

	var selected_id := StringName(str(pending.get("selected_card_id", "")))
	var opponent_id := StringName(str(pending.get("opponent_id", "")))
	var raw_transfer_state = pending.get("transfer_state", {})
	if not (raw_transfer_state is Dictionary):
		return {"success": false, "reason": "invalid_transfer_state"}
	var transfer_state: Dictionary = (
		raw_transfer_state as Dictionary
	).duplicate(true)
	if (
		String(selected_id).is_empty()
		or String(opponent_id).is_empty()
		or transfer_state.is_empty()
	):
		return {"success": false, "reason": "incomplete_resolution"}

	var card = _card_catalog.get_card_by_id(selected_id)
	if card == null:
		return {"success": false, "reason": "card_missing"}

	var desired_player: int = maxi(
		0,
		int(transfer_state.get("desired_player", 0))
	)
	var desired_opponent: int = maxi(
		0,
		int(transfer_state.get("desired_opponent", 0))
	)
	var opponent_collection = OpponentCollectionScript.new()
	opponent_collection.initialize(
		_card_catalog,
		opponent_id,
		1,
		10,
		50,
		null
	)
	var ownership_matches: bool = (
		_collection_backend.get_quantity_by_id(selected_id) == desired_player
		and opponent_collection.get_quantity_by_id(selected_id) == desired_opponent
	)
	if not ownership_matches:
		if not bool(
			_card_economy.call(
				"reconcile_quantities",
				_card_catalog,
				selected_id,
				opponent_id,
				desired_player,
				desired_opponent,
				_collection_backend,
				bool(transfer_state.get("promote_for_rematch", false))
			)
		):
			return {"success": false, "reason": "ownership_reconcile_failed"}

	_resolution_journal.mark_transfer_committed()
	if not _reconcile_reward_metadata_from_state(transfer_state):
		return {"success": false, "reason": "metadata_reconcile_failed"}
	_resolution_journal.mark_metadata_committed()

	var remove_from_decks: bool = (
		int(pending.get("winner", OWNER_NONE)) == OWNER_OPPONENT
		and not _collection_backend.owns_card(card)
	)
	return {
		"success": true,
		"reason": "ok",
		"card_id": String(selected_id),
		"remove_from_decks": remove_from_decks,
	}


func choose_safe_player_stake_index(
	starting_player_cards: Array
) -> int:
	if _stake_policy == null:
		return -1

	var minimum_unique: int = 5
	var protect_collection: bool = true
	if _economy_policy != null:
		minimum_unique = maxi(
			5,
			int(_economy_policy.get("minimum_playable_unique_cards"))
		)
		protect_collection = bool(
			_economy_policy.get("protect_minimum_playable_collection")
		)

	if not protect_collection:
		return _stake_policy.choose_lost_card_index(starting_player_cards)

	var playable_cards: Array = get_playable_owned_cards()
	var quantities: Dictionary = {}
	if (
		_collection_backend != null
		and _collection_backend.has_method("get_quantities_snapshot")
	):
		quantities = _collection_backend.call("get_quantities_snapshot")

	return _stake_policy.choose_lost_card_index(
		starting_player_cards,
		playable_cards,
		quantities,
		minimum_unique
	)


func get_playable_owned_cards() -> Array:
	var result: Array = []
	if _collection_backend == null:
		return result
	if not _collection_backend.has_method("get_owned_cards"):
		return result

	var player_rank: int = 1
	if _progression != null and _progression.has_method("get_rank_number"):
		player_rank = maxi(1, int(_progression.call("get_rank_number")))

	for card in _collection_backend.call("get_owned_cards"):
		if card == null:
			continue
		var usable: bool = true
		if (
			_acquisition_policy != null
			and _acquisition_policy.has_method("can_use_card")
		):
			usable = bool(
				_acquisition_policy.call(
					"can_use_card",
					card,
					player_rank
				)
			)
		if usable:
			result.append(card)
	return result


func player_reward_candidate_ids(
	opponent_profile: Resource,
	opponent_collection_backend,
	starting_opponent_cards: Array
) -> PackedStringArray:
	if opponent_profile == null:
		return PackedStringArray()

	var raw_reward_ids = opponent_profile.get("reward_card_ids")
	var reward_ids: Dictionary = {}
	if raw_reward_ids is PackedStringArray or raw_reward_ids is Array:
		for raw_id in raw_reward_ids:
			reward_ids[str(raw_id)] = true

	# Priority cards are cards this opponent previously won from the player.
	# They are always valid reward choices so rematches can recover stolen cards.
	var priority_ids: Dictionary = {}
	if (
		opponent_collection_backend != null
		and opponent_collection_backend.has_method("get_priority_ids")
	):
		for raw_id in opponent_collection_backend.call("get_priority_ids"):
			priority_ids[str(raw_id)] = true

	if reward_ids.is_empty() and priority_ids.is_empty():
		return PackedStringArray()

	var result := PackedStringArray()
	for card in starting_opponent_cards:
		if card == null:
			continue
		var card_id: String = String(card.card_id)
		if reward_ids.has(card_id) or priority_ids.has(card_id):
			result.append(card_id)

	# Empty means "all cards eligible" in RewardView. This safety fallback avoids
	# a mandatory-stake soft lock if authored content and a migrated save drift.
	return result


func _begin_resolution_journal(
	winner: int,
	result_reason: StringName,
	surrendered: bool,
	opponent_profile: Resource,
	opponent_id: StringName,
	starting_player_cards: Array,
	starting_opponent_cards: Array,
	opponent_collection_backend,
	competition_change: Dictionary
) -> bool:
	if (
		_resolution_journal == null
		or opponent_profile == null
		or starting_player_cards.size() != 5
		or starting_opponent_cards.size() != 5
	):
		return false
	if _resolution_journal.has_pending():
		push_warning(
			"TripleTriadMatchResolutionController: refusing to overwrite an unresolved match-resolution journal."
		)
		return false

	var forced_loss_card_id: String = ""
	if winner == OWNER_OPPONENT:
		var loss_index: int = choose_safe_player_stake_index(
			starting_player_cards
		)
		if loss_index >= 0 and loss_index < starting_player_cards.size():
			var lost_card = starting_player_cards[loss_index]
			if lost_card != null:
				forced_loss_card_id = String(lost_card.card_id)

	var eligible_reward_ids := PackedStringArray()
	if winner == OWNER_PLAYER:
		eligible_reward_ids = player_reward_candidate_ids(
			opponent_profile,
			opponent_collection_backend,
			starting_opponent_cards
		)

	var saved: bool = _resolution_journal.begin_resolution({
		"opponent_id": String(opponent_id),
		"winner": winner,
		"result_reason": String(result_reason),
		"surrendered": surrendered,
		"player_card_ids": _card_ids(starting_player_cards),
		"opponent_card_ids": _card_ids(starting_opponent_cards),
		"eligible_reward_ids": eligible_reward_ids,
		"forced_loss_card_id": forced_loss_card_id,
		"competition_change": competition_change.duplicate(true),
	})
	if not saved:
		push_warning(
			"TripleTriadMatchResolutionController: could not persist the mandatory reward-resolution journal."
		)
	return saved


func _reconcile_reward_metadata_from_state(
	transfer_state: Dictionary
) -> bool:
	if transfer_state.is_empty():
		return false
	var card_id := StringName(str(transfer_state.get("card_id", "")))
	var opponent_id := StringName(str(transfer_state.get("opponent_id", "")))
	var winner: int = int(transfer_state.get("winner", OWNER_NONE))
	if (
		String(card_id).is_empty()
		or String(opponent_id).is_empty()
		or winner not in [OWNER_PLAYER, OWNER_OPPONENT]
	):
		return false

	var source: StringName = (
		&"opponent_win"
		if winner == OWNER_PLAYER
		else &"opponent_loss"
	)
	var tracker_ok: bool = true
	if _acquisition_tracker != null:
		tracker_ok = bool(
			_acquisition_tracker.call(
				"reconcile_card_history",
				card_id,
				int(transfer_state.get("desired_acquired", 0)),
				int(transfer_state.get("desired_lost", 0)),
				source,
				opponent_id
			)
		)

	var encounter_ok: bool = true
	if _encounter_records != null:
		encounter_ok = bool(
			_encounter_records.call(
				"reconcile_card_transfer",
				opponent_id,
				card_id,
				int(transfer_state.get("desired_cards_won", 0)),
				int(transfer_state.get("desired_cards_lost", 0)),
				int(transfer_state.get("desired_stolen_recovered", 0)),
				int(transfer_state.get("desired_stolen_quantity", 0))
			)
		)
	return tracker_ok and encounter_ok


func _card_ids(cards: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for card in cards:
		if card == null:
			continue
		var card_id: String = str(card.get("card_id")).strip_edges()
		if not card_id.is_empty():
			result.append(card_id)
	return result
