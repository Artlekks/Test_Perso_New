extends CanvasLayer

signal opened
signal closed
signal match_finished(result: Dictionary)
signal card_reward_selected(card_definition)

const MatchScript = preload("res://scripts/triple_triad/triple_triad_match.gd")
const AIScript = preload("res://scripts/triple_triad/triple_triad_ai.gd")
const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const PHASE_CLOSED := 0
const PHASE_DEALING := 1
const PHASE_SELECT_CARD := 2
const PHASE_SELECT_CELL := 3
const PHASE_ANIMATING := 4
const PHASE_AI := 5
const PHASE_RESULT := 6
const PHASE_REWARD := 7

const HAND_STEP_Y := 64.0
const HAND_SELECTED_X_OFFSET := -10.0
const CAPTURE_SETTLE_SECONDS := 0.34
const RESULT_FADE_IN_SECONDS := 0.24
const RESULT_FADE_OUT_SECONDS := 0.30

@export var card_catalog: Resource
@export var rule_set: Resource
@export_range(1, 10, 1) var prototype_min_level: int = 1
@export_range(1, 10, 1) var prototype_max_level: int = 3
@export_range(0.0, 2.0, 0.05) var ai_delay_seconds: float = 0.75

@onready var root: Control = $Root
@onready var opponent_hand_container: Control = $Root/OpponentHand
@onready var board_container: GridContainer = $Root/Board
@onready var player_hand_container: Control = $Root/PlayerHand
@onready var opponent_score_label: Label = $Root/OpponentScoreLabel
@onready var player_score_label: Label = $Root/PlayerScoreLabel
@onready var turn_label: Label = $Root/TurnLabel
@onready var message_label: Label = $Root/MessageLabel
@onready var help_label: Label = $Root/HelpLabel
@onready var info_panel: ColorRect = $Root/InfoPanel
@onready var info_label: Label = $Root/InfoPanel/InfoLabel
@onready var selection_arrow: Polygon2D = $Root/SelectionArrow
@onready var turn_arrow: Polygon2D = $Root/TurnArrow
@onready var result_label: Label = $Root/ResultLabel
@onready var reward_view = $Root/TripleTriadRewardView
@onready var transition_fade: ColorRect = $Root/TransitionFade
@onready var animation_director = $AnimationDirector
@onready var ai_timer: Timer = $AITimer

var _match = null
var _ai = null
var _rng := RandomNumberGenerator.new()
var _phase: int = PHASE_CLOSED
var _selected_hand_index: int = 0
var _selected_cell_index: int = 4
var _previous_pause: bool = false
var _player_views: Array = []
var _opponent_views: Array = []
var _board_views: Array = []
var _starting_player_cards: Array = []
var _starting_opponent_cards: Array = []
var _last_info_name: String = ""
var _result_winner: int = OWNER_NONE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	transition_fade.visible = false
	transition_fade.modulate = Color(1, 1, 1, 0)
	_match = MatchScript.new()
	_ai = AIScript.new()
	_rng.randomize()
	_build_views()
	ai_timer.timeout.connect(_on_ai_timer_timeout)
	reward_view.reward_selected.connect(_on_reward_selected)
	reward_view.completed.connect(_on_reward_completed)
	reward_view.leave_requested.connect(_on_reward_leave_requested)
	if card_catalog != null and card_catalog.has_method("validate_catalog"):
		var audit: Dictionary = card_catalog.validate_catalog()
		if not bool(audit.get("valid", false)):
			push_error("TripleTriadGame: invalid card catalog: %s" % str(audit.get("errors", [])))


func is_open() -> bool:
	return _phase != PHASE_CLOSED


func open_game() -> void:
	if is_open() or card_catalog == null:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	_previous_pause = tree.paused
	root.visible = true
	_start_new_match()
	tree.paused = true
	opened.emit()


