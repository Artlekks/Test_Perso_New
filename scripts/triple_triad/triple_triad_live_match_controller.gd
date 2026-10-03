extends RefCounted

# Volatile live-match state for Triple Triad.
# Owns the selected hand/cell cursor, the active player deck, the starting hands
# used for reward resolution, and deterministic match setup helpers. It does
# not own UI nodes, persistence, progression, animation, or scene-tree state.

const SessionControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_session_controller.gd"
)

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const PHASE_SELECT_CARD := SessionControllerScript.PHASE_SELECT_CARD
const PHASE_SELECT_CELL := SessionControllerScript.PHASE_SELECT_CELL
const PHASE_AI := SessionControllerScript.PHASE_AI
const PHASE_RESULT := SessionControllerScript.PHASE_RESULT
const PHASE_REWARD := SessionControllerScript.PHASE_REWARD

var selected_hand_index: int = 0
var selected_cell_index: int = 4

var _active_player_deck: Array = []
var _starting_player_cards: Array = []
var _starting_opponent_cards: Array = []

var _match = null
var _match_flow = null
var _match_context = null
var _rng: RandomNumberGenerator = null


func initialize(
	match_state,
	match_flow_controller,
	match_context_controller,
	rng: RandomNumberGenerator
) -> void:
	_match = match_state
	_match_flow = match_flow_controller
	_match_context = match_context_controller
	_rng = rng


func is_ready() -> bool:
	return (
		_match != null
		and _match_flow != null
		and _match_context != null
		and _rng != null
	)


func set_active_player_deck(cards: Array) -> void:
	_active_player_deck = cards.duplicate()


func get_active_player_deck() -> Array:
	return _active_player_deck.duplicate()


func get_starting_player_cards() -> Array:
	return _starting_player_cards.duplicate()


func get_starting_opponent_cards() -> Array:
	return _starting_opponent_cards.duplicate()


func install_recovery_state(
	player_cards: Array,
	opponent_cards: Array
) -> void:
	_starting_player_cards = player_cards.duplicate()
	_starting_opponent_cards = opponent_cards.duplicate()
	_active_player_deck = player_cards.duplicate()
	selected_hand_index = 0
	selected_cell_index = 4


func prepare_new_match(
	player_cards_override: Array,
	opponent_collection_backend
) -> Dictionary:
	if not is_ready():
		return {"success": false, "reason": "runtime_not_initialized"}

	if int(_match_context.qa_hand_seed) > 0:
		_rng.seed = int(_match_context.qa_hand_seed)

	var player_cards: Array = []
	if player_cards_override.size() == 5:
		player_cards = player_cards_override.duplicate()
	elif _active_player_deck.size() == 5:
		player_cards = _active_player_deck.duplicate()
	else:
		player_cards = _match_context.build_budgeted_hand()
	if player_cards.size() != 5:
		return {"success": false, "reason": "invalid_player_deck"}

	var opponent_cards: Array = []
	if opponent_collection_backend != null:
		opponent_cards = opponent_collection_backend.build_match_deck(
			5,
			int(_match_context.active_deck_budget),
			_match_context.active_opponent_evolution
		)
	if opponent_cards.size() != 5:
		return {"success": false, "reason": "invalid_opponent_deck"}

	var starting_owner: int = OWNER_NONE
	match int(_match_context.qa_forced_starting_owner):
		OWNER_PLAYER:
			starting_owner = OWNER_PLAYER
		OWNER_OPPONENT:
			starting_owner = OWNER_OPPONENT
		_:
			if _rng.randi_range(0, 1) == 0:
				starting_owner = OWNER_PLAYER
			else:
				starting_owner = OWNER_OPPONENT

	var flow: Dictionary = _match_flow.prepare_match(
		player_cards,
		opponent_cards,
		starting_owner,
		_match_context.active_rule_set,
		_match_context.active_region_profile
	)
	if not bool(flow.get("success", false)):
		return flow

	_starting_player_cards = player_cards.duplicate()
	_starting_opponent_cards = opponent_cards.duplicate()
	selected_hand_index = int(flow.get("selected_hand_index", 0))
	selected_cell_index = int(flow.get("selected_cell_index", 4))
	return {
		"success": true,
		"starting_owner": int(flow.get("starting_owner", starting_owner)),
		"player_cards": player_cards.duplicate(),
		"opponent_cards": opponent_cards.duplicate(),
		"selected_hand_index": selected_hand_index,
		"selected_cell_index": selected_cell_index,
	}


