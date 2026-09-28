extends CanvasLayer

signal opened
signal closed
signal match_finished(result: Dictionary)

const MatchScript = preload("res://scripts/triple_triad/triple_triad_match.gd")
const AIScript = preload("res://scripts/triple_triad/triple_triad_ai.gd")
const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const PHASE_CLOSED := 0
const PHASE_SELECT_CARD := 1
const PHASE_SELECT_CELL := 2
const PHASE_AI := 3
const PHASE_FINISHED := 4

@export var card_catalog: Resource
@export var rule_set: Resource
@export_range(1, 10, 1) var prototype_min_level: int = 1
@export_range(1, 10, 1) var prototype_max_level: int = 3
@export_range(0.0, 2.0, 0.05) var ai_delay_seconds: float = 0.35

@onready var root: Control = $Root
@onready var opponent_hand_container: Control = $Root/OpponentHand
@onready var board_container: GridContainer = $Root/Board
@onready var player_hand_container: Control = $Root/PlayerHand
@onready var opponent_score_label: Label = $Root/OpponentScoreLabel
@onready var player_score_label: Label = $Root/PlayerScoreLabel
@onready var turn_label: Label = $Root/TurnLabel
@onready var message_label: Label = $Root/MessageLabel
@onready var help_label: Label = $Root/HelpLabel
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	_match = MatchScript.new()
	_ai = AIScript.new()
	_rng.randomize()
	_build_views()
	ai_timer.timeout.connect(_on_ai_timer_timeout)
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
	_phase = PHASE_CLOSED
	root.visible = false
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = _previous_pause
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not _pressed(event):
		return

	if _phase == PHASE_FINISHED:
		if _is_confirm(event):
			_start_new_match()
			get_viewport().set_input_as_handled()
			return
		if _is_back(event):
			close_game()
			get_viewport().set_input_as_handled()
			return

	if _phase == PHASE_AI:
		if _is_back(event):
			close_game()
			get_viewport().set_input_as_handled()
		return

	if _phase == PHASE_SELECT_CARD:
		var horizontal: int = _horizontal_step(event)
		if horizontal != 0:
			_selected_hand_index = clampi(_selected_hand_index + horizontal, 0, maxi(_match.player_hand.size() - 1, 0))
			_refresh_views()
			get_viewport().set_input_as_handled()
			return
		if _is_confirm(event) and not _match.player_hand.is_empty():
			_phase = PHASE_SELECT_CELL
			_selected_cell_index = _find_nearest_empty_cell(_selected_cell_index)
			_refresh_views()
			get_viewport().set_input_as_handled()
			return
		if _is_back(event):
			close_game()
			get_viewport().set_input_as_handled()
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
			get_viewport().set_input_as_handled()
			return
		if _is_confirm(event):
			_try_player_move()
			get_viewport().set_input_as_handled()
			return
		if _is_back(event):
			_phase = PHASE_SELECT_CARD
			_refresh_views()
			get_viewport().set_input_as_handled()


func _start_new_match() -> void:
	ai_timer.stop()
	var player_cards: Array = card_catalog.build_random_hand(_rng, prototype_min_level, prototype_max_level, 5)
	var opponent_cards: Array = card_catalog.build_random_hand(_rng, prototype_min_level, prototype_max_level, 5)
	var starting_owner: int = OWNER_PLAYER if _rng.randi_range(0, 1) == 0 else OWNER_OPPONENT
	_match.reset_match(player_cards, opponent_cards, starting_owner, rule_set)
	_selected_hand_index = 0
	_selected_cell_index = 4
	message_label.text = ""
	if starting_owner == OWNER_PLAYER:
		_phase = PHASE_SELECT_CARD
	else:
		_phase = PHASE_AI
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
	var result: Dictionary = _match.place_card(OWNER_PLAYER, _selected_hand_index, _selected_cell_index)
	if not bool(result.get("success", false)):
		message_label.text = "Invalid move."
		return
	_selected_hand_index = clampi(_selected_hand_index, 0, maxi(_match.player_hand.size() - 1, 0))
	message_label.text = _capture_message(result)
	if bool(result.get("game_over", false)):
		_finish_match()
	else:
		_phase = PHASE_AI
		_refresh_views()
		_schedule_ai()