func close_game() -> void:
	if not is_open():
		return
	ai_timer.stop()
	reward_view.close_reward()
	transition_fade.visible = false
	transition_fade.modulate = Color(1, 1, 1, 0)
	_phase = PHASE_CLOSED
	root.visible = false
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = _previous_pause
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not _pressed(event):
		return

	# The reward view owns input while it is active.
	if _phase == PHASE_REWARD:
		return

	if _phase == PHASE_RESULT:
		if _is_confirm(event):
			_begin_result_transition()
			_accept_input()
			return
		if _is_back(event):
			close_game()
			_accept_input()
		return

	if _phase in [PHASE_DEALING, PHASE_ANIMATING, PHASE_AI]:
		if _is_back(event):
			close_game()
			_accept_input()
		return

	if _phase == PHASE_SELECT_CARD:
		var hand_step: int = _hand_step(event)
		if hand_step != 0:
			_selected_hand_index = clampi(
				_selected_hand_index + hand_step,
				0,
				maxi(_match.player_hand.size() - 1, 0)
			)
			_refresh_views()
			_accept_input()
			return
		if _is_confirm(event) and not _match.player_hand.is_empty():
			_phase = PHASE_SELECT_CELL
			_selected_cell_index = _find_nearest_empty_cell(_selected_cell_index)
			_refresh_views()
			_accept_input()
			return
		if _is_back(event):
			close_game()
			_accept_input()
			return

	if _phase == PHASE_SELECT_CELL:
		var moved: bool = false
		if _is_left(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, -1, 0)
			moved = true
		elif _is_right(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, 1, 0)
			moved = true
		elif _is_up(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, 0, -1)
			moved = true
		elif _is_down(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, 0, 1)
			moved = true
		if moved:
			_refresh_views()
			_accept_input()
			return
		if _is_confirm(event):
			_try_player_move()
			_accept_input()
			return
		if _is_back(event):
			_phase = PHASE_SELECT_CARD
			_refresh_views()
			_accept_input()


func _start_new_match() -> void:
	ai_timer.stop()
	reward_view.close_reward()
	result_label.visible = false
	transition_fade.visible = false
	transition_fade.modulate = Color(1, 1, 1, 0)
	_result_winner = OWNER_NONE
	message_label.text = ""
	_last_info_name = ""

	var player_cards: Array = card_catalog.build_random_hand(_rng, prototype_min_level, prototype_max_level, 5)
	var opponent_cards: Array = card_catalog.build_random_hand(_rng, prototype_min_level, prototype_max_level, 5)
	_starting_player_cards = player_cards.duplicate()
	_starting_opponent_cards = opponent_cards.duplicate()
	var starting_owner: int = OWNER_PLAYER if _rng.randi_range(0, 1) == 0 else OWNER_OPPONENT
	_match.reset_match(player_cards, opponent_cards, starting_owner, rule_set)
	_selected_hand_index = 0
	_selected_cell_index = 4
	_phase = PHASE_DEALING
	_refresh_views()
	_run_deal_sequence(starting_owner)


func _run_deal_sequence(starting_owner: int) -> void:
	await animation_director.deal_hands(_player_views, _opponent_views, HAND_STEP_Y)
	if not is_open() or _phase != PHASE_DEALING:
		return
	_phase = PHASE_SELECT_CARD if starting_owner == OWNER_PLAYER else PHASE_AI
	_refresh_views()
	if _phase == PHASE_AI:
		_schedule_ai()