func move_hand_selection(step: int) -> bool:
	if _match == null or step == 0:
		return false
	var before: int = selected_hand_index
	selected_hand_index = clampi(
		selected_hand_index + step,
		0,
		maxi(_match.player_hand.size() - 1, 0)
	)
	return selected_hand_index != before


func begin_cell_selection() -> int:
	if _match_flow == null:
		return selected_cell_index
	selected_cell_index = _match_flow.nearest_empty_cell(selected_cell_index)
	return selected_cell_index


func move_board_selection(
	action: StringName,
	input_controller
) -> bool:
	if input_controller == null:
		return false
	var next_index: int = int(
		input_controller.move_board_cursor(selected_cell_index, action)
	)
	if next_index == selected_cell_index:
		return false
	selected_cell_index = next_index
	return true


func apply_player_move_result(flow: Dictionary) -> void:
	selected_hand_index = int(
		flow.get("next_hand_index", selected_hand_index)
	)


func apply_ai_move_result(next_step: Dictionary) -> void:
	selected_hand_index = int(
		next_step.get("selected_hand_index", selected_hand_index)
	)
	selected_cell_index = int(
		next_step.get("selected_cell_index", selected_cell_index)
	)


func set_selected_hand_index(value: int) -> void:
	selected_hand_index = maxi(0, value)


func try_rotate_selected_card() -> Dictionary:
	if _match == null:
		return {"success": false, "message": "Rotate unavailable."}
	if (
		selected_hand_index < 0
		or selected_hand_index >= _match.player_hand.size()
	):
		return {"success": false, "message": "Rotate unavailable."}
	if _match.rotate_hand_card(OWNER_PLAYER, selected_hand_index):
		return {"success": true, "message": "ROTATE! One use spent."}
	return {"success": false, "message": "Rotate already used."}


func remove_card_from_active_deck(card_id: StringName) -> Array:
	var filtered: Array = []
	for card in _active_player_deck:
		if card == null:
			continue
		if String(card.card_id) == String(card_id):
			continue
		filtered.append(card)
	_active_player_deck = filtered
	return _active_player_deck.duplicate()


func capture_message(result: Dictionary) -> String:
	var combo_captured: Array = result.get("combo_captured", [])
	var same_triggered: bool = bool(result.get("same_triggered", false))
	var plus_triggered: bool = bool(result.get("plus_triggered", false))

	var special_text: String = ""
	if same_triggered and plus_triggered:
		special_text = "SAME + PLUS!"
	elif same_triggered:
		special_text = "SAME!"
	elif plus_triggered:
		special_text = "PLUS!"

	if special_text.is_empty():
		return ""
	if not combo_captured.is_empty():
		return "%s  COMBO x%d" % [special_text, combo_captured.size()]
	return special_text


func current_help_entries(phase: int) -> Array:
	var entries: Array = []
	match phase:
		PHASE_SELECT_CARD:
			entries.append({"key": "W/S", "action": "Card"})
			entries.append({"key": "K", "action": "Select"})
			if _match != null and _match.can_rotate(OWNER_PLAYER):
				entries.append({"key": "R", "action": "Rotate"})
			entries.append({"key": "I", "action": "Surrender"})
		PHASE_SELECT_CELL:
			entries.append({"key": "WASD", "action": "Move"})
			entries.append({"key": "K", "action": "Place"})
			if _match != null and _match.can_rotate(OWNER_PLAYER):
				entries.append({"key": "R", "action": "Rotate"})
			entries.append({"key": "I", "action": "Back"})
		PHASE_AI:
			entries.append({"key": "I", "action": "Surrender"})
		PHASE_RESULT:
			entries.append({"key": "K", "action": "Continue"})
		PHASE_REWARD:
			entries.append({"key": "K", "action": "Continue"})
	return entries