func _on_ai_timer_timeout() -> void:
	if _phase != PHASE_AI or _match.game_over:
		return
	var move: Dictionary = _ai.choose_move(_match, OWNER_OPPONENT, _rng)
	if not bool(move.get("valid", false)):
		_finish_match()
		return
	var result: Dictionary = _match.place_card(
		OWNER_OPPONENT,
		int(move.get("hand_index", 0)),
		int(move.get("cell_index", 0))
	)
	message_label.text = _capture_message(result)
	if bool(result.get("game_over", false)):
		_finish_match()
	else:
		_phase = PHASE_SELECT_CARD
		_selected_hand_index = clampi(_selected_hand_index, 0, maxi(_match.player_hand.size() - 1, 0))
		_selected_cell_index = _find_nearest_empty_cell(_selected_cell_index)
		_refresh_views()


func _finish_match() -> void:
	_phase = PHASE_FINISHED
	var score: Dictionary = _match.get_score()
	var winner: int = _match.get_winner()
	match winner:
		OWNER_PLAYER:
			message_label.text = "YOU WIN  %d - %d" % [int(score["player"]), int(score["opponent"])]
		OWNER_OPPONENT:
			message_label.text = "YOU LOSE  %d - %d" % [int(score["player"]), int(score["opponent"])]
		_:
			message_label.text = "DRAW  %d - %d" % [int(score["player"]), int(score["opponent"])]
	_refresh_views()
	match_finished.emit({
		"winner": winner,
		"score": score,
	})


func _schedule_ai() -> void:
	ai_timer.start(maxf(ai_delay_seconds, 0.01))


func _build_views() -> void:
	const HAND_STEP_Y := 58.0
	for index in range(5):
		var opponent_view = CardViewScene.instantiate()
		opponent_hand_container.add_child(opponent_view)
		opponent_view.position = Vector2(0.0, index * HAND_STEP_Y)
		opponent_view.z_index = index
		_opponent_views.append(opponent_view)
	for _index in range(9):
		var board_view = CardViewScene.instantiate()
		board_container.add_child(board_view)
		_board_views.append(board_view)
	for index in range(5):
		var player_view = CardViewScene.instantiate()
		player_hand_container.add_child(player_view)
		player_view.position = Vector2(0.0, index * HAND_STEP_Y)
		player_view.z_index = index
		_player_views.append(player_view)


func _refresh_views() -> void:
	if _match == null:
		return
	var show_opponent_cards: bool = rule_set != null and bool(rule_set.open_rule)
	for index in range(_opponent_views.size()):
		var view = _opponent_views[index]
		if index < _match.opponent_hand.size():
			view.visible = true
			view.configure(_match.opponent_hand[index], OWNER_OPPONENT, not show_opponent_cards)
			view.set_selected(false)
			view.z_index = index
		else:
			view.visible = false

	for index in range(_player_views.size()):
		var view = _player_views[index]
		if index < _match.player_hand.size():
			view.visible = true
			view.configure(_match.player_hand[index], OWNER_PLAYER, false)
			var is_selected: bool = _phase == PHASE_SELECT_CARD and index == _selected_hand_index
			view.set_selected(is_selected)
			view.z_index = 20 if is_selected else index
		else:
			view.visible = false

	for cell_index in range(_board_views.size()):
		var board_view = _board_views[cell_index]
		var slot_variant = _match.board[cell_index]
		if slot_variant == null:
			board_view.configure(null, OWNER_NONE, false)
		else:
			var slot: Dictionary = slot_variant
			board_view.configure(slot["card"], int(slot["owner"]), false)
		board_view.set_selected(_phase == PHASE_SELECT_CELL and cell_index == _selected_cell_index)

	var score: Dictionary = _match.get_score()
	opponent_score_label.text = str(int(score["opponent"]))
	player_score_label.text = str(int(score["player"]))
	match _phase:
		PHASE_SELECT_CARD:
			turn_label.text = "Your turn: choose a card"
			help_label.text = "A/D: Card   K: Select   I: Leave"
		PHASE_SELECT_CELL:
			turn_label.text = "Choose a board space"
			help_label.text = "W/A/S/D: Move   K: Place   I: Back"
		PHASE_AI:
			turn_label.text = "Opponent's turn"
			help_label.text = "I: Leave"
		PHASE_FINISHED:
			turn_label.text = "Match complete"
			help_label.text = "K: Play again   I: Leave"


func _capture_message(result: Dictionary) -> String:
	var captured: Array = result.get("captured", [])
	if captured.is_empty():
		return ""
	return "Captured %d card%s!" % [captured.size(), "" if captured.size() == 1 else "s"]


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


func _horizontal_step(event: InputEvent) -> int:
	if _is_left(event):
		return -1
	if _is_right(event):
		return 1
	return 0


func _key_matches(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.keycode == key or key_event.physical_keycode == key