func _try_player_move() -> void:
	if _selected_hand_index < 0 or _selected_hand_index >= _match.player_hand.size():
		return
	if _selected_cell_index < 0 or _selected_cell_index >= 9:
		return
	if _match.board[_selected_cell_index] != null:
		message_label.text = "That space is occupied."
		return

	var played_card = _match.player_hand[_selected_hand_index]
	var source_view: Control = _player_views[_selected_hand_index]
	var target_view: Control = _board_views[_selected_cell_index]
	var result: Dictionary = _match.place_card(OWNER_PLAYER, _selected_hand_index, _selected_cell_index)
	if not bool(result.get("success", false)):
		message_label.text = "Invalid move."
		return

	_phase = PHASE_ANIMATING
	_last_info_name = str(played_card.display_name)
	_refresh_phase_ui()
	await animation_director.animate_placement(root, source_view, target_view, played_card, OWNER_PLAYER)
	if not is_open():
		return

	_selected_hand_index = clampi(_selected_hand_index, 0, maxi(_match.player_hand.size() - 1, 0))
	message_label.text = _capture_message(result)
	var captured_cells: Array = result.get("captured", [])
	_refresh_views(captured_cells)
	if not captured_cells.is_empty():
		await get_tree().create_timer(CAPTURE_SETTLE_SECONDS, true).timeout
		if not is_open():
			return

	if bool(result.get("game_over", false)):
		_finish_match()
	else:
		_phase = PHASE_AI
		_refresh_views()
		_schedule_ai()


func _on_ai_timer_timeout() -> void:
	if _phase != PHASE_AI or _match.game_over:
		return
	_run_ai_turn()


func _run_ai_turn() -> void:
	var move: Dictionary = _ai.choose_move(_match, OWNER_OPPONENT, _rng)
	if not bool(move.get("valid", false)):
		_finish_match()
		return

	var hand_index: int = int(move.get("hand_index", 0))
	var cell_index: int = int(move.get("cell_index", 0))
	if hand_index < 0 or hand_index >= _match.opponent_hand.size():
		_finish_match()
		return

	var played_card = _match.opponent_hand[hand_index]
	var source_view: Control = _opponent_views[hand_index]
	var target_view: Control = _board_views[cell_index]
	var result: Dictionary = _match.place_card(OWNER_OPPONENT, hand_index, cell_index)
	if not bool(result.get("success", false)):
		_finish_match()
		return

	_phase = PHASE_ANIMATING
	_last_info_name = str(played_card.display_name)
	_refresh_phase_ui()
	await animation_director.animate_placement(root, source_view, target_view, played_card, OWNER_OPPONENT)
	if not is_open():
		return

	message_label.text = _capture_message(result)
	var captured_cells: Array = result.get("captured", [])
	_refresh_views(captured_cells)
	if not captured_cells.is_empty():
		await get_tree().create_timer(CAPTURE_SETTLE_SECONDS, true).timeout
		if not is_open():
			return

	if bool(result.get("game_over", false)):
		_finish_match()
	else:
		_phase = PHASE_SELECT_CARD
		_selected_hand_index = clampi(_selected_hand_index, 0, maxi(_match.player_hand.size() - 1, 0))
		_selected_cell_index = _find_nearest_empty_cell(_selected_cell_index)
		_refresh_views()


func _finish_match() -> void:
	_phase = PHASE_RESULT
	_refresh_views()
	var score: Dictionary = _match.get_score()
	_result_winner = _match.get_winner()
	match _result_winner:
		OWNER_PLAYER:
			result_label.text = "YOU WIN!"
		OWNER_OPPONENT:
			result_label.text = "YOU LOSE..."
		_:
			result_label.text = "DRAW"
	result_label.visible = true
	turn_label.text = ""
	help_label.text = "K: Continue"
	selection_arrow.visible = false
	turn_arrow.visible = false
	match_finished.emit({
		"winner": _result_winner,
		"score": score,
	})


func _begin_result_transition() -> void:
	if _phase != PHASE_RESULT:
		return
	_phase = PHASE_ANIMATING
	help_label.text = ""
	_run_result_transition(_result_winner)


