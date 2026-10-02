extends RefCounted

# Deterministic match-flow coordinator for Triple Triad.
# Owns turn sequencing and lifecycle decisions, but deliberately owns no UI,
# persistence, progression, reward transfer, or scene-tree state.

const SessionControllerScript = preload("res://scripts/triple_triad/triple_triad_session_controller.gd")

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2
const PHASE_AI := SessionControllerScript.PHASE_AI

var _match = null
var _ai = null
var _rng: RandomNumberGenerator = null
var _session = null


func initialize(
	match_state,
	ai_controller,
	rng: RandomNumberGenerator,
	session_controller
) -> void:
	_match = match_state
	_ai = ai_controller
	_rng = rng
	_session = session_controller


func is_ready() -> bool:
	return (
		_match != null
		and _ai != null
		and _rng != null
		and _session != null
	)


func prepare_match(
	player_cards: Array,
	opponent_cards: Array,
	starting_owner: int,
	rule_set: Resource,
	region_profile: Resource
) -> Dictionary:
	if not is_ready():
		return {"success": false, "reason": "flow_not_initialized"}
	if player_cards.size() != 5:
		return {"success": false, "reason": "invalid_player_hand"}
	if opponent_cards.size() != 5:
		return {"success": false, "reason": "invalid_opponent_hand"}

	var clean_owner: int = (
		starting_owner
		if starting_owner in [OWNER_PLAYER, OWNER_OPPONENT]
		else OWNER_PLAYER
	)
	_session.prepare_new_match()
	_match.reset_match(
		player_cards,
		opponent_cards,
		clean_owner,
		rule_set,
		region_profile
	)
	_session.begin_dealing()
	return {
		"success": true,
		"starting_owner": clean_owner,
		"selected_hand_index": 0,
		"selected_cell_index": 4,
	}


func complete_deal(starting_owner: int) -> Dictionary:
	if not is_ready():
		return {"success": false, "reason": "flow_not_initialized"}
	_session.complete_deal(starting_owner)
	return {
		"success": true,
		"phase": _session.phase,
		"schedule_ai": _session.phase == PHASE_AI,
	}


func commit_player_move(
	selected_hand_index: int,
	selected_cell_index: int
) -> Dictionary:
	if not is_ready():
		return {"success": false, "reason": "flow_not_initialized"}
	if selected_hand_index < 0 or selected_hand_index >= _match.player_hand.size():
		return {"success": false, "reason": "invalid_hand_index"}
	if selected_cell_index < 0 or selected_cell_index >= 9:
		return {"success": false, "reason": "invalid_cell_index"}
	if _match.board[selected_cell_index] != null:
		return {"success": false, "reason": "occupied"}

	var played_card = _match.player_hand[selected_hand_index]
	var played_rotation: int = _match.get_hand_rotation(
		OWNER_PLAYER,
		selected_hand_index
	)
	var target_rank_bonus: int = _match.get_cell_rank_bonus(
		selected_cell_index
	)
	var result: Dictionary = _match.place_card(
		OWNER_PLAYER,
		selected_hand_index,
		selected_cell_index
	)
	if not bool(result.get("success", false)):
		return {
			"success": false,
			"reason": str(result.get("reason", "invalid_move")),
		}

	var next_hand_index: int = clampi(
		selected_hand_index,
		0,
		maxi(_match.player_hand.size() - 1, 0)
	)
	_session.begin_animation()
	return {
		"success": true,
		"played_card": played_card,
		"played_rotation": played_rotation,
		"hand_index": selected_hand_index,
		"cell_index": selected_cell_index,
		"placement_rank_modifier": int(
			result.get("placed_total_modifier", target_rank_bonus)
		),
		"next_hand_index": next_hand_index,
		"result": result,
	}


func complete_player_move(result: Dictionary) -> StringName:
	if not is_ready():
		return &"ignored"
	if bool(result.get("game_over", false)):
		return &"finish"
	_session.begin_ai_turn()
	return &"schedule_ai"