func _run_result_transition(winner: int) -> void:
	transition_fade.visible = true
	transition_fade.modulate = Color(1, 1, 1, 0)
	var fade_in: Tween = transition_fade.create_tween()
	fade_in.set_trans(Tween.TRANS_QUAD)
	fade_in.set_ease(Tween.EASE_IN_OUT)
	fade_in.tween_property(transition_fade, "modulate", Color.WHITE, RESULT_FADE_IN_SECONDS)
	await fade_in.finished
	if not is_open():
		return

	result_label.visible = false
	if winner not in [OWNER_PLAYER, OWNER_OPPONENT]:
		close_game()
		return

	_phase = PHASE_REWARD
	reward_view.open_reward(
		_starting_opponent_cards,
		_starting_player_cards,
		winner,
		true
	)
	_refresh_phase_ui()

	# Reveal the result screen while both card rows begin sliding into place.
	reward_view.start_entrance()
	var fade_out: Tween = transition_fade.create_tween()
	fade_out.set_trans(Tween.TRANS_QUAD)
	fade_out.set_ease(Tween.EASE_IN_OUT)
	fade_out.tween_property(transition_fade, "modulate", Color(1, 1, 1, 0), RESULT_FADE_OUT_SECONDS)
	await fade_out.finished
	if not is_open():
		return
	transition_fade.visible = false


func _schedule_ai() -> void:
	ai_timer.start(maxf(ai_delay_seconds, 0.01))


func _build_views() -> void:
	for index in range(5):
		var opponent_view: Control = CardViewScene.instantiate() as Control
		opponent_hand_container.add_child(opponent_view)
		opponent_view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
		opponent_view.z_index = index
		_opponent_views.append(opponent_view)
	for _index in range(9):
		var board_view: Control = CardViewScene.instantiate() as Control
		board_container.add_child(board_view)
		_board_views.append(board_view)
	for index in range(5):
		var player_view: Control = CardViewScene.instantiate() as Control
		player_hand_container.add_child(player_view)
		player_view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
		player_view.z_index = index
		_player_views.append(player_view)


func _refresh_views(captured_cells: Array = []) -> void:
	if _match == null:
		return
	var show_opponent_cards: bool = rule_set == null or bool(rule_set.open_rule)

	for index in range(_opponent_views.size()):
		var view: Control = _opponent_views[index]
		view.modulate = Color.WHITE
		view.scale = Vector2.ONE
		if index < _match.opponent_hand.size():
			view.visible = true
			view.configure(_match.opponent_hand[index], OWNER_OPPONENT, not show_opponent_cards)
			view.set_selected(false)
			view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
			view.z_index = index
		else:
			view.visible = false

	for index in range(_player_views.size()):
		var view: Control = _player_views[index]
		view.modulate = Color.WHITE
		view.scale = Vector2.ONE
		if index < _match.player_hand.size():
			view.visible = true
			view.configure(_match.player_hand[index], OWNER_PLAYER, false)
			var is_selected: bool = (
				_phase in [PHASE_SELECT_CARD, PHASE_SELECT_CELL]
				and index == _selected_hand_index
			)
			# Selection is communicated by the side arrow + a small left nudge.
			# The ownership border remains blue instead of changing to yellow.
			view.set_selected(false)
			view.position = Vector2(
				HAND_SELECTED_X_OFFSET if is_selected else 0.0,
				float(index) * HAND_STEP_Y
			)
			view.z_index = index
		else:
			view.visible = false

	for cell_index in range(_board_views.size()):
		var board_view: Control = _board_views[cell_index]
		var slot_variant = _match.board[cell_index]
		if slot_variant == null:
			board_view.configure(null, OWNER_NONE, false)
		else:
			var slot: Dictionary = slot_variant
			board_view.configure(
				slot["card"],
				int(slot["owner"]),
				false,
				captured_cells.has(cell_index)
			)
		board_view.set_selected(_phase == PHASE_SELECT_CELL and cell_index == _selected_cell_index)

	var score: Dictionary = _match.get_score()
	opponent_score_label.text = str(int(score["opponent"]))
	player_score_label.text = str(int(score["player"]))
	_refresh_phase_ui()


func _refresh_phase_ui() -> void:
	selection_arrow.visible = false
	turn_arrow.visible = false
	info_panel.visible = _phase not in [PHASE_CLOSED, PHASE_REWARD]

	match _phase:
		PHASE_DEALING:
			turn_label.text = ""
			help_label.text = ""
			info_label.text = ""
		PHASE_SELECT_CARD:
			turn_label.text = "Your turn: choose a card"
			help_label.text = "W/S: Card   K: Select   I: Leave"
			_update_player_selection_markers()
			_update_selected_card_info()
		PHASE_SELECT_CELL:
			turn_label.text = "Choose a board space"
			help_label.text = "W/A/S/D: Move   K: Place   I: Back"
			_update_player_selection_markers()
			_update_selected_card_info()
		PHASE_AI:
			turn_label.text = "Opponent's turn"
			help_label.text = "I: Leave"
			_turn_arrow_for_owner(OWNER_OPPONENT)
			info_label.text = _last_info_name
		PHASE_ANIMATING:
			turn_label.text = ""
			help_label.text = ""
			info_label.text = _last_info_name
		PHASE_RESULT:
			turn_label.text = ""
			help_label.text = ""
		PHASE_REWARD:
			turn_label.text = ""
			help_label.text = ""
			info_panel.visible = false


func _update_player_selection_markers() -> void:
	if _match.player_hand.is_empty():
		return
	selection_arrow.visible = true
	selection_arrow.position = Vector2(
		player_hand_container.position.x - 16.0,
		player_hand_container.position.y + float(_selected_hand_index) * HAND_STEP_Y + 48.0
	)
	_turn_arrow_for_owner(OWNER_PLAYER)


func _turn_arrow_for_owner(turn_owner: int) -> void:
	turn_arrow.visible = true
	turn_arrow.position = Vector2(58.0, 31.0) if turn_owner == OWNER_OPPONENT else Vector2(574.0, 31.0)


func _update_selected_card_info() -> void:
	if _selected_hand_index < 0 or _selected_hand_index >= _match.player_hand.size():
		info_label.text = ""
		return
	var selected_card = _match.player_hand[_selected_hand_index]
	info_label.text = str(selected_card.display_name)


func _capture_message(result: Dictionary) -> String:
	var captured: Array = result.get("captured", [])
	if captured.is_empty():
		return ""
	return "Captured %d card%s!" % [captured.size(), "" if captured.size() == 1 else "s"]


func _on_reward_selected(card_definition) -> void:
	_last_info_name = str(card_definition.display_name)
	card_reward_selected.emit(card_definition)


func _on_reward_completed() -> void:
	reward_view.close_reward()
	close_game()


func _on_reward_leave_requested() -> void:
	close_game()


func _find_nearest_empty_cell(preferred: int) -> int:
	if preferred >= 0 and preferred < 9 and _match.board[preferred] == null:
		return preferred
	var empty_cells: Array[int] = _match.get_empty_cells()
	if empty_cells.is_empty():
		return 0
	return empty_cells[0]


func _move_board_cursor(current: int, dx: int, dy: int) -> int:
	var row: int = floori(float(current) / 3.0)
	var column: int = current % 3
	column = clampi(column + dx, 0, 2)
	row = clampi(row + dy, 0, 2)
	return row * 3 + column


func _accept_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo


func _is_confirm(event: InputEvent) -> bool:
	return _key_matches(event, KEY_K) or _key_matches(event, KEY_ENTER)


func _is_back(event: InputEvent) -> bool:
	return _key_matches(event, KEY_I) or _key_matches(event, KEY_ESCAPE)


func _is_left(event: InputEvent) -> bool:
	return _key_matches(event, KEY_A) or _key_matches(event, KEY_LEFT)


func _is_right(event: InputEvent) -> bool:
	return _key_matches(event, KEY_D) or _key_matches(event, KEY_RIGHT)


func _is_up(event: InputEvent) -> bool:
	return _key_matches(event, KEY_W) or _key_matches(event, KEY_UP)


func _is_down(event: InputEvent) -> bool:
	return _key_matches(event, KEY_S) or _key_matches(event, KEY_DOWN)


func _hand_step(event: InputEvent) -> int:
	if _is_up(event):
		return -1
	if _is_down(event):
		return 1
	return 0


func _key_matches(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.keycode == key or key_event.physical_keycode == key