func commit_ai_move(active_ai_profile: Resource) -> Dictionary:
	if not is_ready():
		return {"success": false, "reason": "flow_not_initialized", "finish": true}

	var move: Dictionary = _ai.choose_move(
		_match,
		OWNER_OPPONENT,
		_rng,
		active_ai_profile
	)
	if not bool(move.get("valid", false)):
		return {"success": false, "reason": "no_valid_ai_move", "finish": true}

	var hand_index: int = int(move.get("hand_index", 0))
	var cell_index: int = int(move.get("cell_index", 0))
	if hand_index < 0 or hand_index >= _match.opponent_hand.size():
		return {"success": false, "reason": "invalid_ai_hand_index", "finish": true}
	if cell_index < 0 or cell_index >= 9:
		return {"success": false, "reason": "invalid_ai_cell_index", "finish": true}

	if bool(move.get("rotate", false)):
		_match.rotate_hand_card(OWNER_OPPONENT, hand_index)
	var played_card = _match.opponent_hand[hand_index]
	var played_rotation: int = _match.get_hand_rotation(
		OWNER_OPPONENT,
		hand_index
	)
	var target_rank_bonus: int = _match.get_cell_rank_bonus(cell_index)
	var result: Dictionary = _match.place_card(
		OWNER_OPPONENT,
		hand_index,
		cell_index
	)
	if not bool(result.get("success", false)):
		return {
			"success": false,
			"reason": str(result.get("reason", "invalid_ai_move")),
			"finish": true,
		}

	_session.begin_animation()
	return {
		"success": true,
		"played_card": played_card,
		"played_rotation": played_rotation,
		"hand_index": hand_index,
		"cell_index": cell_index,
		"placement_rank_modifier": int(
			result.get("placed_total_modifier", target_rank_bonus)
		),
		"result": result,
	}


func complete_ai_move(
	result: Dictionary,
	selected_hand_index: int,
	selected_cell_index: int
) -> Dictionary:
	if not is_ready():
		return {"action": &"ignored"}
	if bool(result.get("game_over", false)):
		return {"action": &"finish"}

	_session.begin_player_turn()
	return {
		"action": &"player_turn",
		"selected_hand_index": clampi(
			selected_hand_index,
			0,
			maxi(_match.player_hand.size() - 1, 0)
		),
		"selected_cell_index": nearest_empty_cell(selected_cell_index),
	}


func can_run_ai_timer() -> bool:
	return (
		is_ready()
		and _session.phase == PHASE_AI
		and not _match.game_over
	)


func request_surrender() -> StringName:
	if not is_ready():
		return &"ignored"
	if not _session.match_started:
		return &"close"
	if not _session.request_surrender():
		return &"ignored"
	return &"confirm"


func confirm_surrender() -> void:
	if is_ready():
		_session.confirm_surrender()


func cancel_surrender() -> Dictionary:
	if not is_ready():
		return {"resume_phase": -1, "schedule_ai": false}
	var resume_phase: int = _session.cancel_surrender()
	return {
		"resume_phase": resume_phase,
		"schedule_ai": resume_phase == PHASE_AI,
	}


func finish_match(
	forced_winner: int = OWNER_NONE,
	reason: StringName = &"board_complete"
) -> int:
	if not is_ready():
		return OWNER_NONE
	var resolved_winner: int = (
		forced_winner
		if forced_winner in [OWNER_PLAYER, OWNER_OPPONENT]
		else _match.get_winner()
	)
	_session.finish_match(resolved_winner, reason)
	return resolved_winner


func begin_result_transition() -> Dictionary:
	if not is_ready() or not _session.begin_result_transition():
		return {"accepted": false, "winner": OWNER_NONE}
	return {
		"accepted": true,
		"winner": _session.result_winner,
	}


func prepare_result_destination(winner: int) -> StringName:
	if not is_ready():
		return &"ignored"
	if winner not in [OWNER_PLAYER, OWNER_OPPONENT]:
		_session.increment_round()
		return &"replay"
	_session.begin_reward()
	return &"reward"


func nearest_empty_cell(preferred: int) -> int:
	if _match == null:
		return clampi(preferred, 0, 8)
	if preferred >= 0 and preferred < 9 and _match.board[preferred] == null:
		return preferred
	var empty_cells: Array[int] = _match.get_empty_cells()
	if empty_cells.is_empty():
		return 0
	return empty_cells[0]
